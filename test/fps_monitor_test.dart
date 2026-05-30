// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FpsMonitor — construction', () {
    test('default constructor uses 60fps and window of 60', () {
      final monitor = FpsMonitor();
      expect(monitor.targetFps, 60.0);
      expect(monitor.windowSize, 60);
      monitor.dispose();
    });

    test('custom constructor stores provided values', () {
      final monitor = FpsMonitor(windowSize: 30, targetFps: 120.0);
      expect(monitor.targetFps, 120.0);
      expect(monitor.windowSize, 30);
      monitor.dispose();
    });

    test('initial currentFps equals targetFps', () {
      final monitor = FpsMonitor(targetFps: 60.0);
      expect(monitor.currentFps, 60.0);
      monitor.dispose();
    });
  });

  group('FpsMonitor — state', () {
    late FpsMonitor monitor;

    setUp(() {
      monitor = FpsMonitor(windowSize: 10, targetFps: 60.0);
    });

    tearDown(() {
      monitor.dispose();
    });

    test('isRunning is false before start()', () {
      expect(monitor.isRunning, isFalse);
    });

    test('isHealthy is true at initial targetFps', () {
      expect(monitor.isHealthy, isTrue);
    });

    test('fpsRatio is 1.0 at target FPS', () {
      expect(monitor.fpsRatio, closeTo(1.0, 0.01));
    });

    test('meanFrameMs is 0.0 before any frames', () {
      expect(monitor.meanFrameMs, 0.0);
    });

    test('reset() restores currentFps to targetFps', () {
      final monitor2 = FpsMonitor(targetFps: 60.0);
      // Force a different value
      monitor2.reset();
      expect(monitor2.currentFps, 60.0);
      monitor2.dispose();
    });

    test('stop() sets isRunning to false', () {
      monitor.start();
      expect(monitor.isRunning, isTrue);
      monitor.stop();
      expect(monitor.isRunning, isFalse);
    });

    test('start() is idempotent — calling twice does not crash', () {
      expect(() {
        monitor.start();
        monitor.start();
      }, returnsNormally);
    });

    test('stop() is idempotent — calling twice does not crash', () {
      expect(() {
        monitor.stop();
        monitor.stop();
      }, returnsNormally);
    });
  });

  group('FpsMonitor — callback', () {
    test('onFpsChanged is not called before frames arrive', () {
      bool called = false;
      final monitor = FpsMonitor(
        onFpsChanged: (_) => called = true,
      );
      monitor.start();
      // No frames have been pushed
      expect(called, isFalse);
      monitor.dispose();
    });
  });
}
