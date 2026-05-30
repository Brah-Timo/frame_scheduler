// ============================================================
// frame_scheduler — Example App
// ============================================================
//
// Demonstrates all major features of the frame_scheduler package:
//   • FrameSchedulerScope for automatic lifecycle management
//   • Scheduling tasks at all four priority levels
//   • FpsOverlay debug widget
//   • SchedulerBuilder for reactive UI adaptation
//   • Live metrics dashboard
//   • Simulated FPS stress test
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    FrameSchedulerScope(
      // Use performance preset + logging in debug mode
      config: kDebugMode
          ? SchedulerConfig.performance().withLogging()
          : SchedulerConfig.performance(),
      child: const ExampleApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// App shell
// ─────────────────────────────────────────────────────────────────────────────

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'frame_scheduler Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6200EA),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DemoScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main demo screen
// ─────────────────────────────────────────────────────────────────────────────

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen>
    with SingleTickerProviderStateMixin {
  // Smooth spinning logo — the canary for FPS health
  late AnimationController _spinController;

  final _scheduler = SchedulerController.instance;
  final _log = <String>[];
  Timer? _stressTimer;
  bool _isStressTesting = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _spinController.dispose();
    _stressTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _addLog(String msg) {
    setState(() {
      _log.insert(0, '[${DateTime.now().toIso8601String().substring(11, 23)}] $msg');
      if (_log.length > 20) _log.removeLast();
    });
  }

  /// Simulates a CPU-heavy task by spinning for [ms] milliseconds.
  Future<void> _burnCpu(int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      // Hot loop — intentionally burns CPU
      sqrt(Random().nextDouble() * 999999);
    }
  }

  // ── Scheduling actions ────────────────────────────────────────────────────

  void _scheduleCritical() {
    _scheduler.schedule(
      () async {
        await Future.delayed(const Duration(milliseconds: 2));
        _addLog('🚨 CRITICAL executed immediately');
      },
      priority: PriorityLevel.critical,
      estimatedDurationMs: 2,
      id: 'demo_critical_${DateTime.now().millisecond}',
    );
  }

  void _scheduleHigh() {
    _scheduler.schedule(
      () async {
        await Future.delayed(const Duration(milliseconds: 30));
        _addLog('🔺 HIGH executed');
      },
      priority: PriorityLevel.high,
      estimatedDurationMs: 30,
      id: 'demo_high_${DateTime.now().millisecond}',
      maxWaitMs: 5000,
      onDropped: () => _addLog('🔺 HIGH was DROPPED'),
    );
  }

  void _scheduleNormal() {
    _scheduler.schedule(
      () async {
        await Future.delayed(const Duration(milliseconds: 50));
        _addLog('🔹 NORMAL executed');
      },
      priority: PriorityLevel.normal,
      estimatedDurationMs: 50,
      id: 'demo_normal_${DateTime.now().millisecond}',
      maxWaitMs: 4000,
      onDropped: () => _addLog('🔹 NORMAL was DROPPED'),
    );
  }

  void _scheduleLow() {
    _scheduler.schedule(
      () async {
        _addLog('🔸 LOW (analytics) executed');
      },
      priority: PriorityLevel.low,
      estimatedDurationMs: 1,
      id: 'demo_low_${DateTime.now().millisecond}',
      maxWaitMs: 3000,
      onDropped: () => _addLog('🔸 LOW was DROPPED (expected during stress)'),
    );
  }

  void _scheduleHeavyWork() {
    _scheduler.schedule(
      () async {
        await _burnCpu(80);
        _addLog('💪 Heavy work (80ms CPU burn) completed');
      },
      priority: PriorityLevel.normal,
      estimatedDurationMs: 80,
      id: 'demo_heavy_${DateTime.now().millisecond}',
      maxWaitMs: 6000,
      onDropped: () => _addLog('💪 Heavy work DROPPED'),
    );
  }

  void _toggleStressTest() {
    if (_isStressTesting) {
      _stressTimer?.cancel();
      setState(() => _isStressTesting = false);
      _addLog('🛑 Stress test stopped');
    } else {
      setState(() => _isStressTesting = true);
      _addLog('🔥 Stress test started — watch the overlay!');
      // Schedule a heavy task every 100ms to stress the scheduler
      _stressTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          _scheduler.schedule(
            () async => await _burnCpu(60),
            priority: PriorityLevel.normal,
            estimatedDurationMs: 60,
            id: 'stress_${DateTime.now().microsecondsSinceEpoch}',
          );
        },
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('frame_scheduler Demo'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Animated spinner (FPS health canary) ──
                Center(
                  child: AnimatedBuilder(
                    animation: _spinController,
                    builder: (_, child) => Transform.rotate(
                      angle: _spinController.value * 2 * pi,
                      child: child,
                    ),
                    child: const FlutterLogo(size: 100),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'If this stutters, the scheduler is working!',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Zone banner (reactive via SchedulerBuilder) ──
                SchedulerBuilder(
                  builder: (ctx, zone) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _zoneColor(zone).withValues(alpha: 0.15),
                      border: Border.all(color: _zoneColor(zone)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(zone.emoji, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          zone.description,
                          style: TextStyle(
                            color: _zoneColor(zone),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Priority buttons ──
                const _SectionHeader('Schedule by Priority'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PriorityButton(
                      label: '🚨 Critical',
                      color: const Color(0xFFE53935),
                      onPressed: _scheduleCritical,
                    ),
                    _PriorityButton(
                      label: '🔺 High',
                      color: const Color(0xFFFF6D00),
                      onPressed: _scheduleHigh,
                    ),
                    _PriorityButton(
                      label: '🔹 Normal',
                      color: const Color(0xFF1565C0),
                      onPressed: _scheduleNormal,
                    ),
                    _PriorityButton(
                      label: '🔸 Low',
                      color: const Color(0xFF37474F),
                      onPressed: _scheduleLow,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Heavy work ──
                const _SectionHeader('Simulate Heavy Work'),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.memory),
                  label: const Text('Schedule 80ms CPU Burn (Normal)'),
                  onPressed: _scheduleHeavyWork,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: Icon(_isStressTesting ? Icons.stop : Icons.bolt),
                  label: Text(
                    _isStressTesting ? 'Stop Stress Test' : 'Start Stress Test',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStressTesting
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFF1B5E20),
                  ),
                  onPressed: _toggleStressTest,
                ),
                const SizedBox(height: 20),

                // ── Metrics dashboard ──
                const _SectionHeader('Live Metrics'),
                const SizedBox(height: 8),
                _MetricsDashboard(scheduler: _scheduler),
                const SizedBox(height: 20),

                // ── Event log ──
                const _SectionHeader('Event Log'),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ListView.builder(
                    reverse: false,
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Text(
                      _log[i],
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 80), // bottom padding
              ],
            ),
          ),

          // FPS Debug Overlay
          const FpsOverlay(
            alignment: Alignment.topRight,
            showQueueDepth: true,
            showMetrics: true,
          ),
        ],
      ),
    );
  }

  Color _zoneColor(FpsZone zone) {
    switch (zone) {
      case FpsZone.healthy:
        return const Color(0xFF4CAF50);
      case FpsZone.warning:
        return const Color(0xFFFF9800);
      case FpsZone.critical:
        return const Color(0xFFF44336);
      case FpsZone.danger:
        return const Color(0xFF9C27B0);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Colors.white54, letterSpacing: 0.5),
      );
}

class _PriorityButton extends StatelessWidget {
  const _PriorityButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: color),
        onPressed: onPressed,
        child: Text(label),
      );
}

class _MetricsDashboard extends StatefulWidget {
  const _MetricsDashboard({required this.scheduler});
  final SchedulerController scheduler;

  @override
  State<_MetricsDashboard> createState() => _MetricsDashboardState();
}

class _MetricsDashboardState extends State<_MetricsDashboard> {
  late Timer _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.scheduler.metrics;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          _MetricRow('✅ Executed', '${m.executedCount}'),
          _MetricRow('⏳ Deferred', '${m.deferredCount}'),
          _MetricRow('❌ Dropped', '${m.droppedCount}'),
          _MetricRow('⌛ Expired', '${m.expiredCount}'),
          _MetricRow(
            '⏱ Avg Execution',
            '${m.meanExecutionMs.toStringAsFixed(2)} ms',
          ),
          _MetricRow('📊 Drop Rate', '${m.dropRate.toStringAsFixed(1)}%'),
          _MetricRow('🔄 Zone Transitions', '${m.zoneTransitions}'),
          _MetricRow('📦 Peak Queue', '${m.peakQueueLength}'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              widget.scheduler.resetMetrics();
              setState(() {});
            },
            child: const Text('Reset Metrics'),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: Colors.white)),
          ],
        ),
      );
}
