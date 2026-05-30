/// Configuration for [SchedulerController].
///
/// [SchedulerConfig] is an **immutable value object** that defines all
/// tunable parameters of the frame scheduler. It is designed around four
/// ready-made factory presets for the most common scenarios, plus a fluent
/// `copyWith` API for fine-grained customisation.
///
/// ## Preset Quick-Reference
///
/// | Preset            | Target FPS | Warning FPS | Critical FPS | Best For            |
/// |-------------------|-----------|-------------|--------------|---------------------|
/// | `balanced()`      | 60        | 48          | 30           | General apps        |
/// | `performance()`   | 60        | 54          | 40           | Heavy games / 3D    |
/// | `batterySaver()`  | 30        | 24          | 15           | Low-end devices     |
/// | `highRefresh()`   | 120       | 96          | 60           | 120 Hz displays     |
///
/// ## Zone Model
/// ```
/// ──────────────────────────────────────────────────────────
///  targetFps ──────────────── 🟢 Healthy   (all tasks run)
///  warningFpsThreshold ─────── 🟡 Warning   (low deferred)
///  criticalFpsThreshold ─────── 🔴 Critical  (only high+critical)
///  < 15 FPS ───────────────── 💀 Danger    (only critical)
/// ──────────────────────────────────────────────────────────
/// ```
class SchedulerConfig {
  /// Creates a fully custom [SchedulerConfig].
  ///
  /// Prefer the named factory constructors for most use cases.
  const SchedulerConfig({
    required this.targetFps,
    required this.warningFpsThreshold,
    required this.criticalFpsThreshold,
    required this.fpsWindowSize,
    required this.maxDeferredTasks,
    required this.deferCheckIntervalMs,
    required this.enableLogging,
    required this.autoAdjustPriority,
    required this.safeBudgetRatio,
    required this.dangerFpsThreshold,
    required this.enableMetrics,
  }) : assert(
          warningFpsThreshold > criticalFpsThreshold,
          'warningFpsThreshold must be greater than criticalFpsThreshold.',
        );

  // ──────────────────────────────────────────────────────────────────────────
  // FPS configuration
  // ──────────────────────────────────────────────────────────────────────────

  /// Target (maximum) FPS for the device.
  ///
  /// Set to 60.0 for standard displays, 120.0 for high-refresh displays.
  final double targetFps;

  /// FPS below which [PriorityLevel.low] and [PriorityLevel.normal] tasks
  /// begin to be deferred.
  ///
  /// Defaults to 80% of [targetFps] in the `balanced` preset (48 FPS at
  /// 60 Hz).
  final double warningFpsThreshold;

  /// FPS below which [PriorityLevel.high] tasks are also deferred.
  /// Only [PriorityLevel.critical] tasks still execute in this zone.
  ///
  /// Defaults to 50% of [targetFps] in the `balanced` preset (30 FPS at
  /// 60 Hz).
  final double criticalFpsThreshold;

  /// FPS below which the system enters the **Danger** zone.
  ///
  /// In the Danger zone the [TaskQueue] immediately drops all tasks below
  /// [PriorityLevel.critical] to relieve pressure on the UI thread.
  ///
  /// Hard-coded to 15.0 FPS in all presets — this is the threshold at which
  /// the human eye perceives motion as a slideshow rather than animation.
  final double dangerFpsThreshold;

  // ──────────────────────────────────────────────────────────────────────────
  // Monitoring configuration
  // ──────────────────────────────────────────────────────────────────────────

  /// Number of frames used in the rolling FPS average.
  ///
  /// - Larger values → smoother, but slower to react to drops.
  /// - Smaller values → faster reaction, but noisier.
  ///
  /// Recommended range: 10–120. Default: 60.
  final int fpsWindowSize;

  // ──────────────────────────────────────────────────────────────────────────
  // Queue configuration
  // ──────────────────────────────────────────────────────────────────────────

  /// Maximum number of tasks allowed in the deferred queue simultaneously.
  ///
  /// When the queue is full, new tasks are dropped immediately and their
  /// `onDropped` callback is invoked.
  final int maxDeferredTasks;

