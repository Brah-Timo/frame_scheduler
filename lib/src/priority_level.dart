/// Defines the execution priority of a task scheduled through
/// [SchedulerController].
///
/// Priority levels control **two** separate behaviours:
///
/// 1. **Deferral decision** — whether a task is executed immediately or added
///    to the deferred queue based on the current [FpsZone].
/// 2. **Queue ordering** — higher-priority tasks are always dequeued before
///    lower-priority ones when FPS recovers.
///
/// ## Behaviour Matrix
///
/// | Priority | 🟢 Healthy | 🟡 Warning | 🔴 Critical | 💀 Danger |
/// |----------|-----------|-----------|------------|---------|
/// | critical | Execute   | Execute   | Execute    | Execute |
/// | high     | Execute   | Execute   | Defer      | Defer   |
/// | normal   | Execute   | Defer     | Defer      | Drop    |
/// | low      | Execute   | Defer     | Drop       | Drop    |
///
/// ### Legend
/// - **Execute** — runs synchronously in the current call.
/// - **Defer** — added to the priority queue; runs when FPS recovers.
/// - **Drop** — discarded immediately; `onDropped` callback is invoked.
///
/// ## Choosing the Right Priority
///
/// | Scenario                                    | Recommended Priority |
/// |---------------------------------------------|----------------------|
/// | Responding to a user tap                    | `critical`           |
/// | Playing an essential sound effect           | `critical`           |
/// | Loading the next scene's core assets        | `high`               |
/// | Syncing score to server                     | `high`               |
/// | Pre-loading adjacent screen's images        | `normal`             |
/// | Non-critical animations / eye-candy         | `normal`             |
/// | Sending analytics / telemetry               | `low`                |
/// | Background cache refresh                    | `low`                |
/// | Prefetching speculative content             | `low`                |
enum PriorityLevel {
  /// **Always executes** regardless of FPS zone.
  ///
  /// Reserved for operations that must complete on the current frame and
  /// whose omission would be immediately visible or audible to the user.
  ///
  /// ⚠️ Use sparingly. Overusing `critical` defeats the purpose of the
  /// scheduler — if too many tasks are critical, FPS cannot recover.
  critical,

  /// Executes in 🟢 Healthy and 🟡 Warning zones; deferred in 🔴 Critical
  /// and 💀 Danger zones.
  ///
  /// Suitable for important-but-not-instant work: loading the next level,
  /// syncing state to a server, or showing a success animation.
  high,

  /// Executes only in the 🟢 Healthy zone; deferred in 🟡 Warning and
  /// 🔴 Critical; dropped in 💀 Danger.
  ///
  /// The **default priority** for most application work. If the UI is
  /// already stressed, normal tasks wait until calm returns.
  normal,

  /// The lowest priority. Deferred in 🟡 Warning, dropped immediately in
  /// 🔴 Critical and 💀 Danger.
  ///
  /// Use for background, speculative, or analytics work that is safe to lose.
  low,
}

/// Extension methods and computed properties for [PriorityLevel].
extension PriorityLevelExtension on PriorityLevel {
  // ──────────────────────────────────────────────────────────────────────────
  // Display helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// A human-readable title-case name suitable for logging and UI display.
  String get displayName {
    switch (this) {
      case PriorityLevel.critical:
        return 'Critical';
      case PriorityLevel.high:
        return 'High';
      case PriorityLevel.normal:
        return 'Normal';
      case PriorityLevel.low:
        return 'Low';
    }
  }

  /// A single-character badge for compact log lines.
  ///
  /// Example output: `[C]`, `[H]`, `[N]`, `[L]`
  String get badge {
    switch (this) {
      case PriorityLevel.critical:
        return '[C]';
      case PriorityLevel.high:
        return '[H]';
      case PriorityLevel.normal:
        return '[N]';
      case PriorityLevel.low:
        return '[L]';
    }
  }

  /// Emoji representation for rich log output.
  String get emoji {
    switch (this) {
      case PriorityLevel.critical:
        return '🚨';
      case PriorityLevel.high:
        return '🔺';
      case PriorityLevel.normal:
        return '🔹';
      case PriorityLevel.low:
        return '🔸';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Sorting
  // ──────────────────────────────────────────────────────────────────────────

  /// Numeric weight used for priority-queue ordering.
  ///
  /// Higher weight → dequeued first. Stable ordering between tasks of the
  /// same priority is preserved by insertion order in [TaskQueue].
  int get weight {
    switch (this) {
      case PriorityLevel.critical:
        return 4;
      case PriorityLevel.high:
        return 3;
      case PriorityLevel.normal:
        return 2;
      case PriorityLevel.low:
        return 1;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Comparators
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns `true` if this priority is strictly higher than [other].
  bool isHigherThan(PriorityLevel other) => weight > other.weight;

  /// Returns `true` if this priority is strictly lower than [other].
  bool isLowerThan(PriorityLevel other) => weight < other.weight;

  /// Returns `true` if this priority is at least as high as [other].
  bool isAtLeast(PriorityLevel other) => weight >= other.weight;

  // ──────────────────────────────────────────────────────────────────────────
  // Upgrade / downgrade helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns the next higher [PriorityLevel], or the same level if already
  /// [PriorityLevel.critical].
  ///
  /// Used by the auto-adjust logic when a deferred task is close to expiry.
  PriorityLevel get upgraded {
    switch (this) {
      case PriorityLevel.low:
        return PriorityLevel.normal;
      case PriorityLevel.normal:
        return PriorityLevel.high;
      case PriorityLevel.high:
      case PriorityLevel.critical:
        return PriorityLevel.critical;
    }
  }

  /// Returns the next lower [PriorityLevel], or the same level if already
  /// [PriorityLevel.low].
  PriorityLevel get downgraded {
    switch (this) {
      case PriorityLevel.critical:
        return PriorityLevel.high;
      case PriorityLevel.high:
        return PriorityLevel.normal;
      case PriorityLevel.normal:
      case PriorityLevel.low:
        return PriorityLevel.low;
    }
  }
}
