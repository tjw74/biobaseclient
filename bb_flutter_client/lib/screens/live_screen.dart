import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../models/session_stats.dart';
import '../theme.dart';

const _kGreen = BiobaseColors.live;
const _kBlue = BiobaseColors.accent;
const _kAmber = BiobaseColors.warning;
const _kPurple = Color(0xFF8B5CF6);
const _kRed = BiobaseColors.error;
const _kCyan = Color(0xFF06B6D4);

class _MetricDef {
  final String label;
  final String Function(SessionStats s, LiveFrame f) value;
  final String unit;
  const _MetricDef(this.label, this.value, [this.unit = '']);
}

class _CategoryDef {
  final String name;
  final Color color;
  final IconData icon;
  final List<_MetricDef> metrics;
  const _CategoryDef(this.name, this.color, this.icon, this.metrics);
}

String _f0(double v) => v.toStringAsFixed(0);
String _f1(double v) => v.toStringAsFixed(1);
String _f2(double v) => v.toStringAsFixed(2);
String _pct(double v) => '${v.toInt()}%';
String _ms(double v) => '${v.toInt()}ms';

final _categories = [
  _CategoryDef('Movement', _kGreen, Icons.directions_run, [
    _MetricDef('Speed', (s, f) => '${f.speed}', 'u/s'),
    _MetricDef('Max Speed', (s, f) => _f0(s.speedMax)),
    _MetricDef('Avg Speed', (s, f) => _f0(s.speedAvgSafe)),
    _MetricDef('Distance', (s, f) => _f0(s.distanceTraveled), 'units'),
    _MetricDef('Path Efficiency', (s, f) => _f2(s.pathEfficiency)),
    _MetricDef('Air Time', (s, f) => _pct(s.airTimePercent)),
    _MetricDef('Ground Samples', (s, f) => '${s.groundSamples}'),
    _MetricDef('Air Samples', (s, f) => '${s.airSamples}'),
    _MetricDef('State', (s, f) => s.movementState),
  ]),
  _CategoryDef('Aim', _kBlue, Icons.gps_fixed, [
    _MetricDef('Headshot %', (s, f) => _pct(s.headshotPercent)),
    _MetricDef('First Bullet Accuracy', (s, f) => _pct(s.firstBulletAccuracy)),
    _MetricDef('Spray Accuracy', (s, f) => _pct(s.sprayAccuracy)),
    _MetricDef('Spray Transfer', (s, f) => _pct(s.sprayTransferSuccess)),
    _MetricDef('Burst Accuracy', (s, f) => _pct(s.burstAccuracy)),
    _MetricDef('Tap Accuracy', (s, f) => _pct(s.tapAccuracy)),
    _MetricDef('Missed Shots', (s, f) => '${s.missedShots}'),
    _MetricDef('Crosshair Placement', (s, f) => _f1(s.crosshairPlacementError), '°'),
    _MetricDef('Head Level %', (s, f) => _pct(s.crosshairHeadLevelPercent)),
    _MetricDef('Flick Distance', (s, f) => _f1(s.flickDistance)),
    _MetricDef('Flick Accuracy', (s, f) => _pct(s.flickAccuracy)),
    _MetricDef('Pre-aim Accuracy', (s, f) => _pct(s.preAimAccuracy)),
    _MetricDef('Reaction Time', (s, f) => _ms(s.reactionTime)),
    _MetricDef('Time to First Shot', (s, f) => '${_f2(s.timeToFirstShot)}s'),
    _MetricDef('Time to Kill', (s, f) => '${_f2(s.timeToKill)}s'),
  ]),
  _CategoryDef('Combat', _kRed, Icons.flash_on, [
    _MetricDef('Entry Attempts', (s, f) => '${s.entryAttempts}'),
    _MetricDef('Entry Success', (s, f) => '${s.entrySuccesses}'),
    _MetricDef('Entry Rate', (s, f) => _pct(s.entrySuccessRate)),
    _MetricDef('Trade Opportunities', (s, f) => '${s.tradeOpportunities}'),
    _MetricDef('Successful Trades', (s, f) => '${s.successfulTrades}'),
    _MetricDef('Trade Time', (s, f) => '${_f2(s.tradeTime)}s'),
    _MetricDef('Time Alive', (s, f) => '${_f1(s.timeAlive)}s'),
    _MetricDef('Survival Rate', (s, f) => _pct(s.survivalRate)),
    _MetricDef('Damage Dealt', (s, f) => '${s.damageDealt}'),
    _MetricDef('Damage Received', (s, f) => '${s.damageReceived}'),
    _MetricDef('Damage Per Round', (s, f) => _f1(s.damagePerRound)),
  ]),
  _CategoryDef('Utility', _kAmber, Icons.local_fire_department, [
    _MetricDef('Flash Effectiveness', (s, f) => _pct(s.flashEffectiveness)),
    _MetricDef('Flash Duration', (s, f) => '${_f1(s.flashBlindnessDuration)}s'),
    _MetricDef('Enemies Flashed', (s, f) => '${s.enemiesFlashed}'),
    _MetricDef('Teammates Flashed', (s, f) => '${s.teammatesFlashed}'),
    _MetricDef('Smoke Effectiveness', (s, f) => _pct(s.smokeEffectiveness)),
    _MetricDef('Molotov Effectiveness', (s, f) => _pct(s.molotovEffectiveness)),
    _MetricDef('HE Effectiveness', (s, f) => _pct(s.heEffectiveness)),
    _MetricDef('Utility Damage', (s, f) => '${s.utilityDamage}'),
    _MetricDef('Usage Efficiency', (s, f) => _pct(s.utilityUsageEfficiency)),
    _MetricDef('Lineup Success', (s, f) => _pct(s.grenadeLineupSuccess)),
  ]),
  _CategoryDef('Positioning', _kCyan, Icons.my_location, [
    _MetricDef('Time Exposed', (s, f) => '${_f1(s.timeExposed)}s'),
    _MetricDef('Time In Cover', (s, f) => '${_f1(s.timeInCover)}s'),
    _MetricDef('Peek Count', (s, f) => '${s.peekCount}'),
    _MetricDef('Wide Peeks', (s, f) => '${s.widePeekCount}'),
    _MetricDef('Jiggle Peeks', (s, f) => '${s.jigglePeekCount}'),
    _MetricDef('Shoulder Peeks', (s, f) => '${s.shoulderPeekCount}'),
    _MetricDef('Re-peeks', (s, f) => '${s.rePeekCount}'),
    _MetricDef('Peek Success', (s, f) => _pct(s.peekSuccessRate)),
    _MetricDef('Team Spacing', (s, f) => _f0(s.teamSpacing)),
    _MetricDef('Nearest Teammate', (s, f) => _f0(s.nearestTeammateDistance)),
    _MetricDef('Isolation Deaths', (s, f) => '${s.isolationDeaths}'),
  ]),
  _CategoryDef('Decision Making', const Color(0xFF818CF8), Icons.psychology, [
    _MetricDef('Rotation Timing', (s, f) => '${_f1(s.rotationTiming)}s'),
    _MetricDef('Rotation Efficiency', (s, f) => _pct(s.rotationEfficiency)),
    _MetricDef('Decision Latency', (s, f) => _ms(s.decisionLatency)),
    _MetricDef('Angle Hold Duration', (s, f) => '${_f1(s.angleHoldDuration)}s'),
    _MetricDef('Angle Win Rate', (s, f) => _pct(s.angleWinRate)),
    _MetricDef('Crosshair Idle', (s, f) => '${_f1(s.crosshairIdleTime)}s'),
    _MetricDef('Off Target Time', (s, f) => '${_f1(s.crosshairOffTargetTime)}s'),
  ]),
  _CategoryDef('Economy', const Color(0xFFFBBF24), Icons.attach_money, [
    _MetricDef('Equipment Value', (s, f) => '\$${s.equipmentValue}'),
    _MetricDef('Economy State', (s, f) => s.economyState),
  ]),
  _CategoryDef('Teamplay', _kGreen, Icons.group, [
    _MetricDef('Teammates Flashed', (s, f) => '${s.teammatesFlashed}'),
    _MetricDef('Team Spacing', (s, f) => _f0(s.teamSpacing)),
    _MetricDef('Nearest Teammate', (s, f) => _f0(s.nearestTeammateDistance)),
    _MetricDef('Isolation Deaths', (s, f) => '${s.isolationDeaths}'),
  ]),
  _CategoryDef('Round Performance', _kBlue, Icons.emoji_events, [
    _MetricDef('Win Probability', (s, f) => _pct(s.roundWinProbability)),
    _MetricDef('Clutch Attempts', (s, f) => '${s.clutchAttempts}'),
    _MetricDef('Clutch Success', (s, f) => _pct(s.clutchSuccessPercent)),
    _MetricDef('Opening Duel %', (s, f) => _pct(s.openingDuelPercent)),
    _MetricDef('Opening Duel Win', (s, f) => _pct(s.openingDuelWinPercent)),
    _MetricDef('Multi-kill Rounds', (s, f) => '${s.multiKillRounds}'),
    _MetricDef('ADR', (s, f) => _f1(s.adr)),
    _MetricDef('KAST', (s, f) => _pct(s.kast)),
    _MetricDef('HLTV Rating', (s, f) => _f2(s.hltvRating)),
  ]),
  _CategoryDef('Consistency', _kPurple, Icons.trending_up, [
    _MetricDef('Consistency Score', (s, f) => _f0(s.consistencyScore)),
    _MetricDef('Confidence Score', (s, f) => _f0(s.confidenceScore)),
  ]),
  _CategoryDef('Mechanical Execution', _kAmber, Icons.precision_manufacturing, [
    _MetricDef('Strafe Sync', (s, f) => _pct(s.strafeSyncPercent)),
    _MetricDef('Counter-strafe Accuracy', (s, f) => _pct(s.counterStrafeAccuracy)),
    _MetricDef('Counter-strafe Stop', (s, f) => _ms(s.counterStrafeStopTime)),
    _MetricDef('Time to Full Accuracy', (s, f) => _ms(s.timeToFullAccuracy)),
    _MetricDef('Bhop Success Rate', (s, f) => _pct(s.bhopSuccessRate)),
    _MetricDef('Max Consecutive Bhops', (s, f) => '${s.consecutiveBhopsMax}'),
    _MetricDef('Perfect Jump %', (s, f) => _pct(s.perfectJumpPercent)),
    _MetricDef('Jump Timing', (s, f) => _f2(s.jumpTimingConsistency)),
    _MetricDef('Air Strafe Efficiency', (s, f) => _pct(s.airStrafeEfficiency)),
    _MetricDef('Landing Speed Retention', (s, f) => _pct(s.landingSpeedRetention)),
    _MetricDef('Speed Loss on Landing', (s, f) => _f1(s.speedLossOnLanding)),
  ]),
  _CategoryDef('BioBase Biometrics', _kCyan, Icons.monitor_heart, [
    _MetricDef('Fatigue Score', (s, f) => _f0(s.fatigueScore)),
    _MetricDef('Confidence', (s, f) => _f0(s.confidenceScore)),
    _MetricDef('Footsteps', (s, f) => '${s.footstepCount}'),
    _MetricDef('Weapon Switches', (s, f) => '${s.weaponSwitchCount}'),
    _MetricDef('Reload Timing', (s, f) => '${_f2(s.reloadTiming)}s'),
    _MetricDef('Reload Cancels', (s, f) => '${s.reloadCancelCount}'),
  ]),
];