  /// How often (in milliseconds) the scheduler checks the deferred queue
  /// and attempts to execute pending tasks when FPS has recovered.
  ///
  /// Smaller values mean lower latency for deferred tasks; larger values
  /// reduce the timer overhead. Default: 200ms.
  final int deferCheckIntervalMs;

  // ──────────────────────────────────────────────────────────────────────────
  // Execution configuration
  // ──────────────────────────────────────────────────────────────────────────

  /// The fraction of a frame's total duration reserved for scheduled tasks.
  ///
  /// At 60 FPS the total budget is 16.67ms. With [safeBudgetRatio] = 0.70
  /// the usable budget is ≈ 11.67ms. The remaining 30% is reserved for
  /// Flutter's own build + raster overhead.
  ///
  /// Valid range: 0.1 – 0.95. Default: 0.70.
  final double safeBudgetRatio;

  // ──────────────────────────────────────────────────────────────────────────
  // Debug / diagnostic configuration
  // ──────────────────────────────────────────────────────────────────────────

  /// When `true`, the scheduler prints detailed log lines to the console
  /// showing every scheduling decision, zone transition, and queue event.
  ///
  /// **Disable in production.** Enable via [withLogging].
  final bool enableLogging;

  /// When `true`, the scheduler collects execution metrics (task count,
  /// deferred count, drop count, mean execution time) accessible via
  /// [SchedulerController.metrics].
  ///
  /// Has negligible overhead but can be disabled for minimal footprint.
  final bool enableMetrics;

  /// When `true`, the scheduler automatically upgrades the priority of
  /// tasks that have been waiting in the queue for more than half their
  /// [ScheduledTask.maxWaitMs] budget.
  ///
  /// This prevents "priority inversion starvation" in heavy workloads.
  final bool autoAdjustPriority;

  // ──────────────────────────────────────────────────────────────────────────
  // Factory presets
  // ──────────────────────────────────────────────────────────────────────────

  /// **Balanced** preset — the recommended default for most apps.
  ///
  /// 60 FPS target, moderate thresholds, sensible queue limits.
  factory SchedulerConfig.balanced() => const SchedulerConfig(
        targetFps: 60.0,
        warningFpsThreshold: 48.0,   // 80% of 60
        criticalFpsThreshold: 30.0,  // 50% of 60
        dangerFpsThreshold: 15.0,
        fpsWindowSize: 60,
        maxDeferredTasks: 50,
        deferCheckIntervalMs: 200,
        safeBudgetRatio: 0.70,
        enableLogging: false,
        enableMetrics: true,
        autoAdjustPriority: true,
      );

  /// **Performance** preset — aggressive for heavy games and 3D apps.
  ///
  /// Reacts faster to FPS drops (smaller window), defers sooner (90%
  /// threshold), larger queue to hold more deferred work.
  factory SchedulerConfig.performance() => const SchedulerConfig(
        targetFps: 60.0,
        warningFpsThreshold: 54.0,   // 90% of 60 — defer sooner
        criticalFpsThreshold: 40.0,
        dangerFpsThreshold: 15.0,
        fpsWindowSize: 30,           // Faster reaction window
        maxDeferredTasks: 100,
        deferCheckIntervalMs: 100,   // Check more frequently
        safeBudgetRatio: 0.60,       // More conservative budget
        enableLogging: false,
        enableMetrics: true,
        autoAdjustPriority: true,
      );

  /// **Battery-saver** preset — for low-end or older devices.
  ///
  /// Targets 30 FPS as the healthy baseline, defers aggressively, checks
  /// the queue less frequently to reduce CPU wake-ups.
  factory SchedulerConfig.batterySaver() => const SchedulerConfig(
        targetFps: 30.0,
        warningFpsThreshold: 24.0,   // 80% of 30
        criticalFpsThreshold: 15.0,  // 50% of 30
        dangerFpsThreshold: 8.0,
        fpsWindowSize: 30,
        maxDeferredTasks: 20,
        deferCheckIntervalMs: 500,   // Less frequent — saves battery
        safeBudgetRatio: 0.65,
        enableLogging: false,
        enableMetrics: false,
        autoAdjustPriority: false,
      );

