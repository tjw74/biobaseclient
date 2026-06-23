import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../models/session_stats.dart';
import '../theme.dart';

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
        _SpeedHero(frame: frame, live: live, history: history),
        const SizedBox(height: 4),
        _SessionStrip(stats: sessionStats),
        const SizedBox(height: 6),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  flex: 3,
                  child: _VelocityChart(history: history, frame: frame)),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: _RadarChart(history: history)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _StateTimeline(history: history),
        const SizedBox(height: 8),
        _InputRow(frame: frame),
      ],
    );
  }
}

// ── Speed Hero ──

class _SpeedHero extends StatelessWidget {
  final LiveFrame frame;
  final bool live;
  final List<LiveMovementSample> history;

  const _SpeedHero({
    required this.frame,
    required this.live,
    required this.history,
  });

  String _grade(int s) {
    if (s >= 250) return 'MAX';
    if (s >= 220) return 'FAST';
    if (s >= 150) return 'RUN';
    if (s >= 80) return 'WALK';
    if (s > 5) return 'CREEP';
    return 'STILL';
  }

  Color _color(int s) {
    if (s >= 250) return BiobaseColors.live;
    if (s >= 220) return BiobaseColors.accent;
    if (s >= 150) return BiobaseColors.text;
    return BiobaseColors.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(frame.speed);
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${frame.speed}',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: c,
                  letterSpacing: -3,
                  height: 1,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_grade(frame.speed),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c,
                        letterSpacing: 0.5,
                      )),
                ),
              ),
              const Spacer(),
              if (live)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: BiobaseColors.live,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: BiobaseColors.live.withAlpha(100),
                            blurRadius: 6),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: (frame.speed / 250).clamp(0.0, 1.0),
                backgroundColor: BiobaseColors.surfaceRaised,
                valueColor: AlwaysStoppedAnimation(c.withAlpha(100)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 130,
              child: CustomPaint(
                size: const Size(double.infinity, 130),
                painter: _SpeedTracePainter(
                  speeds: history.map((s) => s.speed).toList(),
                  onGround: history.map((s) => s.onGround).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
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

    // Threshold reference lines
    for (final (val, color, label) in [
      (250.0, BiobaseColors.live, 'MAX'),
      (150.0, BiobaseColors.textTertiary, 'RUN'),
    ]) {
      final y = chartH - (val / maxSpeed).clamp(0.0, 1.0) * chartH;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = color.withAlpha(20)
          ..strokeWidth = 0.5,
      );
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                fontSize: 7,
                color: color.withAlpha(35),
                letterSpacing: 0.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, y - tp.height - 1));
    }

    // Subtle grid
    for (int i = 1; i < 4; i++) {
      final y = chartH * (i / 4);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = BiobaseColors.surfaceRaised.withAlpha(50)
          ..strokeWidth = 0.5,
      );
    }

    if (speeds.isEmpty) return;
    final n = speeds.length;
    final d = max(1, n - 1).toDouble();

    // Ground/air bar
    for (int i = 0; i < n && i < onGround.length; i++) {
      final x = (i / d) * size.width;
      final nx = ((i + 1) / d) * size.width;
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - barH, nx - x, barH),
        Paint()
          ..color = onGround[i]
              ? BiobaseColors.textTertiary.withAlpha(15)
              : BiobaseColors.warning.withAlpha(40),
      );
    }

    // Speed line + fill
    final path = Path();
    final fill = Path();
    for (int i = 0; i < n; i++) {
      final x = (i / d) * size.width;
      final y = chartH - (speeds[i] / maxSpeed).clamp(0.0, 1.0) * chartH;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, chartH);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(((n - 1) / d) * size.width, chartH);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BiobaseColors.accent.withAlpha(35),
            BiobaseColors.accent.withAlpha(2),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, chartH)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = BiobaseColors.accent
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // End dot
    final lx = ((n - 1) / d) * size.width;
    final ly = chartH - (speeds.last / maxSpeed).clamp(0.0, 1.0) * chartH;
    canvas.drawCircle(
        Offset(lx, ly), 3, Paint()..color = BiobaseColors.accent.withAlpha(40));
    canvas.drawCircle(
        Offset(lx, ly), 1.5, Paint()..color = BiobaseColors.accent);
  }

  @override
  bool shouldRepaint(covariant _SpeedTracePainter old) =>
      speeds.length != old.speeds.length;
}