class LiveScreen extends StatefulWidget {
  final LiveFrame frame;
  final bool live;
  final List<LiveMovementSample> history;
  final SessionStats sessionStats;

  const LiveScreen({
    super.key,
    required this.frame,
    this.live = false,
    this.history = const [],
    required this.sessionStats,
  });

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final Set<int> _expanded = {0};

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    final stats = widget.sessionStats;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SessionInfo(frame: frame, stats: stats),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _MetricCard(dotColor: _kGreen, label: 'SPEED',
              value: '${frame.speed}', description: 'units per second',
              progress: (frame.speed / 250).clamp(0.0, 1.0))),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(dotColor: _kBlue, label: 'COUNTER-STRAFE',
              value: frame.counterStrafeScore.toStringAsFixed(2), description: 'deceleration accuracy',
              progress: frame.counterStrafeScore.clamp(0.0, 1.0))),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(dotColor: _kAmber, label: 'PATH EFFICIENCY',
              value: frame.pathEfficiency.toStringAsFixed(2), description: 'optimal route adherence',
              progress: frame.pathEfficiency.clamp(0.0, 1.0))),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(dotColor: _kPurple, label: 'STRAFE SYNC',
              value: '${stats.strafeSyncPercent.toInt()}%', description: 'air strafe synchronization',
              progress: (stats.strafeSyncPercent / 100).clamp(0.0, 1.0))),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _SpeedChart(history: widget.history, frame: frame, live: widget.live)),
              const SizedBox(width: 12),
              Expanded(child: _VelocityChart(history: widget.history, frame: frame)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StateTimeline(history: widget.history),
        const SizedBox(height: 8),
        _InputRow(frame: frame),
        const SizedBox(height: 20),
        // All metrics by category
        for (int i = 0; i < _categories.length; i++) ...[
          _CategorySection(
            category: _categories[i],
            stats: stats,
            frame: frame,
            expanded: _expanded.contains(i),
            onToggle: () => setState(() {
              if (_expanded.contains(i)) { _expanded.remove(i); }
              else { _expanded.add(i); }
            }),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

// ── Category Section ──

class _CategorySection extends StatelessWidget {
  final _CategoryDef category;
  final SessionStats stats;
  final LiveFrame frame;
  final bool expanded;
  final VoidCallback onToggle;

  const _CategorySection({
    required this.category,
    required this.stats,
    required this.frame,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(color: category.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Icon(category.icon, size: 14, color: BiobaseColors.textTertiary),
                    const SizedBox(width: 8),
                    Text(category.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
                    const SizedBox(width: 8),
                    Text('${category.metrics.length}', style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
                    const Spacer(),
                    Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: BiobaseColors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            Container(height: 1, color: BiobaseColors.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in category.metrics)
                    _MetricCell(label: m.label, value: m.value(stats, frame), unit: m.unit, color: category.color),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MetricCell({required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w500, color: BiobaseColors.textTertiary, letterSpacing: 0.3)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BiobaseColors.text, letterSpacing: -0.5, height: 1)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(unit, style: const TextStyle(fontSize: 9, color: BiobaseColors.textTertiary)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Session Info ──

class _SessionInfo extends StatelessWidget {
  final LiveFrame frame;
  final SessionStats stats;

  const _SessionInfo({required this.frame, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _kv('Map', frame.mapName),
          _div(),
          _kv('Player', frame.playerName),
          _div(),
          _kv('Max', '${stats.speedMax.toInt()}'),
          _div(),
          _kv('Avg', '${stats.speedAvgSafe.toInt()}'),
          _div(),
          _kv('Jumps', '${stats.jumpCount}'),
          _div(),
          _kv('Bhop', '${stats.consecutiveBhopsMax}'),
          _div(),
          _kv('Sync', '${stats.strafeSyncPercent.toInt()}%'),
          _div(),
          _kv('Distance', _fd(stats.distanceTraveled)),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BiobaseColors.text, fontFamily: 'monospace', letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _div() {
    return Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 2), color: BiobaseColors.borderSubtle);
  }

  String _fd(double d) {
    if (d >= 10000) return '${(d / 1000).toStringAsFixed(0)}k';
    if (d >= 1000) return '${(d / 1000).toStringAsFixed(1)}k';
    return d.toInt().toString();
  }
}

// ── Metric Card ──

class _MetricCard extends StatelessWidget {
  final Color dotColor;
  final String label;
  final String value;
  final String description;
  final double progress;

  const _MetricCard({required this.dotColor, required this.label, required this.value, required this.description, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: BiobaseColors.text, letterSpacing: -1, height: 1)),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: SizedBox(height: 2, child: LinearProgressIndicator(
              value: progress, backgroundColor: BiobaseColors.surfaceRaised,
              valueColor: AlwaysStoppedAnimation(dotColor.withAlpha(160)),
            )),
          ),
        ],
      ),
    );
  }
}

// ── Speed Chart ──

class _SpeedChart extends StatelessWidget {
  final List<LiveMovementSample> history;
  final LiveFrame frame;
  final bool live;

  const _SpeedChart({required this.history, required this.frame, required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Speed History', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
            const Spacer(),
            if (live) Container(width: 6, height: 6, decoration: BoxDecoration(
              color: BiobaseColors.live, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: BiobaseColors.live.withAlpha(100), blurRadius: 6)],
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _leg(BiobaseColors.accent, 'Speed', '${frame.speed}'),
            const SizedBox(width: 16),
            _leg(BiobaseColors.live, 'Max', '250'),
            const SizedBox(width: 16),
            _leg(BiobaseColors.textTertiary, 'Run', '150'),
          ]),
          const SizedBox(height: 10),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
            child: CustomPaint(size: const Size(double.infinity, double.infinity),
              painter: _SpeedTracePainter(
                speeds: history.map((s) => s.speed).toList(),
                onGround: history.map((s) => s.onGround).toList(),
              ),
            ),
          )),
          const SizedBox(height: 6),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('HISTORY', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
            Text('NOW', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
          ]),
        ],
      ),
    );
  }

  Widget _leg(Color c, String label, String val) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label ', style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
      Text(val, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c, fontFamily: 'monospace')),
    ]);
  }
}

