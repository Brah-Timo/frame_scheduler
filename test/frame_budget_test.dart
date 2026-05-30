import 'package:flutter_test/flutter_test.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // FrameBudget tests
  // ──────────────────────────────────────────────────────────────────────────

  group('FrameBudget — budget calculations', () {
    late FrameBudget budget60;
    late FrameBudget budget120;

    setUp(() {
      budget60 = FrameBudget(config: SchedulerConfig.balanced());
      budget120 = FrameBudget(config: SchedulerConfig.highRefresh());
    });

    test('totalBudgetMs at 60fps ≈ 16.67ms', () {
      expect(budget60.totalBudgetMs, closeTo(16.67, 0.01));
    });

    test('totalBudgetMs at 120fps ≈ 8.33ms', () {
      expect(budget120.totalBudgetMs, closeTo(8.33, 0.01));
    });

    test('safeBudgetMs at 60fps with ratio 0.70 ≈ 11.67ms', () {
      expect(budget60.safeBudgetMs, closeTo(11.67, 0.01));
    });

    test('safeBudgetMs at 120fps with ratio 0.70 ≈ 5.83ms', () {
      expect(budget120.safeBudgetMs, closeTo(5.83, 0.01));
    });

    test('canFit returns true when task fits in budget', () {
      expect(budget60.canFit(taskEstimatedMs: 5.0, usedMs: 0.0), isTrue);
    });

    test('canFit returns false when task exceeds safe budget', () {
      expect(budget60.canFit(taskEstimatedMs: 20.0, usedMs: 0.0), isFalse);
    });

    test('canFit returns false when combined usage exceeds safe budget', () {
      // 8ms used + 5ms new = 13ms > 11.67ms safe budget
      expect(budget60.canFit(taskEstimatedMs: 5.0, usedMs: 8.0), isFalse);
    });

    test('canFit returns true when combined usage is within safe budget', () {
      // 3ms used + 5ms new = 8ms < 11.67ms safe budget
      expect(budget60.canFit(taskEstimatedMs: 5.0, usedMs: 3.0), isTrue);
    });

    test('remaining() returns correct remaining budget', () {
      expect(budget60.remaining(5.0), closeTo(6.67, 0.01));
    });

    test('remaining() returns 0 when budget is exhausted', () {
      expect(budget60.remaining(20.0), 0.0);
    });

    test('usageRatio() is 0.0 when nothing used', () {
      expect(budget60.usageRatio(0.0), 0.0);
    });

    test('usageRatio() is 1.0 when safe budget fully consumed', () {
      expect(budget60.usageRatio(budget60.safeBudgetMs), closeTo(1.0, 0.001));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // FpsZone tests
  // ──────────────────────────────────────────────────────────────────────────

  group('FpsZone — computeZone()', () {
    final config = SchedulerConfig.balanced();
    // balanced: warning=48, critical=30, danger=15

    test('60fps → healthy', () {
      expect(
        FrameBudget.computeZone(fps: 60.0, config: config),
        FpsZone.healthy,
      );
    });

    test('48fps → healthy (at threshold boundary)', () {
      expect(
        FrameBudget.computeZone(fps: 48.0, config: config),
        FpsZone.healthy,
      );
    });

    test('47fps → warning (just below threshold)', () {
      expect(
        FrameBudget.computeZone(fps: 47.0, config: config),
        FpsZone.warning,
      );
    });

    test('40fps → warning (mid-range)', () {
      expect(
        FrameBudget.computeZone(fps: 40.0, config: config),
        FpsZone.warning,
      );
    });

    test('30fps → warning (at critical threshold boundary)', () {
      expect(
        FrameBudget.computeZone(fps: 30.0, config: config),
        FpsZone.warning,
      );
    });

    test('29fps → critical (just below critical threshold)', () {
      expect(
        FrameBudget.computeZone(fps: 29.0, config: config),
        FpsZone.critical,
      );
    });

    test('20fps → critical (mid-range)', () {
      expect(
        FrameBudget.computeZone(fps: 20.0, config: config),
        FpsZone.critical,
      );
    });

    test('15fps → critical (at danger threshold boundary)', () {
      expect(
        FrameBudget.computeZone(fps: 15.0, config: config),
        FpsZone.critical,
      );
    });

    test('14fps → danger (just below danger threshold)', () {
      expect(
        FrameBudget.computeZone(fps: 14.0, config: config),
        FpsZone.danger,
      );
    });

    test('0fps → danger', () {
      expect(
        FrameBudget.computeZone(fps: 0.0, config: config),
        FpsZone.danger,
      );
    });
  });

  group('FpsZone — extension properties', () {
    test('healthy.isHealthy is true', () {
      expect(FpsZone.healthy.isHealthy, isTrue);
    });

    test('warning.isHealthy is false', () {
      expect(FpsZone.warning.isHealthy, isFalse);
    });

    test('critical.isSevere is true', () {
      expect(FpsZone.critical.isSevere, isTrue);
    });

    test('danger.isSevere is true', () {
      expect(FpsZone.danger.isSevere, isTrue);
    });

    test('healthy.isSevere is false', () {
      expect(FpsZone.healthy.isSevere, isFalse);
    });

    test('warning.isSevere is false', () {
      expect(FpsZone.warning.isSevere, isFalse);
    });

    test('zones have correct severity order', () {
      expect(FpsZone.healthy.severity, 0);
      expect(FpsZone.warning.severity, 1);
      expect(FpsZone.critical.severity, 2);
      expect(FpsZone.danger.severity, 3);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SchedulerMetrics tests
  // ──────────────────────────────────────────────────────────────────────────

  group('SchedulerMetrics', () {
    test('empty is all zeros', () {
      const m = SchedulerMetrics.empty;
      expect(m.executedCount, 0);
      expect(m.deferredCount, 0);
      expect(m.droppedCount, 0);
      expect(m.expiredCount, 0);
      expect(m.totalExecutionMs, 0.0);
      expect(m.peakQueueLength, 0);
      expect(m.zoneTransitions, 0);
    });

    test('meanExecutionMs is 0 when no tasks executed', () {
      const m = SchedulerMetrics.empty;
      expect(m.meanExecutionMs, 0.0);
    });

    test('meanExecutionMs computes correctly', () {
      final m = SchedulerMetrics.empty.copyWith(
        executedCount: 4,
        totalExecutionMs: 20.0,
      );
      expect(m.meanExecutionMs, 5.0);
    });

    test('dropRate is 0 when nothing dropped', () {
      final m = SchedulerMetrics.empty.copyWith(executedCount: 10);
      expect(m.dropRate, 0.0);
    });

    test('dropRate computes correctly', () {
      final m = SchedulerMetrics.empty.copyWith(
        executedCount: 8,
        droppedCount: 2,
      );
      // 2 / 10 = 20%
      expect(m.dropRate, closeTo(20.0, 0.001));
    });

    test('copyWith overrides only specified fields', () {
      final original = SchedulerMetrics.empty.copyWith(executedCount: 5);
      final updated = original.copyWith(deferredCount: 3);
      expect(updated.executedCount, 5);
      expect(updated.deferredCount, 3);
      expect(updated.droppedCount, 0);
    });
  });
}