  /// **High-refresh** preset — for 120 Hz displays (iPad Pro, flagship phones).
  ///
  /// Both thresholds scale proportionally to 120 FPS baseline.
  factory SchedulerConfig.highRefresh() => const SchedulerConfig(
        targetFps: 120.0,
        warningFpsThreshold: 96.0,   // 80% of 120
        criticalFpsThreshold: 60.0,  // 50% of 120
        dangerFpsThreshold: 30.0,
        fpsWindowSize: 120,
        maxDeferredTasks: 75,
        deferCheckIntervalMs: 150,
        safeBudgetRatio: 0.70,
        enableLogging: false,
        enableMetrics: true,
        autoAdjustPriority: true,
      );

  // ──────────────────────────────────────────────────────────────────────────
  // Fluent modifiers
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns a copy of this config with [enableLogging] set to `true`.
  ///
  /// Convenience for development:
  /// ```dart
  /// config: SchedulerConfig.performance().withLogging()
  /// ```
  SchedulerConfig withLogging() => copyWith(enableLogging: true);

  /// Returns a copy of this config with [enableMetrics] set to `true`.
  SchedulerConfig withMetrics() => copyWith(enableMetrics: true);

  /// Returns a new [SchedulerConfig] with the specified fields overridden.
  SchedulerConfig copyWith({
    double? targetFps,
    double? warningFpsThreshold,
    double? criticalFpsThreshold,
    double? dangerFpsThreshold,
    int? fpsWindowSize,
    int? maxDeferredTasks,
    int? deferCheckIntervalMs,
    double? safeBudgetRatio,
    bool? enableLogging,
    bool? enableMetrics,
    bool? autoAdjustPriority,
  }) {
    return SchedulerConfig(
      targetFps: targetFps ?? this.targetFps,
      warningFpsThreshold: warningFpsThreshold ?? this.warningFpsThreshold,
      criticalFpsThreshold: criticalFpsThreshold ?? this.criticalFpsThreshold,
      dangerFpsThreshold: dangerFpsThreshold ?? this.dangerFpsThreshold,
      fpsWindowSize: fpsWindowSize ?? this.fpsWindowSize,
      maxDeferredTasks: maxDeferredTasks ?? this.maxDeferredTasks,
      deferCheckIntervalMs: deferCheckIntervalMs ?? this.deferCheckIntervalMs,
      safeBudgetRatio: safeBudgetRatio ?? this.safeBudgetRatio,
      enableLogging: enableLogging ?? this.enableLogging,
      enableMetrics: enableMetrics ?? this.enableMetrics,
      autoAdjustPriority: autoAdjustPriority ?? this.autoAdjustPriority,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchedulerConfig &&
          runtimeType == other.runtimeType &&
          targetFps == other.targetFps &&
          warningFpsThreshold == other.warningFpsThreshold &&
          criticalFpsThreshold == other.criticalFpsThreshold &&
          dangerFpsThreshold == other.dangerFpsThreshold &&
          fpsWindowSize == other.fpsWindowSize &&
          maxDeferredTasks == other.maxDeferredTasks &&
          deferCheckIntervalMs == other.deferCheckIntervalMs &&
          safeBudgetRatio == other.safeBudgetRatio &&
          enableLogging == other.enableLogging &&
          enableMetrics == other.enableMetrics &&
          autoAdjustPriority == other.autoAdjustPriority;

  @override
  int get hashCode => Object.hash(
        targetFps,
        warningFpsThreshold,
        criticalFpsThreshold,
        dangerFpsThreshold,
        fpsWindowSize,
        maxDeferredTasks,
        deferCheckIntervalMs,
        safeBudgetRatio,
        enableLogging,
        enableMetrics,
        autoAdjustPriority,
      );

  @override
  String toString() => 'SchedulerConfig('
      'target: ${targetFps}fps, '
      'warning: ${warningFpsThreshold}fps, '
      'critical: ${criticalFpsThreshold}fps, '
      'window: $fpsWindowSize, '
      'maxQueue: $maxDeferredTasks)';
}