class _SpeedTracePainter extends CustomPainter {
  final List<double> speeds;
  final List<bool> onGround;
  _SpeedTracePainter({required this.speeds, required this.onGround});

  @override
  void paint(Canvas canvas, Size size) {
    const maxSpeed = 300.0;
    const barH = 3.0;
    final chartH = size.height - barH;

    for (final (val, color) in [(250.0, BiobaseColors.live), (150.0, BiobaseColors.textTertiary)]) {
      final y = chartH - (val / maxSpeed).clamp(0.0, 1.0) * chartH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = color.withAlpha(20)..strokeWidth = 0.5);
    }
    for (int i = 1; i < 4; i++) {
      final y = chartH * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = BiobaseColors.surfaceRaised.withAlpha(50)..strokeWidth = 0.5);
    }
    if (speeds.isEmpty) return;
    final n = speeds.length;
    final d = max(1, n - 1).toDouble();

    for (int i = 0; i < n && i < onGround.length; i++) {
      final x = (i / d) * size.width;
      final nx = ((i + 1) / d) * size.width;
      canvas.drawRect(Rect.fromLTWH(x, size.height - barH, nx - x, barH),
        Paint()..color = onGround[i] ? BiobaseColors.textTertiary.withAlpha(15) : BiobaseColors.warning.withAlpha(40));
    }

    final path = Path();
    final fill = Path();
    for (int i = 0; i < n; i++) {
      final x = (i / d) * size.width;
      final y = chartH - (speeds[i] / maxSpeed).clamp(0.0, 1.0) * chartH;
      if (i == 0) { path.moveTo(x, y); fill.moveTo(x, chartH); fill.lineTo(x, y); }
      else { path.lineTo(x, y); fill.lineTo(x, y); }
    }
    fill.lineTo(((n - 1) / d) * size.width, chartH);
    fill.close();

    canvas.drawPath(fill, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [BiobaseColors.accent.withAlpha(35), BiobaseColors.accent.withAlpha(2)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, chartH)));
    canvas.drawPath(path, Paint()..color = BiobaseColors.accent..strokeWidth = 1.5
      ..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);

    final lx = ((n - 1) / d) * size.width;
    final ly = chartH - (speeds.last / maxSpeed).clamp(0.0, 1.0) * chartH;
    canvas.drawCircle(Offset(lx, ly), 3, Paint()..color = BiobaseColors.accent.withAlpha(40));
    canvas.drawCircle(Offset(lx, ly), 1.5, Paint()..color = BiobaseColors.accent);
  }

  @override
  bool shouldRepaint(covariant _SpeedTracePainter old) => speeds.length != old.speeds.length;
}

