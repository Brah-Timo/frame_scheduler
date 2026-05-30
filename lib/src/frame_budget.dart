import 'scheduler_config.dart';

// ────────────────────────────────────────────────────────────────────────────
// FpsZone
// ────────────────────────────────────────────────────────────────────────────

/// Represents the current performance health zone of the application.
///
/// Zones are computed from the live FPS value and the thresholds defined
/// in [SchedulerConfig]. The zone is the primary input to the deferral
/// decision tree in [SchedulerController].
///
/// ## Zone Boundaries (default `balanced` config, 60 FPS target)
///
/// ```
///  60 FPS ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ 🟢 Healthy  — all tasks execute
///  48 FPS ─────────────────── threshold  (warningFpsThreshold)
///  30 FPS ─────────────────── threshold  (criticalFpsThreshold)
///  15 FPS ─────────────────── threshold  (dangerFpsThreshold)
///   0 FPS ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ 💀 Danger   — only critical tasks run
/// ```
enum FpsZone {
  /// FPS is at or near the target. All tasks execute immediately.
  healthy,

  /// FPS is slightly degraded (below [SchedulerConfig.warningFpsThreshold]).
  /// [PriorityLevel.normal] and [PriorityLevel.low] tasks are deferred.
  warning,

  /// FPS is significantly degraded (below [SchedulerConfig.criticalFpsThreshold]).
  /// Only [PriorityLevel.critical] and [PriorityLevel.high] tasks execute.
  critical,

  /// FPS is dangerously low (below [SchedulerConfig.dangerFpsThreshold]).
  /// All non-critical tasks are **dropped**, not deferred.
  /// The scheduler also triggers aggressive queue pruning.
  danger,
}

/// Extension providing rich metadata for each [FpsZone].
extension FpsZoneExtension on FpsZone {
  // ──────────────────────────────────────────────────────────────────────────
  // Display
  // ──────────────────────────────────────────────────────────────────────────

  /// Single emoji indicator for compact overlays and log output.
  String get emoji {
    switch (this) {
      case FpsZone.healthy:
        return '🟢';
      case FpsZone.warning:
        return '🟡';
      case FpsZone.critical:
        return '🔴';
      case FpsZone.danger:
        return '💀';
    }
  }

  /// Short title used in [FpsOverlay] and logging.
  String get label {
    switch (this) {
      case FpsZone.healthy:
        return 'Healthy';
      case FpsZone.warning:
        return 'Warning';
      case FpsZone.critical:
        return 'Critical';
      case FpsZone.danger:
        return 'Danger';
    }
  }