// ── Session Stats Strip ──

class _SessionStrip extends StatelessWidget {
  final SessionStats stats;

  const _SessionStrip({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _s('MAX', '${stats.speedMax.toInt()}'),
          _div(),
          _s('AVG', '${stats.speedAvgSafe.toInt()}'),
          _div(),
          _s('JUMPS', '${stats.jumpCount}'),
          _div(),
          _s('BHOP', '${stats.consecutiveBhopsMax}'),
          _div(),
          _s('SYNC', '${stats.strafeSyncPercent.toInt()}%'),
          _div(),
          _s('DIST', _fd(stats.distanceTraveled)),
          _div(),
          _s('AIR', '${stats.airTimePercent.toInt()}%'),
        ],
      ),
    );
  }

  Widget _s(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                  fontFamily: 'monospace',
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 8,
                  color: BiobaseColors.textTertiary,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _div() {
    return Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: BiobaseColors.borderSubtle);
  }

  String _fd(double d) {
    if (d >= 10000) return '${(d / 1000).toStringAsFixed(0)}k';
    if (d >= 1000) return '${(d / 1000).toStringAsFixed(1)}k';
    return d.toInt().toString();
  }
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
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _leg(const Color(0xFF3B82F6), 'X', _fv(0)),
              const SizedBox(width: 14),
              _leg(const Color(0xFF10B981), 'Y', _fv(1)),
              const SizedBox(width: 14),
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
        ],
      ),
    );
  }

  String _fv(int i) =>
      (frame.vel.length > i ? frame.vel[i] : 0.0).toStringAsFixed(0);

  Widget _leg(Color c, String axis, String val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 2,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 4),
        Text(val,
            style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: BiobaseColors.textTertiary)),
      ],
    );
  }
}

class _VelocityTracePainter extends CustomPainter {
  final List<double> velX, velY, velZ;

  _VelocityTracePainter(
      {required this.velX, required this.velY, required this.velZ});

  @override
  void paint(Canvas canvas, Size size) {
    // Zero line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = BiobaseColors.surfaceRaised.withAlpha(60)
        ..strokeWidth = 0.5,
    );

    if (velX.isEmpty) return;

    double mx = 1;
    for (final l in [velX, velY, velZ]) {
      for (final v in l) {
        if (v.abs() > mx) mx = v.abs();
      }
    }
    mx *= 1.1;

    void trace(List<double> v, Color c) {
      if (v.isEmpty) return;
      final p = Path();
      final d = max(1, v.length - 1).toDouble();
      for (int i = 0; i < v.length; i++) {
        final x = (i / d) * size.width;
        final y = size.height / 2 - (v[i] / mx) * (size.height / 2);
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = c
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round);
    }

    trace(velX, const Color(0xFF3B82F6));
    trace(velY, const Color(0xFF10B981));
    trace(velZ, const Color(0xFFF59E0B));
  }

  @override
  bool shouldRepaint(covariant _VelocityTracePainter old) =>
      velX.length != old.velX.length;
}

// ── Radar Chart ──

class _RadarChart extends StatelessWidget {
  final List<LiveMovementSample> history;

  const _RadarChart({required this.history});