// ── Velocity Chart ──

class _VelocityChart extends StatelessWidget {
  final List<LiveMovementSample> history;
  final LiveFrame frame;
  const _VelocityChart({required this.history, required this.frame});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Velocity Components', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
          const SizedBox(height: 12),
          Row(children: [
            _leg(const Color(0xFF3B82F6), 'X', _fv(0)),
            const SizedBox(width: 16),
            _leg(const Color(0xFF10B981), 'Y', _fv(1)),
            const SizedBox(width: 16),
            _leg(const Color(0xFFF59E0B), 'Z', _fv(2)),
          ]),
          const SizedBox(height: 10),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
            child: CustomPaint(size: const Size(double.infinity, double.infinity),
              painter: _VelocityTracePainter(
                velX: history.map((s) => s.velX).toList(),
                velY: history.map((s) => s.velY).toList(),
                velZ: history.map((s) => s.velZ).toList(),
              ),
            ),
          )),
          const SizedBox(height: 6),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('HISTORY', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
            Text('NOW', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
          ]),
        ],
      ),
    );
  }

  String _fv(int i) => (frame.vel.length > i ? frame.vel[i] : 0.0).toStringAsFixed(0);
  Widget _leg(Color c, String axis, String val) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$axis ', style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
      Text(val, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c, fontFamily: 'monospace')),
    ]);
  }
}

