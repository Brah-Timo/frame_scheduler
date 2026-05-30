/// frame_scheduler — A production-grade, FPS-aware task scheduler for Flutter.
///
/// This library monitors the real-time frames per second (FPS) of a Flutter
/// application using [SchedulerBinding.addTimingsCallback] and intelligently
/// defers, prioritizes, or drops heavy tasks when the frame rate drops below
/// configurable thresholds — keeping UI smooth and jank-free.
///
/// ## Architecture Overview
/// ```
/// FpsMonitor ──► SchedulerController ──► TaskQueue
///      │               │                    │
///  FrameTiming    FrameBudget          PriorityLevel
///      │               │
/// SchedulerConfig  FpsZone
/// ```
///
/// ## Quick Start
/// ```dart
/// import 'package:frame_scheduler/frame_scheduler.dart';
///
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   runApp(
///     FrameSchedulerScope(
///       config: SchedulerConfig.performance(),
///       child: const MyApp(),
///     ),
///   );
/// }
///
/// // Anywhere in your code:
/// SchedulerController.instance.schedule(
///   () async => await loadHeavyAssets(),
///   priority: PriorityLevel.high,
///   estimatedDurationMs: 50.0,
///   id: 'load_assets',
///   maxWaitMs: 3000,
///   onDropped: () => print('Assets load was dropped due to low FPS'),
/// );
/// ```
///
/// ## FPS Zones
/// | Zone     | FPS Range   | Behavior                             |
/// |----------|-------------|--------------------------------------|
/// | Healthy  | ≥ 48 FPS    | All tasks execute normally           |
/// | Warning  | 30–48 FPS   | Normal + Low priority tasks deferred |
/// | Critical | 15–30 FPS   | Only Critical + High execute         |
/// | Danger   | < 15 FPS    | Only Critical tasks execute          |
library frame_scheduler;

export 'src/fps_monitor.dart';
export 'src/scheduler_controller.dart';
export 'src/task_queue.dart';
export 'src/frame_budget.dart';
export 'src/scheduler_config.dart';
export 'src/priority_level.dart';
export 'src/scheduler_widget.dart';
