# 🎯 frame_scheduler

> A production-grade, FPS-aware task scheduler for Flutter apps and games.

[![pub.dev](https://img.shields.io/pub/v/frame_scheduler.svg)](https://pub.dev/packages/frame_scheduler)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.10-blue)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0-blue)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20Web%20%7C%20Desktop-lightgrey)](https://flutter.dev)

---

## 🧠 The Problem

Your Flutter app runs at 60 FPS in normal conditions. Then it needs to execute
a heavy task — parsing a large JSON response, pre-loading the next scene's
assets, processing a list of 5,000 items. The FPS tanks to 15, the animation
freezes, and the user feels the jank.

The problem isn't the work itself — it's **the timing**.

## 💡 The Solution

`frame_scheduler` hooks into Flutter's rendering engine via
`SchedulerBinding.addTimingsCallback`, monitors the real-time FPS continuously,
and automatically defers, prioritises, or drops tasks based on the current
performance health:

```
FPS is healthy?  → Execute now
FPS is degraded? → Defer task to the priority queue
FPS recovered?   → Execute deferred tasks within the frame budget
FPS in danger?   → Drop non-critical tasks to relieve UI pressure
```

No polling loops. No manual FPS checks. No `Timer.periodic` hacks.
**Just schedule — the library decides when.**

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔬 **Real-time FPS monitoring** | Uses `SchedulerBinding.addTimingsCallback` — the deepest, most accurate Flutter FPS source |
| 🎚 **4-level priority system** | Critical / High / Normal / Low with automatic deferral rules |
| ⏱ **Frame-budget awareness** | Never schedules more work than fits in the available frame time |
| 🔄 **Smart deferred queue** | Priority-sorted, bounded, deduplicated queue with expiry support |
| 📊 **Built-in metrics** | Executed / Deferred / Dropped / Expired counters with drop rate |
| 🔧 **4 presets + copyWith** | `balanced`, `performance`, `batterySaver`, `highRefresh` |
| 🏗 **Auto priority escalation** | Tasks close to expiry are automatically upgraded |
| 🎨 **Debug overlay** | `FpsOverlay` shows live FPS, zone, and queue depth |
| 📡 **Reactive widget** | `SchedulerBuilder` rebuilds on zone changes |
| 🔌 **Zero dependencies** | Pure Flutter + Dart, no third-party packages |

---

## 📦 Installation

```yaml
# pubspec.yaml
dependencies:
  frame_scheduler: ^1.0.0
```

```bash
flutter pub get
```

---

## 🚀 Quick Start — 3 Steps

### Step 1 — Wrap your app

```dart
import 'package:frame_scheduler/frame_scheduler.dart';

void main() {
  runApp(
    FrameSchedulerScope(
      config: SchedulerConfig.performance(),
      child: const MyApp(),
    ),
  );
}
```

### Step 2 — Schedule your tasks

```dart
final scheduler = SchedulerController.instance;

// Load assets for the next scene (deferrable)
scheduler.schedule(
  () async => await assetLoader.preload('level_3'),
  priority: PriorityLevel.high,
  estimatedDurationMs: 80.0,
  id: 'preload_level_3',
  maxWaitMs: 5000,
  onDropped: () => print('Preload dropped — will use fallback'),
);

// Send analytics (safe to drop)
scheduler.schedule(
  () async => await analytics.flush(),
  priority: PriorityLevel.low,
  estimatedDurationMs: 2.0,
  maxWaitMs: 10000,
  onDropped: () => print('Analytics dropped — no FPS budget'),
);

// Critical — always executes instantly
scheduler.schedule(
  () async => soundEngine.play('coin'),
  priority: PriorityLevel.critical,
);
```

### Step 3 — Add the debug overlay (development only)

```dart
Stack(
  children: [
    const MyGameScreen(),
    if (kDebugMode) const FpsOverlay(showMetrics: true),
  ],
)
```

---

## 📊 FPS Zones

| Zone | Range (60fps target) | Emoji | Behaviour |
|------|---------------------|-------|-----------|
| **Healthy** | ≥ 48 FPS | 🟢 | All tasks execute immediately |
| **Warning** | 30–48 FPS | 🟡 | Normal + Low priority tasks deferred |
| **Critical** | 15–30 FPS | 🔴 | Only Critical + High execute; others drop |
| **Danger** | < 15 FPS | 💀 | Only Critical executes; queue is purged |

---

## 🎚 Priority Behaviour Matrix

| Priority | 🟢 Healthy | 🟡 Warning | 🔴 Critical | 💀 Danger |
|----------|-----------|-----------|------------|---------|
| `critical` | Execute | Execute | Execute | Execute |
| `high` | Execute | Execute | Defer | Drop |
| `normal` | Execute | Defer | Drop | Drop |
| `low` | Execute | Defer | Drop | Drop |

---

## ⚙️ Configuration Presets

### `SchedulerConfig.balanced()` — Default

```dart
// Best for: General apps, content browsing, social media
FrameSchedulerScope(config: SchedulerConfig.balanced())
```

| Parameter | Value |
|-----------|-------|
| Target FPS | 60 |
| Warning threshold | 48 FPS (80%) |
| Critical threshold | 30 FPS (50%) |
| Window size | 60 frames |
| Max queue | 50 tasks |

---

### `SchedulerConfig.performance()` — Aggressive

```dart
// Best for: Heavy games, 3D apps, real-time simulations
FrameSchedulerScope(config: SchedulerConfig.performance())
```

| Parameter | Value |
|-----------|-------|
| Target FPS | 60 |
| Warning threshold | 54 FPS (90%) — defers sooner |
| Critical threshold | 40 FPS |
| Window size | 30 frames — reacts faster |
| Max queue | 100 tasks |

---

### `SchedulerConfig.batterySaver()` — Low-end Devices

```dart
// Best for: Budget phones, older devices, background processing
FrameSchedulerScope(config: SchedulerConfig.batterySaver())
```

| Parameter | Value |
|-----------|-------|
| Target FPS | 30 |
| Warning threshold | 24 FPS |
| Check interval | 500ms — fewer wake-ups |

---

### `SchedulerConfig.highRefresh()` — 120Hz Displays

```dart
// Best for: iPad Pro, OnePlus, Samsung Galaxy S, Pixel 6+
FrameSchedulerScope(config: SchedulerConfig.highRefresh())
```

| Parameter | Value |
|-----------|-------|
| Target FPS | 120 |
| Warning threshold | 96 FPS (80%) |
| Critical threshold | 60 FPS (50%) |
| Window size | 120 frames |

---

### Custom Configuration

```dart
SchedulerConfig.balanced().copyWith(
  maxDeferredTasks: 200,
  deferCheckIntervalMs: 100,
  safeBudgetRatio: 0.60,
  autoAdjustPriority: true,
)
```

---

## 🏗 Architecture

```
frame_scheduler/
│
├── FpsMonitor              ← Reads FrameTiming from SchedulerBinding
│     └── rolling window   ← Smoothed FPS via N-frame average
│
├── FrameBudget             ← 16.67ms / 120fps budget calculator
│     └── computeZone()    ← Maps FPS → FpsZone (healthy/warning/critical/danger)
│
├── TaskQueue               ← Priority-sorted, bounded, deduplicated queue
│     ├── PriorityLevel     ← critical / high / normal / low
│     └── ScheduledTask     ← Task + metadata (id, estimated duration, expiry)
│
├── SchedulerController     ← Singleton orchestrator — THE main API
│     ├── schedule()        ← FPS-aware scheduling entry point
│     ├── runCritical()     ← Bypass-all emergency execution
│     └── metrics           ← Cumulative SchedulerMetrics snapshot
│
├── SchedulerConfig         ← Immutable config object (4 presets + copyWith)
│
└── Widgets
      ├── FrameSchedulerScope   ← Lifecycle management widget
      ├── FpsOverlay            ← Debug badge overlay
      ├── SchedulerBuilder      ← Reactive zone-aware builder
      └── ScheduleOnce          ← One-shot schedule-on-mount widget
```

---

## 🔑 Core API Reference

### `SchedulerController.instance.schedule()`

```dart
Future<void> schedule(
  Future<void> Function() task, {
  PriorityLevel priority = PriorityLevel.normal,  // Execution priority
  double estimatedDurationMs = 5.0,               // Budget hint (ms)
  String? id,                                     // Deduplication key
  int? maxWaitMs,                                 // Expiry timeout
  void Function()? onDropped,                     // Drop callback
})
```

### `SchedulerController.instance.runCritical()`

```dart
// Bypasses ALL FPS checks — use only for genuine emergencies
Future<void> runCritical(Future<void> Function() task)
```

### Read-only properties

```dart
SchedulerController.instance.currentFps;        // double
SchedulerController.instance.currentZone;       // FpsZone
SchedulerController.instance.pendingTaskCount;  // int
SchedulerController.instance.metrics;           // SchedulerMetrics
SchedulerController.instance.isRunning;         // bool
```

---

## 🎮 Game Loop Integration Pattern

```dart
// In your game tick (called ~60 times/sec):
void _onGameTick() {
  final scheduler = SchedulerController.instance;

  // Physics: CRITICAL — must never be skipped
  scheduler.schedule(
    () async => physicsEngine.integrate(dt),
    priority: PriorityLevel.critical,
    estimatedDurationMs: 2.0,
    id: 'physics_${frame}',
  );

  // Enemy AI: HIGH — important but can wait one cycle
  if (frame % 10 == 0) {
    scheduler.schedule(
      () async => enemyAI.evaluate(gameState),
      priority: PriorityLevel.high,
      estimatedDurationMs: 6.0,
      id: 'ai_${frame}',
      maxWaitMs: 300,
    );
  }

  // Asset streaming: NORMAL — fine to defer
  if (needsNewChunk) {
    scheduler.schedule(
      () async => worldStreamer.loadChunk(playerPosition),
      priority: PriorityLevel.normal,
      estimatedDurationMs: 35.0,
      id: 'chunk_${chunkId}',
      maxWaitMs: 8000,
    );
  }

  // Telemetry: LOW — safe to drop
  scheduler.schedule(
    () async => telemetry.send({'fps': scheduler.currentFps}),
    priority: PriorityLevel.low,
    estimatedDurationMs: 1.0,
    maxWaitMs: 5000,
    onDropped: () => telemetry.discard(),
  );
}
```

---

## 🔬 How FPS is Measured

`frame_scheduler` uses `SchedulerBinding.addTimingsCallback` — Flutter's
official, lowest-level frame timing API. Each callback delivers a batch of
`FrameTiming` objects, one per completed frame.

The FPS is computed using a **rolling window average**:

```
FPS = 1,000,000 µs ÷ mean(frame_durations_in_window)
```

Where each `frame_duration` is `FrameTiming.totalSpan.inMicroseconds` —
the full wall-clock time including both build and raster phases.

A larger window (configurable via `SchedulerConfig.fpsWindowSize`) produces
smoother readings at the cost of slightly slower reaction to sudden drops.

---

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/task_queue_test.dart

# Run benchmarks
dart run benchmark/scheduler_benchmark.dart
```

---

## 📋 Choosing the Right Priority — Cheat Sheet

| Scenario | Priority |
|----------|----------|
| Responding to a user tap / button press | `critical` |
| Playing a game sound effect | `critical` |
| Updating a high-stakes UI element (health bar, score) | `critical` |
| Loading the next scene's required assets | `high` |
| Syncing game state to server | `high` |
| Showing a toast/snackbar | `high` |
| Pre-loading speculative assets | `normal` |
| Non-critical background animations | `normal` |
| Refreshing a feed in the background | `normal` |
| Sending analytics / telemetry | `low` |
| Background cache updates | `low` |
| Prefetching content the user might see | `low` |

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

Contributions are welcome! Please open an issue first to discuss what you'd
like to change.

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/Brah-Timo/frame_scheduler/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Brah-Timo/frame_scheduler/discussions)
- **pub.dev**: [frame_scheduler](https://pub.dev/packages/frame_scheduler)