  /// Full description suitable for developer tooling and dashboards.
  String get description {
    switch (this) {
      case FpsZone.healthy:
        return 'Healthy — All tasks execute normally';
      case FpsZone.warning:
        return 'Warning — Normal & Low priority tasks deferred';
      case FpsZone.critical:
        return 'Critical — Only High & Critical tasks execute';
      case FpsZone.danger:
        return 'Danger — Only Critical tasks execute; others dropped';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Severity helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Numeric severity level (higher = worse performance).
  int get severity {
    switch (this) {
      case FpsZone.healthy:
        return 0;
      case FpsZone.warning:
        return 1;
      case FpsZone.critical:
        return 2;
      case FpsZone.danger:
        return 3;
    }
  }

  /// `true` for [FpsZone.critical] and [FpsZone.danger].
  bool get isSevere => severity >= 2;

  /// `true` only when the zone is [FpsZone.healthy].
  bool get isHealthy => this == FpsZone.healthy;
}

// ────────────────────────────────────────────────────────────────────────────
// FrameBudget
// ────────────────────────────────────────────────────────────────────────────

/// Calculates and tracks the **time budget** available for executing
/// scheduled tasks within a single rendering frame.
///
/// ## What is a Frame Budget?
///
/// At 60 FPS, the engine produces one frame every ~16.67ms. Flutter uses
/// this time for the **build phase** (widget tree diffing) and the
/// **raster phase** (GPU paint). Whatever is left can be used by the
/// application for additional work.
///
/// [FrameBudget] reserves a configurable fraction ([SchedulerConfig.safeBudgetRatio])
/// of the total frame time for scheduled tasks:
///
/// ```
/// Total budget (16.67 ms) × safeBudgetRatio (0.70) = Safe budget (11.67 ms)
/// ```
///
/// The scheduler never dispatches more work than fits in the safe budget of
/// a single post-frame callback, preventing cascading jank.
///
/// ## Formula
///
/// ```
///   totalBudgetMs = 1000 / targetFps
///   safeBudgetMs  = totalBudgetMs × safeBudgetRatio
///   canFit(task)  = (usedMs + task.estimatedMs) ≤ safeBudgetMs
/// ```
///
/// ## Zone Computation
///
/// The static [computeZone] method maps a raw FPS value to an [FpsZone]
/// using the thresholds from [SchedulerConfig].
class FrameBudget {
  /// Creates a [FrameBudget] for the given [config].
  FrameBudget({required this.config});

  /// The scheduler configuration from which FPS targets and budget ratios
  /// are read.
  final SchedulerConfig config;

  // ──────────────────────────────────────────────────────────────────────────
  // Budget accessors
  // ──────────────────────────────────────────────────────────────────────────

  /// Total wall-clock time available per frame in milliseconds.
  ///
  /// ```
  /// totalBudgetMs = 1000 / targetFps
  /// ```
  ///
  /// At 60 FPS → 16.67 ms | At 120 FPS → 8.33 ms
  double get totalBudgetMs => 1000.0 / config.targetFps;

  /// The portion of [totalBudgetMs] available for scheduled tasks.
  ///
  /// ```
  /// safeBudgetMs = totalBudgetMs × safeBudgetRatio
  /// ```
  ///
  /// At 60 FPS with ratio 0.70 → 11.67 ms
  double get safeBudgetMs => totalBudgetMs * config.safeBudgetRatio;

  // ──────────────────────────────────────────────────────────────────────────
  // Budget calculations
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns `true` if a task with the given estimated duration fits within
  /// the remaining budget for this frame.
  ///
  /// [taskEstimatedMs] — estimated execution time of the candidate task.
  /// [usedMs] — milliseconds already consumed by previously executed tasks
  ///            in the same post-frame callback.
  bool canFit({
    required double taskEstimatedMs,
    required double usedMs,
  }) {
    return (usedMs + taskEstimatedMs) <= safeBudgetMs;
  }

  /// Returns the remaining budget in milliseconds after [usedMs] has been
  /// consumed. Clamped to [0, safeBudgetMs].
  double remaining(double usedMs) =>
      (safeBudgetMs - usedMs).clamp(0.0, safeBudgetMs);

  /// Fraction of the safe budget already consumed (0.0 – 1.0+).
  double usageRatio(double usedMs) =>
      (usedMs / safeBudgetMs).clamp(0.0, 2.0);

  // ──────────────────────────────────────────────────────────────────────────
  // Zone computation (static utility)
  // ──────────────────────────────────────────────────────────────────────────

  /// Maps [currentFps] to an [FpsZone] using the thresholds in [config].
  ///
  /// Evaluation order: healthy → warning → critical → danger.
  ///
  /// ```dart
  /// final zone = FrameBudget.computeZone(fps: 35.0, config: myConfig);
  /// // → FpsZone.warning  (if warningThreshold=48, criticalThreshold=30)
  /// ```
  static FpsZone computeZone({
    required double fps,
    required SchedulerConfig config,
  }) {
    if (fps >= config.warningFpsThreshold) return FpsZone.healthy;
    if (fps >= config.criticalFpsThreshold) return FpsZone.warning;
    if (fps >= config.dangerFpsThreshold) return FpsZone.critical;
    return FpsZone.danger;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Diagnostic helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns a formatted summary of the current budget state.
  ///
  /// ```
  /// FrameBudget[60fps | total: 16.67ms | safe: 11.67ms | ratio: 0.70]
  /// ```
  @override
  String toString() => 'FrameBudget['
      '${config.targetFps}fps | '
      'total: ${totalBudgetMs.toStringAsFixed(2)}ms | '
      'safe: ${safeBudgetMs.toStringAsFixed(2)}ms | '
      'ratio: ${config.safeBudgetRatio}]';
}

// ────────────────────────────────────────────────────────────────────────────
// SchedulerMetrics
// ────────────────────────────────────────────────────────────────────────────

/// Immutable snapshot of cumulative scheduler performance metrics.
///
/// Accessible via [SchedulerController.metrics] when
/// [SchedulerConfig.enableMetrics] is `true`.
///
/// ## Example
/// ```dart
/// final m = SchedulerController.instance.metrics;
/// print('Executed: ${m.executedCount}, Deferred: ${m.deferredCount}');
/// ```
class SchedulerMetrics {
  const SchedulerMetrics({
    required this.executedCount,
    required this.deferredCount,
    required this.droppedCount,
    required this.expiredCount,
    required this.totalExecutionMs,
    required this.peakQueueLength,
    required this.zoneTransitions,
  });

  /// Total tasks that have been executed (immediately + from queue).
  final int executedCount;

  /// Total tasks that were deferred to the queue at least once.
  final int deferredCount;

  /// Total tasks that were dropped (queue full or low-FPS purge).
  final int droppedCount;

  /// Total tasks that expired before execution ([ScheduledTask.maxWaitMs]).
  final int expiredCount;

  /// Cumulative milliseconds spent executing tasks.
  final double totalExecutionMs;

  /// The highest observed queue length since the last reset.
  final int peakQueueLength;

  /// Number of [FpsZone] transitions since the last reset.
  final int zoneTransitions;

  /// Mean execution time per task in milliseconds.
  ///
  /// Returns 0.0 if no tasks have been executed yet.
  double get meanExecutionMs =>
      executedCount > 0 ? totalExecutionMs / executedCount : 0.0;

  /// Percentage of tasks that were dropped (0.0 – 100.0).
  double get dropRate {
    final total = executedCount + deferredCount + droppedCount;
    return total > 0 ? (droppedCount / total) * 100.0 : 0.0;
  }

  /// Returns a new metrics object with the given fields incremented.
  SchedulerMetrics copyWith({
    int? executedCount,
    int? deferredCount,
    int? droppedCount,
    int? expiredCount,
    double? totalExecutionMs,
    int? peakQueueLength,
    int? zoneTransitions,
  }) =>
      SchedulerMetrics(
        executedCount: executedCount ?? this.executedCount,
        deferredCount: deferredCount ?? this.deferredCount,
        droppedCount: droppedCount ?? this.droppedCount,
        expiredCount: expiredCount ?? this.expiredCount,
        totalExecutionMs: totalExecutionMs ?? this.totalExecutionMs,
        peakQueueLength: peakQueueLength ?? this.peakQueueLength,
        zoneTransitions: zoneTransitions ?? this.zoneTransitions,
      );

  /// An empty (zero) metrics baseline.
  static const empty = SchedulerMetrics(
    executedCount: 0,
    deferredCount: 0,
    droppedCount: 0,
    expiredCount: 0,
    totalExecutionMs: 0.0,
    peakQueueLength: 0,
    zoneTransitions: 0,
  );

  @override
  String toString() => 'SchedulerMetrics('
      'executed: $executedCount, '
      'deferred: $deferredCount, '
      'dropped: $droppedCount, '
      'expired: $expiredCount, '
      'meanMs: ${meanExecutionMs.toStringAsFixed(2)}, '
      'peakQueue: $peakQueueLength, '
      'zoneTransitions: $zoneTransitions)';
}