  List<double> _compute() {
    if (history.length < 2) return [0, 0, 0, 0, 0];
    final speeds = history.map((s) => s.speed).toList();
    final avg = speeds.reduce((a, b) => a + b) / speeds.length;
    final cs =
        history.map((s) => s.counterStrafeScore).reduce((a, b) => a + b) /
            history.length;
    final pe =
        history.map((s) => s.pathEfficiency).reduce((a, b) => a + b) /
            history.length;
    final air = history.where((s) => !s.onGround);
    final ac = air.isNotEmpty
        ? air.where((s) => s.speed > 200).length / air.length
        : 0.0;
    double con = 0;
    if (avg > 0) {
      final v =
          speeds.map((s) => (s - avg) * (s - avg)).reduce((a, b) => a + b) /
              speeds.length;
      con = (1 - sqrt(v) / avg).clamp(0.0, 1.0);
    }
    return [
      (avg / 250).clamp(0.0, 1.0),
      cs.clamp(0.0, 1.0),
      pe.clamp(0.0, 1.0),
      ac.clamp(0.0, 1.0),
      con,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(14),
      child: CustomPaint(
        size: const Size(double.infinity, double.infinity),
        painter: _RadarPainter(
          values: _compute(),
          labels: const ['Speed', 'Strafe', 'Path', 'Air', 'Consist.'],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  _RadarPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 22;
    final axes = values.length;

    // Ring grid
    for (int ring = 1; ring <= 3; ring++) {
      final r = radius * (ring / 3);
      final p = Path();
      for (int i = 0; i <= axes; i++) {
        final a = -pi / 2 + (2 * pi / axes) * (i % axes);
        final pt = Offset(center.dx + r * cos(a), center.dy + r * sin(a));
        if (i == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
          p,
          Paint()
            ..color =
                BiobaseColors.surfaceRaised.withAlpha(ring == 3 ? 80 : 40)
            ..strokeWidth = 0.5
            ..style = PaintingStyle.stroke);
    }

    // Spokes
    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      canvas.drawLine(
          center,
          Offset(
              center.dx + radius * cos(a), center.dy + radius * sin(a)),
          Paint()
            ..color = BiobaseColors.surfaceRaised.withAlpha(40)
            ..strokeWidth = 0.5);
    }

    // Data polygon
    final dp = Path();
    for (int i = 0; i <= axes; i++) {
      final idx = i % axes;
      final a = -pi / 2 + (2 * pi / axes) * idx;
      final r = radius * values[idx].clamp(0.0, 1.0);
      final pt = Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      if (i == 0) {
        dp.moveTo(pt.dx, pt.dy);
      } else {
        dp.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(dp, Paint()..color = BiobaseColors.accent.withAlpha(25));
    canvas.drawPath(
        dp,
        Paint()
          ..color = BiobaseColors.accent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);

    // Dots
    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      final r = radius * values[i].clamp(0.0, 1.0);
      canvas.drawCircle(
          Offset(center.dx + r * cos(a), center.dy + r * sin(a)),
          2,
          Paint()..color = BiobaseColors.accent);
    }

    // Labels with values
    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      final lr = radius + 14;
      final pt =
          Offset(center.dx + lr * cos(a), center.dy + lr * sin(a));
      final pct = (values[i] * 100).toInt();
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: labels[i],
              style: TextStyle(
                  fontSize: 8,
                  color: BiobaseColors.textTertiary.withAlpha(160),
                  letterSpacing: 0.3)),
          TextSpan(
              text: ' $pct',
              style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.textTertiary.withAlpha(200))),
        ]),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas, Offset(pt.dx - tp.width / 2, pt.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
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
          painter: _StateTimelinePainter(
            states: history.map((s) => s.onGround).toList(),
          ),
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
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = BiobaseColors.surfaceRaised.withAlpha(40),
      );
      return;
    }
    final n = states.length;
    final w = size.width / n;
    for (int i = 0; i < n; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * w, 0, w + 0.5, size.height),
        Paint()
          ..color = states[i]
              ? BiobaseColors.surfaceRaised.withAlpha(40)
              : BiobaseColors.warning.withAlpha(50),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StateTimelinePainter old) =>
      states.length != old.states.length;
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
              color: frame.onGround
                  ? Colors.transparent
                  : BiobaseColors.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              frame.onGround ? 'GROUND' : 'AIR',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: frame.onGround
                    ? BiobaseColors.textTertiary
                    : BiobaseColors.warning,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${frame.pitch.toStringAsFixed(0)}°',
              style: const TextStyle(
                  fontSize: 11, color: BiobaseColors.textTertiary)),
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
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: on ? Colors.white : BiobaseColors.textTertiary,
        ),
      ),
    );
  }
}
