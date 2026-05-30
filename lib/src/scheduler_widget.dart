import 'dart:async';
import 'package:flutter/material.dart';
import 'scheduler_controller.dart';
import 'scheduler_config.dart';
import 'frame_budget.dart';
import 'priority_level.dart';

// ────────────────────────────────────────────────────────────────────────────
// FrameSchedulerScope
// ────────────────────────────────────────────────────────────────────────────

/// A widget that **automatically manages the lifecycle** of
/// [SchedulerController].
///
/// Wrap your entire app (or a subtree that needs scheduling) with
/// [FrameSchedulerScope] to avoid manually calling [initialize], [start],
/// and [dispose].
///
/// ```dart
/// void main() {
///   runApp(
///     FrameSchedulerScope(
///       config: SchedulerConfig.performance(),
///       child: const MyApp(),
///     ),
///   );
/// }
/// ```
///
/// The widget calls:
/// - [SchedulerController.initialize] + [SchedulerController.start] in
///   [initState].
/// - [SchedulerController.stop] in [deactivate] (e.g., when pushed off
///   the navigation stack).
/// - [SchedulerController.start] again in [activate] (when pushed back).
/// - [SchedulerController.dispose] in [dispose].
class FrameSchedulerScope extends StatefulWidget {
  const FrameSchedulerScope({
    super.key,
    required this.child,
    this.config,
  });

  /// The widget subtree that will benefit from frame-aware scheduling.
  final Widget child;

  /// Optional custom configuration. Defaults to [SchedulerConfig.balanced].
  final SchedulerConfig? config;

  @override
  State<FrameSchedulerScope> createState() => _FrameSchedulerScopeState();
}

class _FrameSchedulerScopeState extends State<FrameSchedulerScope> {
  @override
  void initState() {
    super.initState();
    SchedulerController.instance.initialize(config: widget.config);
    SchedulerController.instance.start();
  }

  @override
  void deactivate() {
    // Pause when the widget is deactivated (e.g., pushed behind another route).
    SchedulerController.instance.stop();
    super.deactivate();
  }

  @override
  void activate() {
    // Resume when the widget becomes active again.
    super.activate();
    SchedulerController.instance.start();
  }

