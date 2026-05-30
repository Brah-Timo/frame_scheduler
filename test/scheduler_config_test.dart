import 'package:flutter_test/flutter_test.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

void main() {
  group('SchedulerConfig — presets', () {
    test('balanced() has 60fps target', () {
      final cfg = SchedulerConfig.balanced();
      expect(cfg.targetFps, 60.0);
    });

    test('balanced() warningThreshold is 48fps (80% of 60)', () {
      final cfg = SchedulerConfig.balanced();
      expect(cfg.warningFpsThreshold, 48.0);
    });

    test('balanced() criticalThreshold is 30fps (50% of 60)', () {
      final cfg = SchedulerConfig.balanced();
      expect(cfg.criticalFpsThreshold, 30.0);
    });

    test('balanced() dangerThreshold is 15fps', () {
      final cfg = SchedulerConfig.balanced();
      expect(cfg.dangerFpsThreshold, 15.0);
    });

    test('performance() warningThreshold is 54fps (90% of 60)', () {
      final cfg = SchedulerConfig.performance();
      expect(cfg.warningFpsThreshold, 54.0);
    });

    test('batterySaver() targets 30fps', () {
      final cfg = SchedulerConfig.batterySaver();
      expect(cfg.targetFps, 30.0);
    });

    test('batterySaver() disables metrics', () {
      final cfg = SchedulerConfig.batterySaver();
      expect(cfg.enableMetrics, isFalse);
    });

    test('highRefresh() targets 120fps', () {
      final cfg = SchedulerConfig.highRefresh();
      expect(cfg.targetFps, 120.0);
    });

    test('highRefresh() warningThreshold is 96fps (80% of 120)', () {
      final cfg = SchedulerConfig.highRefresh();
      expect(cfg.warningFpsThreshold, 96.0);
    });

    test('highRefresh() criticalThreshold is 60fps (50% of 120)', () {
      final cfg = SchedulerConfig.highRefresh();
      expect(cfg.criticalFpsThreshold, 60.0);
    });
  });

  group('SchedulerConfig — validation', () {
    test('assert fires when warningThreshold <= criticalThreshold', () {
      expect(
        () => SchedulerConfig(
          targetFps: 60.0,
          warningFpsThreshold: 30.0,
          criticalFpsThreshold: 40.0, // higher than warning — invalid
          dangerFpsThreshold: 15.0,
          fpsWindowSize: 60,
          maxDeferredTasks: 50,
          deferCheckIntervalMs: 200,
          safeBudgetRatio: 0.7,
          enableLogging: false,
          enableMetrics: true,
          autoAdjustPriority: true,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SchedulerConfig — fluent API', () {
    test('withLogging() enables logging', () {
      final cfg = SchedulerConfig.balanced().withLogging();
      expect(cfg.enableLogging, isTrue);
    });

    test('withMetrics() enables metrics', () {
      final cfg = SchedulerConfig.balanced().withMetrics();
      expect(cfg.enableMetrics, isTrue);
    });

    test('copyWith() overrides only specified fields', () {
      final original = SchedulerConfig.balanced();
      final modified = original.copyWith(targetFps: 90.0);
      expect(modified.targetFps, 90.0);
      // All other fields remain unchanged
      expect(modified.warningFpsThreshold, original.warningFpsThreshold);
      expect(modified.criticalFpsThreshold, original.criticalFpsThreshold);
      expect(modified.fpsWindowSize, original.fpsWindowSize);
    });

    test('equality holds for identical presets', () {
      expect(SchedulerConfig.balanced(), equals(SchedulerConfig.balanced()));
    });

    test('equality fails for different presets', () {
      expect(
        SchedulerConfig.balanced(),
        isNot(equals(SchedulerConfig.performance())),
      );
    });
  });
}