class _VelocityTracePainter extends CustomPainter {
  final List<double> velX, velY, velZ;
  _VelocityTracePainter({required this.velX, required this.velY, required this.velZ});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2),
      Paint()..color = BiobaseColors.surfaceRaised.withAlpha(60)..strokeWidth = 0.5);
    if (velX.isEmpty) return;
    double mx = 1;
    for (final l in [velX, velY, velZ]) { for (final v in l) { if (v.abs() > mx) mx = v.abs(); } }
    mx *= 1.1;
    void trace(List<double> v, Color c) {
      if (v.isEmpty) return;
      final p = Path();
      final d = max(1, v.length - 1).toDouble();
      for (int i = 0; i < v.length; i++) {
        final x = (i / d) * size.width;
        final y = size.height / 2 - (v[i] / mx) * (size.height / 2);
        if (i == 0) { p.moveTo(x, y); } else { p.lineTo(x, y); }
      }
      canvas.drawPath(p, Paint()..color = c..strokeWidth = 1.2..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round);
    }
    trace(velX, const Color(0xFF3B82F6));
    trace(velY, const Color(0xFF10B981));
    trace(velZ, const Color(0xFFF59E0B));
  }

  @override
  bool shouldRepaint(covariant _VelocityTracePainter old) => velX.length != old.velX.length;
}

