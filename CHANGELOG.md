# Changelog

All notable changes to `frame_scheduler` are documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.

---

## [1.0.0] — 2026-05-29

### 🎉 Initial Release

#### Added

**Core Engine**
- `FpsMonitor` — Real-time FPS tracking via `SchedulerBinding.addTimingsCallback`.
  Uses a rolling window of configurable size for smooth, accurate readings.
  Computes FPS from `FrameTiming.totalSpan` (full frame wall-clock duration).
- `SchedulerController` — Singleton central orchestrator. Manages FPS monitoring,
  task queuing, and intelligent execution decisions. Exposes the primary developer
  API: `schedule()`, `runCritical()`, `isQueued()`, `clearQueue()`, and diagnostic
  properties (`currentFps`, `currentZone`, `pendingTaskCount`, `metrics`).
- `TaskQueue` — Priority-sorted, bounded, deduplicated queue for deferred tasks.
  Supports expiry (`maxWaitMs`), `pruneExpired()`, `dropBelow()`, `upgradeHalfExpired()`,
  and full inspection via `tasks`, `tasksOfPriority()`, and `operator[]`.
- `FrameBudget` — Per-frame time budget calculator. Provides `canFit()`, `remaining()`,
  `usageRatio()`, and the static `computeZone()` factory.

**Configuration**
- `SchedulerConfig` — Immutable configuration value object with full `copyWith()`.
  Ships with four ready-made presets:
  - `SchedulerConfig.balanced()` — 60fps, 80%/50% thresholds, 60-frame window.
  - `SchedulerConfig.performance()` — 60fps, 90%/67% thresholds, 30-frame window.
  - `SchedulerConfig.batterySaver()` — 30fps target, 500ms check interval.
  - `SchedulerConfig.highRefresh()` — 120fps target, 96/60 thresholds.
  - Fluent modifiers: `withLogging()`, `withMetrics()`.

**Priority System**
- `PriorityLevel` enum — `critical` / `high` / `normal` / `low`.
  Full extension: `weight`, `displayName`, `badge`, `emoji`, `isHigherThan()`,
  `isLowerThan()`, `isAtLeast()`, `upgraded`, `downgraded`.

**FPS Zones**
- `FpsZone` enum — `healthy` / `warning` / `critical` / `danger`.
  Full extension: `emoji`, `label`, `description`, `severity`, `isSevere`, `isHealthy`.

**Metrics**
- `SchedulerMetrics` — Immutable metrics snapshot with `executedCount`,
  `deferredCount`, `droppedCount`, `expiredCount`, `totalExecutionMs`,
  `peakQueueLength`, `zoneTransitions`, `meanExecutionMs`, `dropRate`.
  Accessible via `SchedulerController.instance.metrics`.
  Reset via `SchedulerController.instance.resetMetrics()`.

**Widgets**
- `FrameSchedulerScope` — Stateful wrapper widget that manages the full
  scheduler lifecycle (init → start → pause on deactivate → resume on activate
  → dispose). The recommended integration point.
- `FpsOverlay` — Debug badge overlay showing live FPS, zone, queue depth,
  and optional metrics summary. Updates at configurable interval.
- `SchedulerBuilder` — Reactive builder that rebuilds when the `FpsZone` changes.
  Ideal for adaptive quality rendering.
- `ScheduleOnce` — One-shot task scheduling widget for mount-time deferred work.

**Auto Priority Escalation**
- When `SchedulerConfig.autoAdjustPriority` is enabled (default: true), tasks
  that have consumed more than 50% of their `maxWaitMs` budget are automatically
  upgraded one priority level, preventing "priority inversion starvation".

**Deduplication**
- Tasks with the same `id` cannot be enqueued twice. The second `schedule()`
  call with a duplicate id is a silent no-op.

**Danger Zone Purging**
- When the FPS zone transitions to `FpsZone.danger`, the scheduler immediately
  invokes `TaskQueue.dropBelow(PriorityLevel.critical)` to relieve pressure on
  the UI thread without waiting for the next timer cycle.

**Testing**
- Full unit test suite: `fps_monitor_test.dart`, `scheduler_config_test.dart`,
  `frame_budget_test.dart`, `task_queue_test.dart`, `priority_level_test.dart`.
- 8-benchmark micro-benchmark suite: `benchmark/scheduler_benchmark.dart`.

**Examples**
- `example/lib/main.dart` — Full demo app with all priority levels, stress test,
  live metrics dashboard, zone banner, and event log.
- `example/lib/game_example.dart` — Game loop integration demo with physics
  (critical), enemy AI (high), asset streaming (normal), and analytics (low).

**Documentation**
- Comprehensive `README.md` with architecture diagram, API reference, game loop
  pattern, and priority cheat sheet.
- `doc/getting_started.md` — Step-by-step guide from installation to advanced usage.
- Full `///` DartDoc on every public API surface.