  @override
  void dispose() {
    SchedulerController.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ────────────────────────────────────────────────────────────────────────────
// FpsOverlay
// ────────────────────────────────────────────────────────────────────────────

/// A development-only debug overlay that displays real-time FPS, zone
/// status, and deferred queue depth.
///
/// Add it inside a [Stack] during development to visualise the scheduler's
/// live state:
///
/// ```dart
/// Stack(
///   children: [
///     MyGameWidget(),
///     const FpsOverlay(),
///   ],
/// )
/// ```
///
/// The overlay updates every [updateIntervalMs] milliseconds (default 500ms).
///
/// ⚠️ **Remove from production builds.** Use an `assert` or
/// `kDebugMode` guard:
///
/// ```dart
/// if (kDebugMode) const FpsOverlay(),
/// ```
class FpsOverlay extends StatefulWidget {
  const FpsOverlay({
    super.key,
    this.alignment = Alignment.topRight,
    this.opacity = 0.90,
    this.updateIntervalMs = 500,
    this.showQueueDepth = true,
    this.showMetrics = false,
  });

  /// Where on the screen to anchor the overlay.
  final AlignmentGeometry alignment;

  /// Opacity of the overlay badge (0.0–1.0).
  final double opacity;

  /// How often to refresh the displayed values in milliseconds.
  final int updateIntervalMs;

  /// Whether to show the deferred queue depth counter.
  final bool showQueueDepth;

  /// Whether to show a collapsed metrics summary (executed/deferred/dropped).
  final bool showMetrics;

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay> {
  double _fps = 60.0;
  FpsZone _zone = FpsZone.healthy;
  int _queueDepth = 0;
  SchedulerMetrics _metrics = SchedulerMetrics.empty;
  late Timer _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      Duration(milliseconds: widget.updateIntervalMs),
      (_) {
        if (!mounted) return;
        setState(() {
          final ctrl = SchedulerController.instance;
          _fps = ctrl.currentFps;
          _zone = ctrl.currentZone;
          _queueDepth = ctrl.pendingTaskCount;
          _metrics = ctrl.metrics;
        });
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  // ── Visual helpers ─────────────────────────────────────────────────────────

  Color get _zoneColor {
    switch (_zone) {
      case FpsZone.healthy:
        return const Color(0xFF4CAF50); // Green
      case FpsZone.warning:
        return const Color(0xFFFF9800); // Orange
      case FpsZone.critical:
        return const Color(0xFFF44336); // Red
      case FpsZone.danger:
        return const Color(0xFF9C27B0); // Purple
    }
  }

  String get _fpsLabel => '${_fps.toStringAsFixed(1)} FPS';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: Opacity(
        opacity: widget.opacity,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xDD000000),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _zoneColor, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // FPS row
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _zone.emoji,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _fpsLabel,
                    style: TextStyle(
                      color: _zoneColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              // Zone label row
              Text(
                _zone.label,
                style: const TextStyle(
                  color: Color(0xAAFFFFFF),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              // Queue depth row
              if (widget.showQueueDepth)
                Text(
                  '⏳ $_queueDepth queued',
                  style: const TextStyle(
                    color: Color(0x88FFFFFF),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              // Metrics row
              if (widget.showMetrics) ...[
                const Divider(color: Color(0x44FFFFFF), height: 8),
                Text(
                  '✅ ${_metrics.executedCount}  '
                  '⏳ ${_metrics.deferredCount}  '
                  '❌ ${_metrics.droppedCount}',
                  style: const TextStyle(
                    color: Color(0x88FFFFFF),
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'avg ${_metrics.meanExecutionMs.toStringAsFixed(1)}ms',
                  style: const TextStyle(
                    color: Color(0x66FFFFFF),
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SchedulerBuilder
// ────────────────────────────────────────────────────────────────────────────

/// A widget that rebuilds its [builder] whenever the [FpsZone] changes.
///
/// Use this to reactively adapt your UI based on the current performance
/// health of the application — for example, disabling particle effects
/// when the zone enters [FpsZone.critical].
///
/// ```dart
/// SchedulerBuilder(
///   builder: (context, zone) {
///     return zone.isSevere
///         ? const LowQualityBackground()
///         : const HighQualityBackground();
///   },
/// )
/// ```
class SchedulerBuilder extends StatefulWidget {
  const SchedulerBuilder({
    super.key,
    required this.builder,
    this.updateIntervalMs = 250,
  });

  /// Called whenever the [FpsZone] or FPS value changes significantly.
  final Widget Function(BuildContext context, FpsZone zone) builder;

  /// How often to poll the scheduler for state changes.
  final int updateIntervalMs;

  @override
  State<SchedulerBuilder> createState() => _SchedulerBuilderState();
}

class _SchedulerBuilderState extends State<SchedulerBuilder> {
  FpsZone _zone = FpsZone.healthy;
  late Timer _pollTimer;

  @override
  void initState() {
    super.initState();
    _zone = SchedulerController.instance.currentZone;
    _pollTimer = Timer.periodic(
      Duration(milliseconds: widget.updateIntervalMs),
      (_) {
        final newZone = SchedulerController.instance.currentZone;
        if (newZone != _zone && mounted) {
          setState(() => _zone = newZone);
        }
      },
    );
  }

  @override
  void dispose() {
    _pollTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _zone);
}

// ────────────────────────────────────────────────────────────────────────────
// ScheduleOnce
// ────────────────────────────────────────────────────────────────────────────

/// A widget that schedules a one-shot task when first inserted into the tree.
///
/// Useful for triggering deferred initialisation work from a widget's build
/// phase without needing a custom [State] class.
///
/// ```dart
/// ScheduleOnce(
///   id: 'load_profile_image',
///   priority: PriorityLevel.high,
///   task: () async => await avatarLoader.fetch(userId),
///   child: const ProfileAvatar(),
/// )
/// ```
class ScheduleOnce extends StatefulWidget {
  const ScheduleOnce({
    super.key,
    required this.task,
    required this.child,
    this.id,
    this.priority = PriorityLevel.normal,
    this.estimatedDurationMs = 5.0,
    this.maxWaitMs,
    this.onDropped,
  });

  final Future<void> Function() task;
  final Widget child;
  final String? id;
  final PriorityLevel priority;
  final double estimatedDurationMs;
  final int? maxWaitMs;
  final void Function()? onDropped;

  @override
  State<ScheduleOnce> createState() => _ScheduleOnceState();
}

class _ScheduleOnceState extends State<ScheduleOnce> {
  @override
  void initState() {
    super.initState();
    SchedulerController.instance.schedule(
      widget.task,
      priority: widget.priority,
      estimatedDurationMs: widget.estimatedDurationMs,
      id: widget.id,
      maxWaitMs: widget.maxWaitMs,
      onDropped: widget.onDropped,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
