# Getting Started with frame_scheduler

A step-by-step guide from installation to advanced production patterns.

---

## Table of Contents

1. [Installation](#installation)
2. [Basic Setup](#basic-setup)
3. [Your First Scheduled Task](#your-first-scheduled-task)
4. [Understanding Priority Levels](#understanding-priority-levels)
5. [Choosing the Right Config Preset](#choosing-the-right-config-preset)
6. [The Debug Overlay](#the-debug-overlay)
7. [Reactive UI with SchedulerBuilder](#reactive-ui-with-schedulerbuilder)
8. [Task Expiry and Drop Callbacks](#task-expiry-and-drop-callbacks)
9. [Reading Live Metrics](#reading-live-metrics)
10. [Game Loop Integration](#game-loop-integration)
11. [Manual Lifecycle Management](#manual-lifecycle-management)
12. [Frequently Asked Questions](#frequently-asked-questions)

---

## 1. Installation

Add `frame_scheduler` to your `pubspec.yaml`:

```yaml
dependencies:
  frame_scheduler: ^1.0.0
```

Then run:

```bash
flutter pub get
```

---

## 2. Basic Setup

The simplest integration uses `FrameSchedulerScope` at the root of your app.
It automatically handles `initialize()`, `start()`, and `dispose()` for you:

```dart
import 'package:flutter/material.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

void main() {
  runApp(
    FrameSchedulerScope(
      config: SchedulerConfig.balanced(), // or omit for the default
      child: const MyApp(),
    ),
  );
}
```

That's it. The scheduler is now running and monitoring your app's FPS.

---

## 3. Your First Scheduled Task

Access the scheduler from anywhere using the singleton:

```dart
import 'package:frame_scheduler/frame_scheduler.dart';

final scheduler = SchedulerController.instance;

// Minimum: just provide the async callback
scheduler.schedule(() async {
  await heavyWork();
});

// Recommended: provide all metadata for best results
scheduler.schedule(
  () async => await heavyWork(),
  priority: PriorityLevel.normal,
  estimatedDurationMs: 50.0,   // How long does heavyWork take?
  id: 'heavy_work_initial',    // Prevents duplicate scheduling
  maxWaitMs: 5000,             // Drop after 5 seconds in queue
  onDropped: () => useFallback(), // Called if dropped
);
```

---

## 4. Understanding Priority Levels

Priority determines **two things**:
1. Whether the task executes now or is deferred (based on current FPS zone)
2. The order deferred tasks execute when FPS recovers (higher priority first)

### `PriorityLevel.critical`
- **Always executes immediately**, regardless of FPS.
- Use for: user-visible reactions to input, sound effects, score updates.
- ⚠️ Overusing `critical` defeats the scheduler's purpose.

### `PriorityLevel.high`
- Executes in 🟢 Healthy and 🟡 Warning zones.
- Deferred (not dropped) in 🔴 Critical zone.
- Dropped in 💀 Danger zone.
- Use for: loading required next-scene assets, server sync.

### `PriorityLevel.normal` _(default)_
- Executes only in 🟢 Healthy zone.
- Deferred in 🟡 Warning zone.
- Dropped in 🔴 Critical and 💀 Danger zones.
- Use for: pre-loading speculative assets, non-critical animations.

### `PriorityLevel.low`
- Deferred in 🟡 Warning zone.
- Dropped in any degraded zone.
- Use for: analytics, telemetry, background cache updates.

---

## 5. Choosing the Right Config Preset

| Your app | Recommended preset |
|----------|--------------------|
| General productivity app | `SchedulerConfig.balanced()` |
| Heavy game or 3D app | `SchedulerConfig.performance()` |
| Budget / older device target | `SchedulerConfig.batterySaver()` |
| Targeting iPad Pro / 120Hz phones | `SchedulerConfig.highRefresh()` |

Enable debug logging during development:

```dart
config: SchedulerConfig.performance().withLogging()
```

Custom fine-tuning:

```dart
config: SchedulerConfig.balanced().copyWith(
  maxDeferredTasks: 100,        // Allow more queued tasks
  deferCheckIntervalMs: 150,    // Check queue 6.7x per second
  safeBudgetRatio: 0.65,        // Use 65% of frame budget
)
```

---

## 6. The Debug Overlay

Add `FpsOverlay` to any `Stack` during development:

```dart
Stack(
  children: [
    const MyScreen(),
    // Show only in debug builds
    if (kDebugMode)
      const FpsOverlay(
        alignment: Alignment.topRight,
        showQueueDepth: true,
        showMetrics: true,        // Adds executed/deferred/dropped counters
        updateIntervalMs: 200,    // Refresh rate of the badge
      ),
  ],
)
```

The badge colour changes with the FPS zone:
- 🟢 Green border → Healthy
- 🟡 Orange border → Warning
- 🔴 Red border → Critical
- 💜 Purple border → Danger

---

## 7. Reactive UI with SchedulerBuilder

Adapt your UI quality automatically when performance degrades:

```dart
SchedulerBuilder(
  builder: (context, zone) {
    return switch (zone) {
      FpsZone.healthy  => const HighQualityParticles(),
      FpsZone.warning  => const MediumQualityParticles(),
      FpsZone.critical => const LowQualityParticles(),
      FpsZone.danger   => const SolidColorBackground(), // Minimal
    };
  },
)
```

---

## 8. Task Expiry and Drop Callbacks

Tasks that wait too long in the queue should be expired gracefully:

```dart
scheduler.schedule(
  () async => await showToastNotification('Friend joined!'),
  priority: PriorityLevel.high,
  estimatedDurationMs: 2.0,
  id: 'friend_joined_toast',
  // Drop the toast if FPS doesn't recover within 3 seconds —
  // showing a "Friend joined" toast 5 seconds late is confusing.
  maxWaitMs: 3000,
  onDropped: () {
    // The FPS was too low for 3 seconds — skip the toast silently.
    print('Toast notification was dropped — FPS was too low.');
  },
);
```

**Auto priority escalation** (enabled by default): If a task has spent
more than 50% of its `maxWaitMs` waiting, its effective priority is
automatically upgraded one level to help it get through before expiry.

---

## 9. Reading Live Metrics

```dart
final m = SchedulerController.instance.metrics;

print('Tasks executed:   ${m.executedCount}');
print('Tasks deferred:   ${m.deferredCount}');
print('Tasks dropped:    ${m.droppedCount}');
print('Tasks expired:    ${m.expiredCount}');
print('Mean exec time:   ${m.meanExecutionMs.toStringAsFixed(2)} ms');
print('Drop rate:        ${m.dropRate.toStringAsFixed(1)}%');
print('Zone transitions: ${m.zoneTransitions}');
print('Peak queue depth: ${m.peakQueueLength}');

// Reset after a session or level
SchedulerController.instance.resetMetrics();
```

A **drop rate above 15%** usually indicates tasks are being scheduled
at priorities that are too aggressive for the device's capabilities.
Consider downgrading `normal` tasks to `low`.

---

## 10. Game Loop Integration

See `example/lib/game_example.dart` for a complete runnable example.
Conceptual pattern:

```dart
// Tick called once per frame (~60 times/second)
void onTick(double dt) {
  // CRITICAL: physics must never be skipped
  scheduler.schedule(
    () async => physics.step(dt),
    priority: PriorityLevel.critical,
    estimatedDurationMs: 1.5,
    id: 'physics_$frameId',
  );

  // HIGH: AI once per 10 frames
  if (frameId % 10 == 0) {
    scheduler.schedule(
      () async => aiSystem.evaluate(entities),
      priority: PriorityLevel.high,
      estimatedDurationMs: 5.0,
      id: 'ai_$frameId',
      maxWaitMs: 200,  // Skip if FPS doesn't recover in 200ms
    );
  }

  // NORMAL: stream world chunks as player moves
  if (playerEnteredNewChunk) {
    scheduler.schedule(
      () async => worldStreamer.loadChunk(chunkId),
      priority: PriorityLevel.normal,
      estimatedDurationMs: 40.0,
      id: 'chunk_$chunkId',
      maxWaitMs: 10000,
    );
  }

  // LOW: telemetry every 5 seconds
  if (frameId % 300 == 0) {
    scheduler.schedule(
      () async => telemetry.heartbeat(),
      priority: PriorityLevel.low,
      estimatedDurationMs: 1.0,
      maxWaitMs: 30000,
      onDropped: () => telemetry.discard(),
    );
  }
}
```

---

## 11. Manual Lifecycle Management

If you need fine-grained control (e.g., pausing when the app goes to
background):

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerController.instance.initialize(
      config: SchedulerConfig.performance(),
    );
    SchedulerController.instance.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        SchedulerController.instance.stop(); // Pause monitoring
        break;
      case AppLifecycleState.resumed:
        SchedulerController.instance.start(); // Resume
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SchedulerController.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MaterialApp(home: MyScreen());
}
```

---

## 12. Frequently Asked Questions

**Q: Does `frame_scheduler` work in release mode?**

Yes. `SchedulerBinding.addTimingsCallback` works in all build modes. Note
that in release mode the engine batches `FrameTiming` callbacks less
frequently (about once per second vs. once per 100ms in debug mode), so
FPS readings update slightly less often but remain accurate.

---

**Q: What happens if I call `schedule()` before calling `initialize()`?**

An `AssertionError` is thrown in debug mode. In release mode, the behaviour
is undefined. Always call `initialize()` before `start()` before any
`schedule()` calls — or use `FrameSchedulerScope` which handles this for you.

---

**Q: Can I use multiple `FrameSchedulerScope` widgets in the same app?**

`SchedulerController` is a singleton, so the second `FrameSchedulerScope`
will call `initialize()` again (stopping the first). This is intentional —
you should only have one `FrameSchedulerScope` at the root of your app.

---

**Q: Is there a risk of memory leaks from the deferred queue?**

No, as long as you set appropriate `maxWaitMs` values for tasks that are
time-sensitive. For tasks that can wait indefinitely, the queue has a hard
capacity limit (`SchedulerConfig.maxDeferredTasks`) and will reject new tasks
when full, calling `onDropped` for the rejected task.

---

**Q: How accurate is the FPS measurement?**

Very accurate. `SchedulerBinding.addTimingsCallback` receives raw
`FrameTiming` data from the Flutter engine itself — the same data displayed
in DevTools' performance overlay. The rolling window smooths out frame-to-
frame variance while still reacting promptly to sustained drops.

---

*For more information, see the [README](../README.md) and the
[API reference on pub.dev](https://pub.dev/documentation/frame_scheduler/latest/).*
