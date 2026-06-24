import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../models/session_stats.dart';
import '../theme.dart';

const _kGreen = BiobaseColors.live;
const _kBlue = BiobaseColors.accent;
const _kAmber = BiobaseColors.warning;
const _kPurple = Color(0xFF8B5CF6);

class LiveScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SessionInfo(frame: frame, stats: sessionStats),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _MetricCard(
              dotColor: _kGreen,
              label: 'SPEED',
              value: '${frame.speed}',
              description: 'units per second',
              progress: (frame.speed / 250).clamp(0.0, 1.0),
            )),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(
              dotColor: _kBlue,
              label: 'COUNTER-STRAFE',
              value: frame.counterStrafeScore.toStringAsFixed(2),
              description: 'deceleration accuracy',
              progress: frame.counterStrafeScore.clamp(0.0, 1.0),
            )),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(
              dotColor: _kAmber,
              label: 'PATH EFFICIENCY',
              value: frame.pathEfficiency.toStringAsFixed(2),
              description: 'optimal route adherence',
              progress: frame.pathEfficiency.clamp(0.0, 1.0),
            )),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(
              dotColor: _kPurple,
              label: 'STRAFE SYNC',
              value: '${sessionStats.strafeSyncPercent.toInt()}%',
              description: 'air strafe synchronization',
              progress: (sessionStats.strafeSyncPercent / 100).clamp(0.0, 1.0),
            )),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _SpeedChart(history: history, frame: frame, live: live)),
              const SizedBox(width: 12),
              Expanded(child: _VelocityChart(history: history, frame: frame)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StateTimeline(history: history),
        const SizedBox(height: 8),
        _InputRow(frame: frame),
      ],
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
          Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BiobaseColors.text, fontFamily: 'monospace', letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
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

  const _MetricCard({
    required this.dotColor,
    required this.label,
    required this.value,
    required this.description,
    required this.progress,
  });

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
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: BiobaseColors.text, letterSpacing: -1, height: 1)),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: BiobaseColors.surfaceRaised,
                valueColor: AlwaysStoppedAnimation(dotColor.withAlpha(160)),
              ),
            ),
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
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Speed History', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
                    const SizedBox(height: 2),
                    const Text('Movement speed over time', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
                  ],
                ),
              ),
              if (live)
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: BiobaseColors.live, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: BiobaseColors.live.withAlpha(100), blurRadius: 6)],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _leg(BiobaseColors.accent, 'Speed', '${frame.speed}'),
              const SizedBox(width: 16),
              _leg(BiobaseColors.live, 'Max', '250'),
              const SizedBox(width: 16),
              _leg(BiobaseColors.textTertiary, 'Run', '150'),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(
                size: const Size(double.infinity, double.infinity),
                painter: _SpeedTracePainter(
                  speeds: history.map((s) => s.speed).toList(),
                  onGround: history.map((s) => s.onGround).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('HISTORY', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
              Text('NOW', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leg(Color c, String label, String val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$label ', style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
        Text(val, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c, fontFamily: 'monospace')),
      ],
    );
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

    for (final (val, color) in [
      (250.0, BiobaseColors.live),
      (150.0, BiobaseColors.textTertiary),
    ]) {
      final y = chartH - (val / maxSpeed).clamp(0.0, 1.0) * chartH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
        Paint()..color = color.withAlpha(20)..strokeWidth = 0.5);
    }

    for (int i = 1; i < 4; i++) {
      final y = chartH * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
        Paint()..color = BiobaseColors.surfaceRaised.withAlpha(50)..strokeWidth = 0.5);
    }

    if (speeds.isEmpty) return;
    final n = speeds.length;
    final d = max(1, n - 1).toDouble();

    for (int i = 0; i < n && i < onGround.length; i++) {
      final x = (i / d) * size.width;
      final nx = ((i + 1) / d) * size.width;
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - barH, nx - x, barH),
        Paint()..color = onGround[i]
            ? BiobaseColors.textTertiary.withAlpha(15)
            : BiobaseColors.warning.withAlpha(40),
      );
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

    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [BiobaseColors.accent.withAlpha(35), BiobaseColors.accent.withAlpha(2)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartH)));
    canvas.drawPath(path, Paint()
      ..color = BiobaseColors.accent..strokeWidth = 1.5
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
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Velocity Components', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
          const SizedBox(height: 2),
          const Text('X / Y / Z axis decomposition', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
          const SizedBox(height: 12),
          Row(
            children: [
              _leg(const Color(0xFF3B82F6), 'X', _fv(0)),
              const SizedBox(width: 16),
              _leg(const Color(0xFF10B981), 'Y', _fv(1)),
              const SizedBox(width: 16),
              _leg(const Color(0xFFF59E0B), 'Z', _fv(2)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(
                size: const Size(double.infinity, double.infinity),
                painter: _VelocityTracePainter(
                  velX: history.map((s) => s.velX).toList(),
                  velY: history.map((s) => s.velY).toList(),
                  velZ: history.map((s) => s.velZ).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('HISTORY', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
              Text('NOW', style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary, letterSpacing: 0.5)),
            ],
          ),
        ],
      ),
    );
  }

  String _fv(int i) => (frame.vel.length > i ? frame.vel[i] : 0.0).toStringAsFixed(0);

  Widget _leg(Color c, String axis, String val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$axis ', style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
        Text(val, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c, fontFamily: 'monospace')),
      ],
    );
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
    for (final l in [velX, velY, velZ]) {
      for (final v in l) { if (v.abs() > mx) mx = v.abs(); }
    }
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: CustomPaint(
          size: const Size(double.infinity, 6),
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
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = BiobaseColors.surfaceRaised.withAlpha(40));
      return;
    }
    final n = states.length;
    final w = size.width / n;
    for (int i = 0; i < n; i++) {
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 0.5, size.height),
        Paint()..color = states[i]
            ? BiobaseColors.surfaceRaised.withAlpha(40)
            : BiobaseColors.warning.withAlpha(50));
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
      child: Row(
        children: [
          _k('W', frame.keys.w),
          const SizedBox(width: 3),
          _k('A', frame.keys.a),
          const SizedBox(width: 3),
          _k('S', frame.keys.s),
          const SizedBox(width: 3),
          _k('D', frame.keys.d),
          const SizedBox(width: 6),
          _k('JUMP', frame.keys.jump),
          const SizedBox(width: 3),
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
        ],
      ),
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
