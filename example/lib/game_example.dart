// ============================================================
// frame_scheduler — Game-Specific Example
// ============================================================
//
// Simulates a 2D arcade game scenario where:
//
//   • Physics updates run as CRITICAL tasks (must never miss a frame)
//   • Enemy AI decisions run as HIGH tasks (important but deferrable)
//   • Asset streaming for the next wave runs as NORMAL tasks
//   • Analytics / telemetry events run as LOW tasks
//
// The demo spawns a fake "game loop" that produces work for the
// scheduler at varying rates, with a simulated FPS drop button
// to observe deferral behaviour in real time.
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

class GameExample extends StatefulWidget {
  const GameExample({super.key});

  @override
  State<GameExample> createState() => _GameExampleState();
}

class _GameExampleState extends State<GameExample>
    with TickerProviderStateMixin {
  // ── Game state ─────────────────────────────────────────────────────────────
  int _score = 0;
  int _wave = 1;
  int _enemiesAlive = 5;
  bool _isRunning = false;

  // ── Scheduler ─────────────────────────────────────────────────────────────
  final _scheduler = SchedulerController.instance;
  Timer? _gameLoopTimer;
  Timer? _waveSpawnTimer;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _bgPulse;
  late AnimationController _scorePopController;
  late Animation<double> _scorePop;

  // ── Event log ─────────────────────────────────────────────────────────────
  final List<_GameEvent> _events = [];

  // ── Random ────────────────────────────────────────────────────────────────
  final _rng = Random();

  @override
  void initState() {
    super.initState();

    _bgPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _scorePopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scorePop = CurvedAnimation(
      parent: _scorePopController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _gameLoopTimer?.cancel();
    _waveSpawnTimer?.cancel();
    _bgPulse.dispose();
    _scorePopController.dispose();
    super.dispose();
  }

  // ── Game loop ──────────────────────────────────────────────────────────────

  void _startGame() {
    setState(() {
      _isRunning = true;
      _score = 0;
      _wave = 1;
      _enemiesAlive = 5;
    });
    _startGameLoop();
    _startWaveSpawner();
    _log('🎮 Game started — Wave $_wave');
  }

  void _stopGame() {
    _gameLoopTimer?.cancel();
    _waveSpawnTimer?.cancel();
    setState(() => _isRunning = false);
    _log('⏹ Game stopped');
  }

  void _startGameLoop() {
    // Simulate a 60fps game loop tick
    _gameLoopTimer = Timer.periodic(
      const Duration(milliseconds: 16), // ~60fps
      (timer) {
        if (!_isRunning) {
          timer.cancel();
          return;
        }
        _gameLoopTick();
      },
    );
  }

  void _startWaveSpawner() {
    _waveSpawnTimer = Timer.periodic(
      const Duration(seconds: 8),
      (timer) {
        if (!_isRunning) {
          timer.cancel();
          return;
        }
        _spawnNextWave();
      },
    );
  }

  void _gameLoopTick() {
    // ── CRITICAL: Physics update — must NEVER be deferred
    _scheduler.schedule(
      () async => _updatePhysics(),
      priority: PriorityLevel.critical,
      estimatedDurationMs: 1.5,
      id: 'physics_${DateTime.now().microsecondsSinceEpoch}',
    );

    // ── HIGH: Enemy AI decision — once per 10 ticks (~6 fps)
    if (_rng.nextInt(10) == 0) {
      _scheduler.schedule(
        () async => _runEnemyAI(),
        priority: PriorityLevel.high,
        estimatedDurationMs: 8.0,
        id: 'enemy_ai_${DateTime.now().microsecondsSinceEpoch}',
        maxWaitMs: 500,
        onDropped: () => _log('🤖 Enemy AI decision deferred too long — skipped'),
      );
    }

    // ── LOW: Analytics heartbeat — once per 300 ticks (~5 sec)
    if (_rng.nextInt(300) == 0) {
      _scheduler.schedule(
        () async => _sendAnalytics(),
        priority: PriorityLevel.low,
        estimatedDurationMs: 0.5,
        id: 'analytics_${DateTime.now().microsecondsSinceEpoch}',
        maxWaitMs: 10000,
        onDropped: () => _log('📊 Analytics heartbeat dropped (FPS too low)'),
      );
    }
  }

  void _spawnNextWave() {
    setState(() {
      _wave++;
      _enemiesAlive = _wave * 3;
    });
    _log('🌊 Wave $_wave spawned — $_enemiesAlive enemies');

    // ── NORMAL: Stream new wave's assets — deferrable
    _scheduler.schedule(
      () async {
        // Simulate asset streaming: ~40ms
        await Future.delayed(Duration(milliseconds: 30 + _rng.nextInt(30)));
        _log('🗂 Wave $_wave assets loaded');
      },
      priority: PriorityLevel.normal,
      estimatedDurationMs: 40.0,
      id: 'wave_${_wave}_assets',
      maxWaitMs: 5000,
      onDropped: () => _log('⚠️ Wave $_wave assets DROPPED — will use fallback'),
    );
  }

  // ── Simulated game sub-systems ─────────────────────────────────────────────

  void _updatePhysics() {
    // Real physics would integrate velocity, check collisions, etc.
    // Here we just keep the enemy count moving.
    if (_enemiesAlive > 0 && _rng.nextDouble() < 0.005) {
      setState(() {
        _enemiesAlive--;
        _score += 10 * _wave;
        _scorePopController.forward(from: 0);
      });
    }
  }

  void _runEnemyAI() {
    // Simulate a brief AI evaluation
    final decision = _rng.nextInt(3);
    final decisions = ['PATROL', 'CHASE', 'ATTACK'];
    _log('🤖 Enemy AI → ${decisions[decision]}');
  }

  void _sendAnalytics() {
    _log('📊 Analytics: score=$_score, wave=$_wave, fps=${_scheduler.currentFps.toStringAsFixed(1)}');
  }

  // ── Player actions ─────────────────────────────────────────────────────────

  void _playerShoot() {
    // Player input must always use CRITICAL to feel instant
    _scheduler.schedule(
      () async {
        if (_enemiesAlive > 0) {
          setState(() {
            _enemiesAlive--;
            _score += 50 * _wave;
          });
          _scorePopController.forward(from: 0);
        }
        _log('💥 Player fired! Score: $_score');
      },
      priority: PriorityLevel.critical,
      estimatedDurationMs: 1.0,
      id: 'player_shoot_${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  // ── Logging ───────────────────────────────────────────────────────────────

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(
        0,
        _GameEvent(
          message: message,
          time: DateTime.now(),
          zone: _scheduler.currentZone,
        ),
      );
      if (_events.length > 30) _events.removeLast();
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text(
          '🎮 frame_scheduler — Game Demo',
          style: TextStyle(color: Colors.white70),
        ),
      ),
      body: Stack(
        children: [
          // Animated background
          AnimatedBuilder(
            animation: _bgPulse,
            builder: (_, __) => Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Color.lerp(
                      const Color(0xFF0D0D1A),
                      const Color(0xFF1A0A2E),
                      _bgPulse.value,
                    )!,
                    const Color(0xFF0D0D1A),
                  ],
                  radius: 1.5,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Score / Wave header ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _GlowText('WAVE $_wave',
                          color: Colors.cyanAccent, size: 18),
                      ScaleTransition(
                        scale: _scorePop
                            .drive(Tween(begin: 1.0, end: 1.4)),
                        child: _GlowText('SCORE: $_score',
                            color: Colors.amber, size: 18),
                      ),
                      _GlowText('👾 $_enemiesAlive',
                          color: Colors.redAccent, size: 18),
                    ],
                  ),
                ),

                // ── Zone banner ──
                SchedulerBuilder(
                  builder: (ctx, zone) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _zoneColor(zone).withValues(alpha: 0.6),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${zone.emoji}  ${zone.description}  '
                      '· ${_scheduler.currentFps.toStringAsFixed(1)} fps  '
                      '· ${_scheduler.pendingTaskCount} queued',
                      style: TextStyle(
                        color: _zoneColor(zone),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Action buttons ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(_isRunning
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded),
                          label: Text(_isRunning ? 'Stop' : 'Start'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRunning
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                          onPressed: _isRunning ? _stopGame : _startGame,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.gps_fixed),
                          label: const Text('🔫 SHOOT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade800,
                          ),
                          onPressed: _isRunning ? _playerShoot : null,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Event log ──
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListView.builder(
                      itemCount: _events.length,
                      itemBuilder: (_, i) {
                        final e = _events[i];
                        return Text(
                          '[${e.time.toIso8601String().substring(11, 23)}] '
                          '${e.zone.emoji} ${e.message}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // FPS overlay
          const FpsOverlay(showMetrics: true),
        ],
      ),
    );
  }

  Color _zoneColor(FpsZone zone) {
    switch (zone) {
      case FpsZone.healthy:
        return Colors.greenAccent;
      case FpsZone.warning:
        return Colors.orangeAccent;
      case FpsZone.critical:
        return Colors.redAccent;
      case FpsZone.danger:
        return Colors.purpleAccent;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GlowText extends StatelessWidget {
  const _GlowText(this.text, {required this.color, required this.size});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          shadows: [
            Shadow(blurRadius: 8, color: color.withValues(alpha: 0.8)),
            Shadow(blurRadius: 16, color: color.withValues(alpha: 0.4)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _GameEvent {
  const _GameEvent({
    required this.message,
    required this.time,
    required this.zone,
  });
  final String message;
  final DateTime time;
  final FpsZone zone;
}
