import 'dart:collection';
import 'package:flutter/scheduler.dart';

/// Signature for callbacks that receive FPS updates.
///
/// Invoked every time the FPS value is recomputed from a new batch of
/// [FrameTiming] objects delivered by the Flutter engine.
typedef FpsCallback = void Function(double currentFps);

/// No-op [FpsCallback] used as the default when no callback is provided.
void _noOpFpsCallback(double fps) {}

/// [FpsMonitor] is the sensing core of `frame_scheduler`.
///
/// It hooks into Flutter's [SchedulerBinding.addTimingsCallback] to receive
/// [FrameTiming] data directly from the Flutter rendering engine — the
/// lowest-level, most accurate FPS source available in Flutter.
///
/// ## How It Works
///
/// Flutter's engine reports batches of [FrameTiming] objects approximately
/// every 100ms in debug/profile mode and ~1 second in release mode. Each
/// [FrameTiming] carries precise timestamps for the build and raster phases
/// of one rendered frame.
///
/// The monitor accumulates frame durations in a **rolling window** and
/// recomputes the FPS on every new batch:
///
/// ```
/// FPS = 1,000,000 µs ÷ mean(frame_durations_in_window)
/// ```
///
/// A larger window (`windowSize`) produces smoother readings but reacts
/// more slowly to sudden FPS drops. Tune it via [SchedulerConfig.fpsWindowSize].
///
/// ## Thread Safety
///
/// All callbacks from [SchedulerBinding.addTimingsCallback] are delivered on
/// the **platform thread** after each vsync. No manual synchronisation is
/// needed.
///
/// ## Usage
///
/// You normally never instantiate [FpsMonitor] directly — use
/// [SchedulerController] instead. For advanced usage:
///
/// ```dart
/// final monitor = FpsMonitor(
///   windowSize: 60,
///   targetFps: 60.0,
///   onFpsChanged: (fps) => print('Current FPS: $fps'),
/// );
/// monitor.start();
/// // ...
/// monitor.stop();
/// monitor.dispose();
/// ```
class FpsMonitor {
  /// Creates an [FpsMonitor] with the given configuration.
  ///
  /// - [windowSize]: Rolling window frame count (default 60).
  /// - [targetFps]: Expected device refresh rate in Hz (default 60.0).
  /// - [onFpsChanged]: Optional callback invoked on every FPS update.
  FpsMonitor({
    this.windowSize = 60,
    this.targetFps = 60.0,
    FpsCallback? onFpsChanged,
  }) : _onFpsChanged = onFpsChanged ?? _noOpFpsCallback;

  // ──────────────────────────────────────────────────────────────────────────
  // Public configuration fields
  // ──────────────────────────────────────────────────────────────────────────

  /// Number of frames included in the rolling average window.
  ///
  /// - A larger value produces a smoother FPS reading but reacts slower.
  /// - A smaller value reacts faster but is noisier.
  ///
  /// Recommended range: 10–120. Default: 60.
  final int windowSize;

  /// The target (maximum) FPS for this device.
  ///
  /// Typical values: 60.0 for standard displays, 120.0 for high-refresh
  /// displays (iPad Pro, OnePlus, Samsung Galaxy S series, etc.).
  final double targetFps;

  // ──────────────────────────────────────────────────────────────────────────
  // Private state
  // ──────────────────────────────────────────────────────────────────────────

  final FpsCallback _onFpsChanged;

  /// Rolling window of raw frame durations in **microseconds**.
  final Queue<double> _frameDurations = Queue<double>();

  bool _isRunning = false;
  double _currentFps = 60.0;

  // ──────────────────────────────────────────────────────────────────────────
  // Public read-only accessors
  // ──────────────────────────────────────────────────────────────────────────

  /// The most recently computed FPS value.
  ///
  /// Before [start] is called or before the first frame timing arrives,
  /// this returns [targetFps] as the optimistic default.
  double get currentFps => _currentFps;

  /// Whether the monitor is actively listening for frame timings.
  bool get isRunning => _isRunning;

