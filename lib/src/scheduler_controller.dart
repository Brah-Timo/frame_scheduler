import 'dart:async';
import 'package:flutter/scheduler.dart';

import 'fps_monitor.dart';
import 'frame_budget.dart';
import 'scheduler_config.dart';
import 'task_queue.dart';
import 'priority_level.dart';

// ────────────────────────────────────────────────────────────────────────────
// SchedulerController
// ────────────────────────────────────────────────────────────────────────────

/// The **central orchestrator** of `frame_scheduler`.
///
/// [SchedulerController] is a singleton that ties together the [FpsMonitor],
/// [TaskQueue], [FrameBudget], and scheduling logic into a single, clean API.
///
/// ## Lifecycle
///
/// ```
/// initialize(config) → start() → schedule() / runCritical() → stop() → dispose()
/// ```
///
/// The recommended integration point is [FrameSchedulerScope], which
/// manages the lifecycle automatically. For manual control:
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   SchedulerController.instance.initialize(
///     config: SchedulerConfig.performance(),
///   );
///   SchedulerController.instance.start();
///   runApp(const MyApp());
/// }
/// ```
///
/// ## Scheduling Model
///
/// ```
/// schedule(task, priority)
///       │
///       ▼
///  _shouldDefer(priority, zone)?
///       │
///   YES │                 NO
///       ▼                  ▼
///   TaskQueue          Execute now
///     │
///     ▼ (every deferCheckIntervalMs)
///  addPostFrameCallback → _processDeferredTasks
///     │
///     ▼
///  Execute tasks within frame budget
/// ```
///
/// ## Thread Safety
///
/// All public methods must be called from the **Flutter UI thread** (the
/// default isolate). The scheduler does not spawn its own threads.
class SchedulerController {
  SchedulerController._();

  static final SchedulerController _instance = SchedulerController._();

  /// Global singleton accessor.
  ///
  /// The singleton is safe to access from anywhere in the widget tree
  /// without a [BuildContext].
  static SchedulerController get instance => _instance;

  // ──────────────────────────────────────────────────────────────────────────
  // Internal state
  // ──────────────────────────────────────────────────────────────────────────

  late SchedulerConfig _config;
  late FpsMonitor _fpsMonitor;
  late TaskQueue _taskQueue;
  late FrameBudget _frameBudget;

  Timer? _deferredCheckTimer;
  bool _initialized = false;
  bool _running = false;

  FpsZone _currentZone = FpsZone.healthy;
  SchedulerMetrics _metrics = SchedulerMetrics.empty;

  // ──────────────────────────────────────────────────────────────────────────
  // Public read-only accessors
  // ──────────────────────────────────────────────────────────────────────────

  /// The active [SchedulerConfig].
  SchedulerConfig get config => _config;

  /// The current [FpsZone] derived from live FPS monitoring.
  FpsZone get currentZone => _currentZone;

  /// The most recently computed FPS value from [FpsMonitor].
  double get currentFps => _initialized ? _fpsMonitor.currentFps : 60.0;

  /// Number of tasks currently waiting in the deferred queue.
  int get pendingTaskCount => _initialized ? _taskQueue.length : 0;

  /// Whether the scheduler has been initialised and is actively running.
  bool get isRunning => _running;

  /// Cumulative performance metrics (requires [SchedulerConfig.enableMetrics]).
  ///
  /// Returns [SchedulerMetrics.empty] when metrics are disabled.
  SchedulerMetrics get metrics => _metrics;

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  /// Initialises the scheduler with the given [config].
  ///
  /// Must be called **once** before [start]. Calling [initialize] again
  /// after the scheduler is running first calls [stop] to cleanly restart
  /// with the new configuration.
  ///
  /// ```dart
  /// SchedulerController.instance.initialize(
  ///   config: SchedulerConfig.performance().withLogging(),
  /// );
  /// ```
  void initialize({SchedulerConfig? config}) {
    if (_running) stop();

    _config = config ?? SchedulerConfig.balanced();

    _fpsMonitor = FpsMonitor(
      windowSize: _config.fpsWindowSize,
      targetFps: _config.targetFps,
      onFpsChanged: _onFpsUpdated,
    );

    _taskQueue = TaskQueue(maxSize: _config.maxDeferredTasks);
    _frameBudget = FrameBudget(config: _config);
    _metrics = SchedulerMetrics.empty;
    _currentZone = FpsZone.healthy;
    _initialized = true;

    _debugLog('Initialized with config: $_config');
  }

  /// Starts FPS monitoring and activates the deferred-task processor.
  ///
  /// Requires [initialize] to have been called first.
  /// Safe to call multiple times — subsequent calls are no-ops.
  void start() {
    assert(_initialized, 'Call initialize() before start().');
    if (_running) return;
    _running = true;
    _fpsMonitor.start();
    _startDeferredProcessor();
    _debugLog('Started.');
  }

  /// Pauses FPS monitoring and the deferred-task processor.
  ///
  /// Queued tasks are **preserved** and will resume processing when [start]
  /// is called again. Use this when the app goes to background.
  void stop() {
    if (!_running) return;
    _running = false;
    _fpsMonitor.stop();
    _deferredCheckTimer?.cancel();
    _deferredCheckTimer = null;
    _debugLog('Stopped. ${_taskQueue.length} tasks remain in queue.');
  }

  /// Resets cumulative metrics to zero without stopping the scheduler.
  void resetMetrics() {
    _metrics = SchedulerMetrics.empty;
  }

  /// Permanently disposes this controller and releases all resources.
  ///
  /// After calling [dispose], the scheduler must be re-initialized before
  /// use. Typically called when the root widget is unmounted.
  void dispose() {
    stop();
    if (_initialized) {
      _taskQueue.clear();
      _fpsMonitor.dispose();
    }
    _initialized = false;
    _debugLog('Disposed.');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Core public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Schedules [task] for execution with FPS-aware deferral logic.
  ///
  /// ## Execution Decision
  ///
  /// | Zone     | Critical | High  | Normal | Low   |
  /// |----------|----------|-------|--------|-------|
  /// | Healthy  | Now      | Now   | Now    | Now   |
  /// | Warning  | Now      | Now   | Defer  | Defer |
  /// | Critical | Now      | Defer | Defer  | Drop  |
  /// | Danger   | Now      | Defer | Drop   | Drop  |
  ///
  /// ## Parameters
  ///
  /// - [task] — The async function to run. Must not throw — wrap in
  ///   try/catch if needed; uncaught errors are caught and logged.
  /// - [priority] — Task priority. Defaults to [PriorityLevel.normal].
  /// - [estimatedDurationMs] — Rough estimate for frame-budget calculations.
  ///   Defaults to 5.0ms.
  /// - [id] — Optional stable identifier for deduplication and logging.
  ///   Auto-generated if omitted.
  /// - [maxWaitMs] — Maximum milliseconds to wait in the deferred queue
  ///   before the task is expired and dropped. `null` = wait indefinitely.
  /// - [onDropped] — Callback invoked if the task is dropped without
  ///   executing (queue full, expired, or purged).
  ///
  /// ## Example
  ///
  /// ```dart
  /// await SchedulerController.instance.schedule(
  ///   () async => await preloadNextLevelAssets(),
  ///   priority: PriorityLevel.high,
  ///   estimatedDurationMs: 80.0,
  ///   id: 'preload_level_3',
  ///   maxWaitMs: 5000,
  ///   onDropped: () => print('Preload was dropped — FPS too low'),
  /// );
  /// ```
  Future<void> schedule(
    Future<void> Function() task, {
    PriorityLevel priority = PriorityLevel.normal,
    double estimatedDurationMs = 5.0,
    String? id,
    int? maxWaitMs,
    void Function()? onDropped,
  }) async {
    assert(_initialized && _running,
        'Call initialize() and start() before schedule().');

    final taskId = id ?? _generateId();
    final deferDecision = _deferDecision(priority);

    _debugLog(
      'schedule(${priority.emoji} ${priority.displayName}, id: $taskId) '
      '→ zone: ${_currentZone.emoji} → decision: ${deferDecision.name}',
    );

    switch (deferDecision) {
      case _TaskDecision.execute:
        await _executeNow(task, taskId);

      case _TaskDecision.defer:
        _deferTask(
          task: task,
          priority: priority,
          estimatedDurationMs: estimatedDurationMs,
          id: taskId,
          maxWaitMs: maxWaitMs,
          onDropped: onDropped,
        );

      case _TaskDecision.drop:
        _debugLog('Task $taskId dropped (zone: ${_currentZone.label}, '
            'priority: ${priority.displayName}).');
        onDropped?.call();
        _trackDrop();
    }
  }

  /// Executes [task] **immediately**, bypassing all FPS checks.
  ///
  /// Use only for true emergency operations (e.g., saving state before
  /// the app is terminated). In normal scenarios, prefer [schedule] with
  /// [PriorityLevel.critical].
  Future<void> runCritical(Future<void> Function() task) async {
    await _executeNow(task, 'critical_${_generateId()}');
  }

  /// Returns `true` if a task with the given [id] is currently queued.
  bool isQueued(String id) => _initialized && _taskQueue.containsId(id);

  /// Removes all tasks from the deferred queue.
  ///
  /// Each dropped task's [ScheduledTask.onDropped] callback is invoked.
  void clearQueue() {
    if (!_initialized) return;
    final count = _taskQueue.length;
    _taskQueue.clear();
    _debugLog('Queue cleared. $count tasks dropped.');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal — decision logic
  // ──────────────────────────────────────────────────────────────────────────

  /// Computes the scheduling decision for a task based on current zone and
  /// priority.
  ///
  /// Returns one of [_TaskDecision.execute], [_TaskDecision.defer], or
  /// [_TaskDecision.drop].
  _TaskDecision _deferDecision(PriorityLevel priority) {
    switch (_currentZone) {
      // ── Healthy ─────────────────────────────────────────────────────────
      case FpsZone.healthy:
        return _TaskDecision.execute; // Never defer in healthy zone

      // ── Warning ─────────────────────────────────────────────────────────
      case FpsZone.warning:
        switch (priority) {
          case PriorityLevel.critical:
          case PriorityLevel.high:
            return _TaskDecision.execute;
          case PriorityLevel.normal:
          case PriorityLevel.low:
            return _TaskDecision.defer;
        }

      // ── Critical ────────────────────────────────────────────────────────
      case FpsZone.critical:
        switch (priority) {
          case PriorityLevel.critical:
            return _TaskDecision.execute;
          case PriorityLevel.high:
            return _TaskDecision.defer;
          case PriorityLevel.normal:
          case PriorityLevel.low:
            return _TaskDecision.drop;
        }

      // ── Danger ──────────────────────────────────────────────────────────
      case FpsZone.danger:
        switch (priority) {
          case PriorityLevel.critical:
            return _TaskDecision.execute;
          case PriorityLevel.high:
          case PriorityLevel.normal:
          case PriorityLevel.low:
            return _TaskDecision.drop;
        }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal — execution
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _executeNow(
    Future<void> Function() task,
    String id,
  ) async {
    final sw = Stopwatch()..start();
    try {
      await task();
    } catch (e, st) {
      _debugLog('Task $id threw: $e\n$st');
    } finally {
      sw.stop();
      _trackExecution(sw.elapsedMilliseconds.toDouble());
      _debugLog('Task $id executed in ${sw.elapsedMilliseconds}ms.');
    }
  }

  void _deferTask({
    required Future<void> Function() task,
    required PriorityLevel priority,
    required double estimatedDurationMs,
    required String id,
    int? maxWaitMs,
    void Function()? onDropped,
  }) {
    final scheduledTask = ScheduledTask(
      id: id,
      task: task,
      priority: priority,
      estimatedDurationMs: estimatedDurationMs,
      onDropped: onDropped,
      maxWaitMs: maxWaitMs,
    );

    final added = _taskQueue.enqueue(scheduledTask);

    if (!added) {
      _debugLog('Task $id could not be queued (full or duplicate). Dropping.');
      onDropped?.call();
      _trackDrop();
      return;
    }

    _trackDefer();

    if (_config.enableMetrics) {
      final current = _taskQueue.length;
      if (current > _metrics.peakQueueLength) {
        _metrics = _metrics.copyWith(peakQueueLength: current);
      }
    }

    _debugLog(
      'Task $id deferred (queue: ${_taskQueue.length}/${_config.maxDeferredTasks}).',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal — FPS update handler
  // ──────────────────────────────────────────────────────────────────────────

  void _onFpsUpdated(double fps) {
    final newZone = FrameBudget.computeZone(fps: fps, config: _config);

    if (newZone != _currentZone) {
      _debugLog(
        'Zone transition: ${_currentZone.emoji} → ${newZone.emoji} '
        '(FPS: ${fps.toStringAsFixed(1)})',
      );

      _currentZone = newZone;
      _trackZoneTransition();

      // In Danger zone: immediately purge all non-critical tasks to relieve
      // UI thread pressure rather than waiting for the next timer tick.
      if (_currentZone == FpsZone.danger) {
        _taskQueue.dropBelow(PriorityLevel.critical);
        _debugLog('Danger zone — non-critical tasks purged from queue.');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal — deferred task processor
  // ──────────────────────────────────────────────────────────────────────────

  void _startDeferredProcessor() {
    _deferredCheckTimer = Timer.periodic(
      Duration(milliseconds: _config.deferCheckIntervalMs),
      (_) {
        if (_taskQueue.isEmpty) return;
        // Schedule execution after the current frame to avoid interfering
        // with the build/raster phases.
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => _processDeferredTasks(),
        );
      },
    );
  }

  Future<void> _processDeferredTasks() async {
    if (_taskQueue.isEmpty) return;
    if (_currentZone.isSevere) return; // Only process in healthy/warning

    // 1. Prune expired tasks
    final pruned = _taskQueue.pruneExpired();
    if (pruned > 0) {
      _trackExpiry(pruned);
      _debugLog('Pruned $pruned expired tasks.');
    }

    // 2. Auto-adjust priority for half-expired tasks
    if (_config.autoAdjustPriority) {
      final upgraded = _taskQueue.upgradeHalfExpired();
      if (upgraded > 0) {
        _debugLog('Auto-upgraded $upgraded tasks approaching expiry.');
      }
    }

    // 3. Execute tasks within the frame budget
    double usedBudgetMs = 0.0;

    while (!_taskQueue.isEmpty) {
      final next = _taskQueue.peek();
      if (next == null) break;

      // Re-check defer decision with current zone (may have changed since
      // the timer fired).
      final decision = _deferDecision(next.effectivePriority);
      if (decision != _TaskDecision.execute) break;

      // Check frame budget
      if (!_frameBudget.canFit(
        taskEstimatedMs: next.estimatedDurationMs,
        usedMs: usedBudgetMs,
      )) {
        _debugLog(
          'Frame budget exhausted (used: ${usedBudgetMs.toStringAsFixed(2)}ms / '
          '${_frameBudget.safeBudgetMs.toStringAsFixed(2)}ms). '
          'Leaving ${_taskQueue.length} tasks for next cycle.',
        );
        break;
      }

      final task = _taskQueue.dequeue()!;
      final sw = Stopwatch()..start();

      try {
        await task.task();
      } catch (e, st) {
        _debugLog('Deferred task ${task.id} threw: $e\n$st');
      } finally {
        sw.stop();
        usedBudgetMs += sw.elapsedMilliseconds;
        _trackExecution(sw.elapsedMilliseconds.toDouble());
        _debugLog(
          'Deferred task ${task.id} executed in ${sw.elapsedMilliseconds}ms '
          '(budget used: ${usedBudgetMs.toStringAsFixed(1)}ms).',
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal — metrics helpers
  // ──────────────────────────────────────────────────────────────────────────

  void _trackExecution(double durationMs) {
    if (!_config.enableMetrics) return;
    _metrics = _metrics.copyWith(
      executedCount: _metrics.executedCount + 1,
      totalExecutionMs: _metrics.totalExecutionMs + durationMs,
    );
  }

  void _trackDefer() {
    if (!_config.enableMetrics) return;
    _metrics = _metrics.copyWith(
      deferredCount: _metrics.deferredCount + 1,
    );
  }

  void _trackDrop() {
    if (!_config.enableMetrics) return;
    _metrics = _metrics.copyWith(
      droppedCount: _metrics.droppedCount + 1,
    );
  }

  void _trackExpiry(int count) {
    if (!_config.enableMetrics) return;
    _metrics = _metrics.copyWith(
      expiredCount: _metrics.expiredCount + count,
    );
  }

  void _trackZoneTransition() {
    if (!_config.enableMetrics) return;
    _metrics = _metrics.copyWith(
      zoneTransitions: _metrics.zoneTransitions + 1,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal — utilities
  // ──────────────────────────────────────────────────────────────────────────

  int _idCounter = 0;

  String _generateId() =>
      'task_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  void _debugLog(String message) {
    if (_config.enableLogging) {
      // ignore: avoid_print
      print('[frame_scheduler] $message');
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _TaskDecision (internal)
// ────────────────────────────────────────────────────────────────────────────

/// Internal enum representing the outcome of [SchedulerController._deferDecision].
enum _TaskDecision {
  /// Execute the task immediately in the current call stack.
  execute,

  /// Add the task to the priority queue for later execution.
  defer,

  /// Discard the task and invoke its `onDropped` callback.
  drop,
}

// ────────────────────────────────────────────────────────────────────────────
// Convenience type alias
// ────────────────────────────────────────────────────────────────────────────

/// Convenient alias for [SchedulerController].
///
/// ```dart
/// FrameScheduler.instance.schedule(myTask);
/// ```
typedef FrameScheduler = SchedulerController;
