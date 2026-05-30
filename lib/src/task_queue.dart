import 'priority_level.dart';

// ────────────────────────────────────────────────────────────────────────────
// ScheduledTask
// ────────────────────────────────────────────────────────────────────────────

/// A unit of work registered with [SchedulerController].
///
/// A [ScheduledTask] wraps an async callback together with metadata that
/// the scheduler uses for ordering, budget calculations, expiry, and
/// diagnostic logging.
///
/// You typically create tasks implicitly through
/// [SchedulerController.schedule] rather than instantiating this class
/// directly.
class ScheduledTask {
  /// Creates a new [ScheduledTask].
  ///
  /// - [id] — unique identifier used for deduplication and logging.
  /// - [task] — the async function to execute.
  /// - [priority] — controls deferral and queue ordering.
  /// - [estimatedDurationMs] — hint for frame-budget calculations.
  /// - [maxWaitMs] — if set, the task is expired and dropped after waiting
  ///   this many milliseconds without executing.
  /// - [onDropped] — invoked when the task is dropped (queue full, expired,
  ///   or purged).
  ScheduledTask({
    required this.id,
    required this.task,
    required this.priority,
    required this.estimatedDurationMs,
    this.onDropped,
    this.maxWaitMs,
  }) : _createdAt = DateTime.now(),
       _effectivePriority = priority;

  // ──────────────────────────────────────────────────────────────────────────
  // Identity & work
  // ──────────────────────────────────────────────────────────────────────────

  /// Unique identifier for this task.
  ///
  /// Used for deduplication checks and log output. If two tasks share the
  /// same `id`, the second enqueue is a no-op.
  final String id;

  /// The async callback to execute.
  final Future<void> Function() task;

  // ──────────────────────────────────────────────────────────────────────────
  // Priority
  // ──────────────────────────────────────────────────────────────────────────

  /// The **original** priority assigned at creation time.
  final PriorityLevel priority;

  /// The **current effective** priority, which may be upgraded automatically
  /// when [SchedulerConfig.autoAdjustPriority] is enabled and the task is
  /// close to expiry.
  PriorityLevel _effectivePriority;

  /// Exposes the current effective priority.
  PriorityLevel get effectivePriority => _effectivePriority;

  /// Upgrades the effective priority by one level.
  ///
  /// Called by the scheduler when the task has been waiting for more than
  /// half of its [maxWaitMs] budget. Never upgrades past [PriorityLevel.critical].
  void upgradePriority() {
    _effectivePriority = _effectivePriority.upgraded;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Budget hint
  // ──────────────────────────────────────────────────────────────────────────

  /// Estimated execution duration in milliseconds.
  ///
  /// This is a **hint** — the scheduler uses it to avoid scheduling more
  /// work than the frame budget allows. Over-estimating causes less work
  /// per cycle; under-estimating may cause jank on individual frames.
  ///
  /// Default: 5.0ms. For heavy parsing/IO tasks, provide a realistic value.
  final double estimatedDurationMs;

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle callbacks
  // ──────────────────────────────────────────────────────────────────────────

  /// Called when the task is removed from the queue without executing.
  ///
  /// Triggered by:
  /// - Queue capacity overflow ([TaskQueue.isFull]).
  /// - Expiry ([maxWaitMs] exceeded).
  /// - FPS Danger zone purge ([TaskQueue.dropBelow]).
  /// - Explicit [TaskQueue.clear].
  final void Function()? onDropped;

  // ──────────────────────────────────────────────────────────────────────────
  // Expiry
  // ──────────────────────────────────────────────────────────────────────────

  /// Maximum time in milliseconds this task is willing to wait before being
  /// dropped. `null` means "wait indefinitely".
  ///
  /// Example: a task that shows a toast notification should have a short
  /// `maxWaitMs` (e.g. 2000ms) because showing it 10 seconds later is
  /// meaningless.
  final int? maxWaitMs;

  final DateTime _createdAt;

  /// How long this task has been waiting in the queue.
  Duration get waitTime => DateTime.now().difference(_createdAt);

  /// `true` if the task has exceeded its [maxWaitMs] budget.
  bool get isExpired {
    if (maxWaitMs == null) return false;
    return waitTime.inMilliseconds > maxWaitMs!;
  }

  /// `true` if the task has waited for more than half its [maxWaitMs] budget.
  ///
  /// Used by the auto-priority-adjust logic to bump the task's priority
  /// before it expires.
  bool get isHalfExpired {
    if (maxWaitMs == null) return false;
    return waitTime.inMilliseconds > (maxWaitMs! / 2);
  }

  /// Fraction of [maxWaitMs] already elapsed (0.0 – 1.0+).
  ///
  /// Returns 0.0 when [maxWaitMs] is null.
  double get expiryRatio {
    if (maxWaitMs == null) return 0.0;
    return (waitTime.inMilliseconds / maxWaitMs!).clamp(0.0, 1.5);
  }

  @override
  String toString() => 'ScheduledTask('
      'id: $id, '
      'priority: ${effectivePriority.displayName}, '
      'estimated: ${estimatedDurationMs}ms, '
      'waited: ${waitTime.inMilliseconds}ms)';
}

// ────────────────────────────────────────────────────────────────────────────
// TaskQueue
// ────────────────────────────────────────────────────────────────────────────

/// A bounded, priority-sorted queue for deferred [ScheduledTask] instances.
///
/// ## Ordering
///
/// Tasks are sorted in **descending effective priority** order. Within the
/// same priority level tasks are ordered by **insertion time** (FIFO),
/// preserving stable ordering across equal-priority tasks.
///
/// ## Capacity
///
/// When [isFull], [enqueue] returns `false` and does **not** discard any
/// existing task. The caller (scheduler) is responsible for invoking
/// `task.onDropped`.
///
/// ## Deduplication
///
/// If a task with the same [ScheduledTask.id] is already in the queue,
/// [enqueue] returns `false` without adding a duplicate.
///
/// ## Thread Safety
///
/// [TaskQueue] is **not** thread-safe. All calls must originate from the
/// Flutter engine thread (the UI isolate).
class TaskQueue {
  /// Creates a [TaskQueue] with the given maximum capacity.
  TaskQueue({required this.maxSize}) : assert(maxSize > 0);