  /// `true` when [currentFps] is above 80% of [targetFps].
  ///
  /// The 80% threshold (i.e. 48 FPS for a 60 Hz target) is the industry
  /// standard "perceptible jank" boundary. Below this point users typically
  /// notice stuttering.
  bool get isHealthy => _currentFps >= (targetFps * 0.80);

  /// Percentage of target FPS currently achieved (0.0 – 1.0+).
  ///
  /// Values > 1.0 are possible during very fast frames and are clamped to
  /// 1.5× target inside the internal computation.
  double get fpsRatio => (_currentFps / targetFps).clamp(0.0, 1.5);

  /// Mean frame duration in milliseconds derived from the rolling window.
  ///
  /// Useful for budget calculations. Returns 0.0 if no frames yet.
  double get meanFrameMs {
    if (_frameDurations.isEmpty) return 0.0;
    final totalMicros = _frameDurations.fold(0.0, (s, d) => s + d);
    return (totalMicros / _frameDurations.length) / 1000.0;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  /// Starts listening to Flutter engine's frame timing callbacks.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops when already
  /// running. Requires [SchedulerBinding] to be initialised (call
  /// [WidgetsFlutterBinding.ensureInitialized] or [runApp] first).
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  /// Stops listening and clears the internal rolling window.
  ///
  /// The last computed [currentFps] value is preserved until [reset] or
  /// [start] is called again.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _frameDurations.clear();
  }

  /// Resets the rolling window and restores [currentFps] to [targetFps].
  ///
  /// Does **not** stop monitoring; call [stop] separately if needed.
  void reset() {
    _frameDurations.clear();
    _currentFps = targetFps;
  }

  /// Permanently disposes this instance.
  ///
  /// Calls [stop] internally. After disposal the instance must not be used.
  void dispose() {
    stop();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal — frame timing handler
  // ──────────────────────────────────────────────────────────────────────────

  /// Called by the Flutter engine with a batch of [FrameTiming] objects.
  ///
  /// Each [FrameTiming] represents one completely rendered frame. We extract
  /// [FrameTiming.totalSpan] — the full wall-clock duration of the frame
  /// including both build and raster phases — and push it into the rolling
  /// window.
  ///
  /// The batch may contain multiple frames when the engine coalesces
  /// callbacks for efficiency (common in release mode).
  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final durationMicros = timing.totalSpan.inMicroseconds.toDouble();

      // Guard against zero or negative durations (can occur on first frames
      // or if the engine reports a synthetic vsync event).
      if (durationMicros <= 0) continue;

      _frameDurations.addLast(durationMicros);

      // Maintain fixed window size by evicting the oldest entry.
      while (_frameDurations.length > windowSize) {
        _frameDurations.removeFirst();
      }
    }

    if (_frameDurations.isNotEmpty) {
      _recomputeFps();
    }
  }

  /// Recomputes [_currentFps] from the current rolling window.
  ///
  /// Formula:
  /// ```
  ///   FPS = 1_000_000 µs/s ÷ mean_frame_duration_µs
  /// ```
  ///
  /// The result is clamped to [0, targetFps × 1.5] to filter out spurious
  /// extreme values on the first few frames or after a resume.
  void _recomputeFps() {
    final totalMicros = _frameDurations.fold(0.0, (sum, d) => sum + d);
    final avgMicros = totalMicros / _frameDurations.length;
    final newFps = (1000000.0 / avgMicros).clamp(0.0, targetFps * 1.5);

    // Only invoke the callback when the value actually changes by at least
    // 0.5 FPS — avoids excessive rebuilds from floating-point noise.
    if ((newFps - _currentFps).abs() >= 0.5) {
      _currentFps = newFps;
      _onFpsChanged(_currentFps);
    } else {
      _currentFps = newFps;
    }
  }

  @override
  String toString() =>
      'FpsMonitor('
      'running: $_isRunning, '
      'fps: ${_currentFps.toStringAsFixed(1)}, '
      'window: ${_frameDurations.length}/$windowSize)';
}