// ── State Timeline ──

class _StateTimeline extends StatelessWidget {
  final List<LiveMovementSample> history;
  const _StateTimeline({required this.history});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(3),
      child: SizedBox(height: 6,
        child: CustomPaint(size: const Size(double.infinity, 6),
          painter: _StateTimelinePainter(states: history.map((s) => s.onGround).toList()),
        ),
      ),
    );
  }
}

class _StateTimelinePainter extends CustomPainter {
  final List<bool> states;
  _StateTimelinePainter({required this.states});

  @override
  void paint(Canvas canvas, Size size) {
    if (states.isEmpty) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = BiobaseColors.surfaceRaised.withAlpha(40));
      return;
    }
    final n = states.length;
    final w = size.width / n;
    for (int i = 0; i < n; i++) {
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 0.5, size.height),
        Paint()..color = states[i] ? BiobaseColors.surfaceRaised.withAlpha(40) : BiobaseColors.warning.withAlpha(50));
    }
  }

  @override
  bool shouldRepaint(covariant _StateTimelinePainter old) => states.length != old.states.length;
}

// ── Input Row ──

class _InputRow extends StatelessWidget {
  final LiveFrame frame;
  const _InputRow({required this.frame});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(children: [
        _k('W', frame.keys.w), const SizedBox(width: 3),
        _k('A', frame.keys.a), const SizedBox(width: 3),
        _k('S', frame.keys.s), const SizedBox(width: 3),
        _k('D', frame.keys.d), const SizedBox(width: 6),
        _k('JUMP', frame.keys.jump), const SizedBox(width: 3),
        _k('DUCK', frame.keys.crouch),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: frame.onGround ? Colors.transparent : BiobaseColors.warning.withAlpha(20),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(frame.onGround ? 'GROUND' : 'AIR',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: frame.onGround ? BiobaseColors.textTertiary : BiobaseColors.warning, letterSpacing: 0.5)),
        ),
        const SizedBox(width: 8),
        Text('${frame.pitch.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
      ]),
    );
  }

  Widget _k(String label, bool on) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: on ? BiobaseColors.live : BiobaseColors.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: on ? Colors.white : BiobaseColors.textTertiary)),
    );
  }
}