  /// Maximum number of tasks the queue can hold simultaneously.
  final int maxSize;

  // Internal sorted list — highest effective priority first.
  final List<ScheduledTask> _queue = [];

  // Fast id-lookup set for O(1) deduplication checks.
  final Set<String> _ids = {};

  // ──────────────────────────────────────────────────────────────────────────
  // Queue state
  // ──────────────────────────────────────────────────────────────────────────

  /// Number of tasks currently in the queue.
  int get length => _queue.length;

  /// `true` when the queue contains no tasks.
  bool get isEmpty => _queue.isEmpty;

  /// `true` when the queue has reached [maxSize].
  bool get isFull => _queue.length >= maxSize;

  /// `true` if a task with the given [id] is already queued.
  bool containsId(String id) => _ids.contains(id);

  // ──────────────────────────────────────────────────────────────────────────
  // Mutation
  // ──────────────────────────────────────────────────────────────────────────

  /// Adds [task] to the queue in priority order.
  ///
  /// Returns `false` (without modifying the queue) if:
  /// - The queue is at [maxSize] capacity.
  /// - A task with the same [ScheduledTask.id] is already present.
  ///
  /// Returns `true` on success.
  bool enqueue(ScheduledTask task) {
    if (isFull) return false;
    if (_ids.contains(task.id)) return false;

    _queue.add(task);
    _ids.add(task.id);
    _sortQueue();

    return true;
  }

  /// Removes and returns the highest-priority (front) task.
  ///
  /// Returns `null` if the queue is empty.
  ScheduledTask? dequeue() {
    if (_queue.isEmpty) return null;
    final task = _queue.removeAt(0);
    _ids.remove(task.id);
    return task;
  }

  /// Returns the highest-priority task without removing it.
  ScheduledTask? peek() => _queue.isEmpty ? null : _queue.first;

  // ──────────────────────────────────────────────────────────────────────────
  // Maintenance
  // ──────────────────────────────────────────────────────────────────────────

  /// Removes all tasks whose [ScheduledTask.isExpired] returns `true`.
  ///
  /// Calls [ScheduledTask.onDropped] for each removed task.
  /// Returns the count of removed tasks.
  int pruneExpired() {
    final expired = _queue.where((t) => t.isExpired).toList();
    for (final task in expired) {
      _queue.remove(task);
      _ids.remove(task.id);
      task.onDropped?.call();
    }
    return expired.length;
  }

  /// Upgrades the effective priority of tasks that have consumed more than
  /// half of their [ScheduledTask.maxWaitMs] budget.
  ///
  /// After upgrading, re-sorts the queue so upgraded tasks bubble up.
  /// Returns the count of tasks that were upgraded.
  int upgradeHalfExpired() {
    int count = 0;
    for (final task in _queue) {
      if (task.isHalfExpired && task.effectivePriority != task.priority.upgraded) {
        task.upgradePriority();
        count++;
      }
    }
    if (count > 0) _sortQueue();
    return count;
  }

  /// Removes all tasks whose [ScheduledTask.effectivePriority] is
  /// **strictly lower** than [threshold].
  ///
  /// Calls [ScheduledTask.onDropped] for each removed task.
  void dropBelow(PriorityLevel threshold) {
    final toDrop = _queue
        .where((t) => t.effectivePriority.isLowerThan(threshold))
        .toList();
    for (final task in toDrop) {
      _queue.remove(task);
      _ids.remove(task.id);
      task.onDropped?.call();
    }
  }

  /// Removes all tasks from the queue, calling [ScheduledTask.onDropped]
  /// for each one.
  void clear() {
    for (final task in _queue) {
      task.onDropped?.call();
    }
    _queue.clear();
    _ids.clear();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Inspection
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns an unmodifiable view of all queued tasks in priority order.
  List<ScheduledTask> get tasks => List.unmodifiable(_queue);

  /// Returns all tasks of the given priority level (effective priority).
  List<ScheduledTask> tasksOfPriority(PriorityLevel p) =>
      _queue.where((t) => t.effectivePriority == p).toList();

  /// Returns the task at [index] (0 = highest priority).
  ScheduledTask operator [](int index) => _queue[index];

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Re-sorts the queue: descending by effective priority weight, then FIFO.
  void _sortQueue() {
    _queue.sort(
      (a, b) => b.effectivePriority.weight.compareTo(a.effectivePriority.weight),
    );
  }

  @override
  String toString() =>
      'TaskQueue(${_queue.length}/$maxSize tasks)';
}
