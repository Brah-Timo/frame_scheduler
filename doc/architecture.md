# frame_scheduler — Architecture

Internal design, data flow, and component responsibilities.

---

## Component Overview

```
frame_scheduler/
│
├── FpsMonitor              ← Reads FrameTiming from SchedulerBinding
│     ├── rolling window   ← Smoothed FPS via N-frame average
│     └── FpsCallback      ← Notifies SchedulerController on change
│
├── FrameBudget             ← Per-frame time budget (16.67 ms at 60fps)
│     ├── canFit()         ← Does a task fit in remaining budget?
│     └── computeZone()    ← Maps current FPS → FpsZone
│
├── TaskQueue               ← Priority-sorted, bounded, dedup queue
│     ├── PriorityLevel    ← critical / high / normal / low
│     ├── ScheduledTask    ← Task + id + estimatedDurationMs + expiry
│     └── upgradeHalfExpired() ← Auto-escalation before expiry
│
├── SchedulerController     ← THE main API (singleton)
│     ├── schedule()       ← FPS-aware routing: execute now or defer
│     ├── runCritical()    ← Bypass all checks, execute immediately
│     ├── _deferLoop()     ← Timer-driven deferred-task executor
│     └── SchedulerMetrics ← Cumulative counters
│
├── SchedulerConfig         ← Immutable config (4 presets + copyWith)
│
└── Widgets
      ├── FrameSchedulerScope   ← Lifecycle management
      ├── FpsOverlay            ← Debug badge overlay
      ├── SchedulerBuilder      ← Reactive zone-aware builder
      └── ScheduleOnce          ← One-shot schedule-on-mount
```

---

## FPS Measurement Pipeline

```
Flutter engine renders a frame
         │
         ▼
SchedulerBinding.addTimingsCallback(List<FrameTiming>)
         │
         ▼
FpsMonitor._onFrameTimings(timings)
         │
         ├─ for each timing:
         │     durationMicros = timing.totalSpan.inMicroseconds
         │     _frameDurations.addLast(durationMicros)
         │     while length > windowSize: removeFirst()
         │
         └─ _recomputeFps()
               FPS = 1,000,000 µs ÷ mean(_frameDurations)
               if |newFps - currentFps| >= 0.5: invoke _onFpsChanged
```

`FrameTiming.totalSpan` includes both the **build** and **raster** phases —
the full wall-clock frame time, which is what determines the perceived frame
rate from the user's perspective.

---

## Task Routing Decision Tree

```
schedule(task, priority, estimatedMs, …) called
         │
         ▼
  priority == critical?
  ├─ YES → execute immediately (no FPS check)
  └─ NO  ↓
         │
         ▼
  computeZone(currentFps, config) → FpsZone
         │
         ├─ healthy:   execute now if budget fits, else defer
         ├─ warning:   critical+high execute now; normal+low → defer
         ├─ critical:  only critical executes; high → defer; normal+low → drop
         └─ danger:    only critical executes; all others → drop
                              │
                    drop → onDropped() callback, metrics.droppedCount++
```

### Frame budget check (healthy zone)

```
FrameBudget.canFit(estimatedMs)?
├─ YES → execute task → record execution time
└─ NO  → defer to TaskQueue (not dropped — will run in next cycle)
```

---

## Deferred Task Execution Loop

`SchedulerController` runs a `Timer.periodic` at `deferCheckIntervalMs`
(default: 100 ms). On each tick:

```
_deferLoop()
    │
    ├─ pruneExpired()           ← remove tasks past maxWaitMs
    ├─ upgradeHalfExpired()     ← escalate tasks at 50%+ wait time
    │
    ├─ while budget remaining and queue non-empty:
    │     task = queue.dequeue()         ← highest-priority first
    │     if canFit(task.estimatedMs):   ← re-check budget
    │         execute task
    │     else:
    │         re-enqueue task (yield to next cycle)
    │
    └─ budget.reset()                   ← restore for next cycle
```

---

## Auto Priority Escalation

When `SchedulerConfig.autoAdjustPriority = true` (default), a task that
has spent more than **50%** of its `maxWaitMs` in the queue is automatically
upgraded one priority level:

```
task.waitFraction > 0.5?
├─ priority.upgraded == current → no change (already at critical)
└─ task.effectivePriority = priority.upgraded
```

This prevents **priority inversion starvation**: a `normal` task that has
been deferred for a long time is bumped to `high` so it executes before
newer lower-priority tasks that arrived during a bad FPS window.

---

## Danger Zone Purge

When the FPS zone transitions **to** `FpsZone.danger`, the scheduler
immediately calls `queue.dropBelow(PriorityLevel.critical)`, discarding all
non-critical deferred tasks. This relieves memory and CPU pressure on the UI
thread before the next timer tick.

---

## Zone Transition Diagram

```
             ┌─────────────┐
             │   healthy   │  ≥ 80% of targetFps
             └──────┬──────┘
                    │ FPS drops
                    ▼
             ┌─────────────┐
             │   warning   │  50–80% of targetFps
             └──────┬──────┘
                    │ FPS drops
                    ▼
             ┌─────────────┐
             │  critical   │  25–50% of targetFps
             └──────┬──────┘
                    │ FPS drops
                    ▼
             ┌─────────────┐
             │   danger    │  < 25% of targetFps
             └─────────────┘

Transitions in either direction are detected by FrameBudget.computeZone()
on every FPS update and trigger SchedulerController._onZoneChanged().
```

---

## Widget Layer

```
FrameSchedulerScope (StatefulWidget, WidgetsBindingObserver)
    │
    ├─ initState()
    │     SchedulerController.instance.initialize(config)
    │     SchedulerController.instance.start()
    │
    ├─ didChangeAppLifecycleState(state)
    │     paused/inactive → stop()   (conserve battery)
    │     resumed         → start()
    │
    └─ dispose()
          SchedulerController.instance.dispose()

SchedulerBuilder (StatefulWidget)
    │
    └─ listens to SchedulerController zone change stream
       rebuilds child when FpsZone changes

FpsOverlay (StatefulWidget)
    └─ Timer.periodic(updateIntervalMs) → setState()
       reads currentFps, currentZone, pendingTaskCount, metrics

ScheduleOnce (StatefulWidget)
    └─ didChangeDependencies() → schedule() exactly once per mount
```

---

## Thread Safety

All `SchedulerBinding.addTimingsCallback` callbacks are delivered on the
**platform thread** (UI isolate) after each vsync. No manual synchronisation
is needed — all `FpsMonitor` and `SchedulerController` state is mutated only
from this thread.

The `schedule()` call is also always invoked from widget build / event handler
code on the same UI isolate, so `TaskQueue` requires no locking.

---

*Back to: [Getting Started](getting_started.md) · [API Reference](api_reference.md)*
