# frame_scheduler — API Reference

Complete reference for every public class, enum, typedef, and method.

---

## Table of Contents

- [SchedulerController](#schedulercontroller)
- [SchedulerConfig](#schedulerconfig)
- [SchedulerMetrics](#schedulermetrics)
- [FpsMonitor](#fpsmonitor)
- [FrameBudget](#framebudget)
- [TaskQueue](#taskqueue)
- [ScheduledTask](#scheduledtask)
- [PriorityLevel](#prioritylevel)
- [FpsZone](#fpszone)
- [FpsCallback](#fpscallback)
- [FrameSchedulerScope](#frameschedulerscope)
- [SchedulerBuilder](#schedulerbuilder)
- [FpsOverlay](#fpsoverlay)
- [ScheduleOnce](#scheduleonce)

---

## SchedulerController

**The primary developer API.** Singleton — access via `SchedulerController.instance`.

```dart
static SchedulerController get instance
```

### Lifecycle

| Method | Description |
|---|---|
| `void initialize({SchedulerConfig? config})` | Configure and prepare. Must call before `start()`. |
| `void start()` | Begin FPS monitoring and deferred-task processing. |
| `void stop()` | Pause monitoring; preserves queue. |
| `void dispose()` | Permanently tear down. Do not reuse the instance after this. |

### Scheduling

| Method | Description |
|---|---|
| `Future<void> schedule(Future<void> Function() task, {PriorityLevel priority, double estimatedDurationMs, String? id, int? maxWaitMs, void Function()? onDropped})` | FPS-aware scheduling entry point. |
| `Future<void> runCritical(Future<void> Function() task)` | Bypass all FPS checks. Use only for genuine emergencies. |

### Inspection

| Property | Type | Description |
|---|---|---|
| `double currentFps` | `double` | Latest FPS reading from FpsMonitor |
| `FpsZone currentZone` | `FpsZone` | Computed FPS zone |
| `int pendingTaskCount` | `int` | Number of deferred tasks waiting |
| `bool isRunning` | `bool` | Whether monitoring is active |
| `SchedulerMetrics metrics` | `SchedulerMetrics` | Cumulative snapshot |

### Queue management

| Method | Description |
|---|---|
| `bool isQueued(String id)` | Returns true if a task with [id] is in the deferred queue. |
| `void clearQueue()` | Discard all deferred tasks; calls `onDropped` for each. |
| `void resetMetrics()` | Reset all counters in `metrics` to zero. |

---

## SchedulerConfig

**Immutable** configuration value object.

```dart
SchedulerConfig({
  double targetFps = 60.0,
  double warningThreshold = 0.80,     // 80% of targetFps
  double criticalThreshold = 0.50,    // 50% of targetFps
  int fpsWindowSize = 60,             // rolling-window frame count
  int maxDeferredTasks = 50,          // queue capacity
  double safeBudgetRatio = 0.70,      // fraction of frame budget usable
  int deferCheckIntervalMs = 100,     // how often deferred tasks run (ms)
  bool autoAdjustPriority = true,     // auto-escalate half-expired tasks
  bool enableLogging = false,
  bool enableMetrics = true,
})
```

### Factory presets

| Preset | Target FPS | Warning | Critical | Window | Queue |
|---|---|---|---|---|---|
| `SchedulerConfig.balanced()` | 60 | 80% (48) | 50% (30) | 60 | 50 |
| `SchedulerConfig.performance()` | 60 | 90% (54) | 67% (40) | 30 | 100 |
| `SchedulerConfig.batterySaver()` | 30 | 80% (24) | 50% (15) | 60 | 30 |
| `SchedulerConfig.highRefresh()` | 120 | 80% (96) | 50% (60) | 120 | 50 |

### Fluent modifiers

```dart
config.withLogging()    // returns copyWith(enableLogging: true)
config.withMetrics()    // returns copyWith(enableMetrics: true)
config.copyWith(…)      // full immutable copy with any fields changed
```

---

## SchedulerMetrics

Immutable snapshot of cumulative scheduler statistics.

| Field | Type | Description |
|---|---|---|
| `executedCount` | `int` | Total tasks executed |
| `deferredCount` | `int` | Total tasks deferred to queue |
| `droppedCount` | `int` | Total tasks dropped (FPS too low) |
| `expiredCount` | `int` | Total tasks expired (maxWaitMs exceeded) |
| `totalExecutionMs` | `double` | Sum of all task execution times (ms) |
| `peakQueueLength` | `int` | Highest observed queue depth |
| `zoneTransitions` | `int` | Number of FpsZone changes |
| `meanExecutionMs` | `double` | `totalExecutionMs / executedCount` |
| `dropRate` | `double` | `droppedCount / (executedCount + droppedCount) * 100` (%) |

---

## FpsMonitor

Reads FPS from `SchedulerBinding.addTimingsCallback`.

```dart
FpsMonitor({
  int windowSize = 60,
  double targetFps = 60.0,
  FpsCallback? onFpsChanged,
})
```

| Member | Type | Description |
|---|---|---|
| `currentFps` | `double` | Latest computed FPS (default: `targetFps`) |
| `isRunning` | `bool` | Whether the timing callback is active |
| `isHealthy` | `bool` | `currentFps >= targetFps × 0.80` |
| `fpsRatio` | `double` | `currentFps / targetFps`, clamped 0–1.5 |
| `meanFrameMs` | `double` | Rolling-window mean frame duration in ms |
| `start()` | `void` | Begin listening; idempotent |
| `stop()` | `void` | Stop and clear rolling window |
| `reset()` | `void` | Clear window, restore `currentFps` to `targetFps` |
| `dispose()` | `void` | Calls `stop()` — permanent teardown |

FPS formula:
```
FPS = 1,000,000 µs ÷ mean(frame_durations_in_window)
```
Clamped to `[0, targetFps × 1.5]`.

---

## FrameBudget

Per-frame time budget calculator.

```dart
FrameBudget({
  required double targetFps,
  required double safeBudgetRatio,  // e.g. 0.70 = use 70% of budget
})
```

| Member | Type | Description |
|---|---|---|
| `totalBudgetMs` | `double` | `1000 / targetFps` |
| `safeBudgetMs` | `double` | `totalBudgetMs × safeBudgetRatio` |
| `canFit(double estimatedMs)` | `bool` | Does the task fit in remaining budget? |
| `remaining()` | `double` | Remaining budget in ms this cycle |
| `usageRatio()` | `double` | Fraction of safe budget consumed |
| `reset()` | `void` | Reset budget for new frame cycle |

### Static factory

```dart
/// Maps currentFps to the appropriate FpsZone.
static FpsZone computeZone({
  required double currentFps,
  required double targetFps,
  required double warningThreshold,   // fraction, e.g. 0.80
  required double criticalThreshold,  // fraction, e.g. 0.50
})
```

Danger zone boundary: `targetFps × 0.25` (hard-coded: < 25% of target).

---

## TaskQueue

Priority-sorted, bounded, deduplicated queue for deferred tasks.

```dart
TaskQueue({required int maxSize})
```

| Method | Description |
|---|---|
| `bool enqueue(ScheduledTask task)` | Returns `false` if queue is full or id already present. |
| `ScheduledTask? dequeue()` | Remove and return highest-priority task. |
| `void pruneExpired()` | Remove all tasks past their `maxWaitMs`; calls `onDropped`. |
| `void dropBelow(PriorityLevel threshold)` | Remove all tasks below [threshold]; calls `onDropped`. |
| `void upgradeHalfExpired()` | Escalate tasks that have used > 50% of `maxWaitMs` by one level. |
| `void clear()` | Remove all tasks; calls `onDropped` for each. |
| `bool contains(String id)` | Check if a task with [id] is queued. |
| `List<ScheduledTask> tasksOfPriority(PriorityLevel p)` | All tasks at exactly [p]. |
| `ScheduledTask? operator [](String id)` | Look up a task by id. |

| Property | Type | Description |
|---|---|---|
| `tasks` | `List<ScheduledTask>` | Immutable snapshot, highest priority first |
| `length` | `int` | Current queue depth |
| `isEmpty` | `bool` | |
| `isNotEmpty` | `bool` | |

---

## ScheduledTask

```dart
class ScheduledTask {
  final Future<void> Function() task;
  final PriorityLevel priority;
  final double estimatedDurationMs;
  final String? id;
  final int? maxWaitMs;
  final void Function()? onDropped;
  final DateTime enqueuedAt;

  Duration get age;               // time since enqueuedAt
  bool get isExpired;             // age > maxWaitMs
  double get waitFraction;        // age / maxWaitMs (0.0–1.0+)
}
```

---

## PriorityLevel

```dart
enum PriorityLevel { critical, high, normal, low }
```

Extension properties:

| Member | Type | Description |
|---|---|---|
| `weight` | `int` | Numeric weight: critical=4, high=3, normal=2, low=1 |
| `displayName` | `String` | e.g. `'Critical'` |
| `badge` | `String` | e.g. `'[CRITICAL]'` |
| `emoji` | `String` | 🔴 / 🟠 / 🟡 / 🟢 |
| `isHigherThan(PriorityLevel other)` | `bool` | |
| `isLowerThan(PriorityLevel other)` | `bool` | |
| `isAtLeast(PriorityLevel other)` | `bool` | |
| `upgraded` | `PriorityLevel` | One level higher (critical.upgraded == critical) |
| `downgraded` | `PriorityLevel` | One level lower (low.downgraded == low) |

### Execution behaviour by zone

| Priority | 🟢 Healthy | 🟡 Warning | 🔴 Critical | 💀 Danger |
|---|---|---|---|---|
| `critical` | Execute | Execute | Execute | Execute |
| `high` | Execute | Execute | Defer | Drop |
| `normal` | Execute | Defer | Drop | Drop |
| `low` | Execute | Defer | Drop | Drop |

---

## FpsZone

```dart
enum FpsZone { healthy, warning, critical, danger }
```

Extension properties:

| Member | Type | Description |
|---|---|---|
| `emoji` | `String` | 🟢 / 🟡 / 🔴 / 💀 |
| `label` | `String` | e.g. `'Healthy'` |
| `description` | `String` | Short human-readable description |
| `severity` | `int` | 0 (healthy) – 3 (danger) |
| `isSevere` | `bool` | `severity >= 2` (critical or danger) |
| `isHealthy` | `bool` | `this == FpsZone.healthy` |

---

## FpsCallback

```dart
typedef FpsCallback = void Function(double currentFps);
```

Invoked by `FpsMonitor` whenever `currentFps` changes by ≥ 0.5 FPS.

---

## FrameSchedulerScope

`StatefulWidget` that manages the full scheduler lifecycle.

```dart
FrameSchedulerScope({
  required Widget child,
  SchedulerConfig? config,   // defaults to SchedulerConfig.balanced()
})
```

Calls `initialize()` → `start()` in `initState()`.
Calls `stop()` / `start()` in `didChangeAppLifecycleState()`.
Calls `dispose()` in `dispose()`.

---

## SchedulerBuilder

Rebuilds when the `FpsZone` changes.

```dart
SchedulerBuilder({
  required Widget Function(BuildContext context, FpsZone zone) builder,
})
```

Example:

```dart
SchedulerBuilder(
  builder: (ctx, zone) => zone.isHealthy
      ? const HighQualityWidget()
      : const LowQualityWidget(),
)
```

---

## FpsOverlay

Debug badge showing live FPS, zone, queue depth, and optional metrics.

```dart
const FpsOverlay({
  Alignment alignment = Alignment.topRight,
  bool showQueueDepth = true,
  bool showMetrics = false,
  int updateIntervalMs = 500,
})
```

Badge border colour:
- 🟢 Green → `FpsZone.healthy`
- 🟡 Orange → `FpsZone.warning`
- 🔴 Red → `FpsZone.critical`
- 💜 Purple → `FpsZone.danger`

---

## ScheduleOnce

One-shot schedule-on-mount widget.

```dart
ScheduleOnce({
  required Future<void> Function() task,
  PriorityLevel priority = PriorityLevel.normal,
  double estimatedDurationMs = 5.0,
  String? id,
  int? maxWaitMs,
  void Function()? onDropped,
  required Widget child,
})
```

Schedules [task] exactly once when first inserted into the widget tree.

---

*Back to: [Getting Started](getting_started.md) · [Architecture](architecture.md)*
