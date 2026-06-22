import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';

class LiveScreen extends StatelessWidget {
  final LiveFrame frame;
  final bool live;
  final List<LiveMovementSample> history;

  const LiveScreen({
    super.key,
    required this.frame,
    this.live = false,
    this.history = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SpeedSection(frame: frame, live: live, history: history),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _VelocitySection(history: history, frame: frame)),
            const SizedBox(width: 8),
            Expanded(child: _RadarSection(history: history)),
          ],
        ),
        const SizedBox(height: 12),
        _InputRow(frame: frame),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

// ── Speed ──

class _SpeedSection extends StatelessWidget {
  final LiveFrame frame;
  final bool live;
  final List<LiveMovementSample> history;

  const _SpeedSection({
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
    final speeds = history.map((s) => s.speed).toList();
    final grounds = history.map((s) => s.onGround).toList();

    return _Card(
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
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
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: (frame.speed / 250).clamp(0.0, 1.0),
                backgroundColor: BiobaseColors.surfaceRaised,
                valueColor: AlwaysStoppedAnimation(c.withAlpha(120)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _SpeedTracePainter(
                    speeds: speeds, onGround: grounds),
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

    final grid = Paint()
      ..color = BiobaseColors.surfaceRaised.withAlpha(80)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (speeds.isEmpty) return;
    final n = speeds.length;
    final d = max(1, n - 1).toDouble();

    for (int i = 0; i < n && i < onGround.length; i++) {
      final x = (i / d) * size.width;
      final nx = ((i + 1) / d) * size.width;
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - barH, nx - x, barH),
        Paint()
          ..color = onGround[i]
              ? BiobaseColors.textTertiary.withAlpha(20)
              : BiobaseColors.warning.withAlpha(40),
      );
    }

    final path = Path();
    final fill = Path();
    for (int i = 0; i < n; i++) {
      final x = (i / d) * size.width;
      final y = size.height -
          (speeds[i] / maxSpeed).clamp(0.0, 1.0) *
              (size.height - barH);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height - barH);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(((n - 1) / d) * size.width, size.height - barH);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BiobaseColors.accent.withAlpha(30),
            BiobaseColors.accent.withAlpha(3),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
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

    final lx = ((n - 1) / d) * size.width;
    final ly = size.height -
        (speeds.last / maxSpeed).clamp(0.0, 1.0) *
            (size.height - barH);
    canvas.drawCircle(Offset(lx, ly), 3,
        Paint()..color = BiobaseColors.accent.withAlpha(50));
    canvas.drawCircle(
        Offset(lx, ly), 1.5, Paint()..color = BiobaseColors.accent);
  }

  @override
  bool shouldRepaint(covariant _SpeedTracePainter old) =>
      speeds.length != old.speeds.length;
}

// ── Velocity ──

class _VelocitySection extends StatelessWidget {
  final List<LiveMovementSample> history;
  final LiveFrame frame;

  const _VelocitySection({required this.history, required this.frame});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 100,
              child: CustomPaint(
                size: const Size(double.infinity, 100),
                painter: _VelocityTracePainter(
                  velX: history.map((s) => s.velX).toList(),
                  velY: history.map((s) => s.velY).toList(),
                  velZ: history.map((s) => s.velZ).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _leg(const Color(0xFF3B82F6), _fv(0)),
              const SizedBox(width: 12),
              _leg(const Color(0xFF10B981), _fv(1)),
              const SizedBox(width: 12),
              _leg(const Color(0xFFF59E0B), _fv(2)),
            ],
          ),
        ],
      ),
    );
  }

  String _fv(int i) =>
      (frame.vel.length > i ? frame.vel[i] : 0.0).toStringAsFixed(0);

  Widget _leg(Color c, String val) {
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
    final grid = Paint()
      ..color = BiobaseColors.surfaceRaised.withAlpha(80)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, size.height / 2),
        Offset(size.width, size.height / 2), grid);

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

// ── Radar ──

class _RadarSection extends StatelessWidget {
  final List<LiveMovementSample> history;

  const _RadarSection({required this.history});

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
    return _Card(
      child: SizedBox(
        height: 168,
        child: CustomPaint(
          size: const Size(double.infinity, 168),
          painter: _RadarPainter(
            values: _compute(),
            labels: const ['Speed', 'Strafe', 'Path', 'Air', 'Consist.'],
          ),
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
    final radius = min(size.width, size.height) / 2 - 20;
    final axes = values.length;

    for (int ring = 1; ring <= 3; ring++) {
      final r = radius * (ring / 3);
      final p = Path();
      for (int i = 0; i <= axes; i++) {
        final a = -pi / 2 + (2 * pi / axes) * (i % axes);
        final pt =
            Offset(center.dx + r * cos(a), center.dy + r * sin(a));
        if (i == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = BiobaseColors.surfaceRaised
                .withAlpha(ring == 3 ? 100 : 60)
            ..strokeWidth = 0.5
            ..style = PaintingStyle.stroke);
    }

    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      canvas.drawLine(
          center,
          Offset(center.dx + radius * cos(a),
              center.dy + radius * sin(a)),
          Paint()
            ..color = BiobaseColors.surfaceRaised.withAlpha(60)
            ..strokeWidth = 0.5);
    }

    final dp = Path();
    for (int i = 0; i <= axes; i++) {
      final idx = i % axes;
      final a = -pi / 2 + (2 * pi / axes) * idx;
      final r = radius * values[idx].clamp(0.0, 1.0);
      final pt =
          Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      if (i == 0) {
        dp.moveTo(pt.dx, pt.dy);
      } else {
        dp.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
        dp, Paint()..color = BiobaseColors.accent.withAlpha(30));
    canvas.drawPath(
        dp,
        Paint()
          ..color = BiobaseColors.accent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);

    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      final r = radius * values[i].clamp(0.0, 1.0);
      canvas.drawCircle(
          Offset(center.dx + r * cos(a), center.dy + r * sin(a)),
          2,
          Paint()..color = BiobaseColors.accent);
    }

    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      final lr = radius + 12;
      final pt = Offset(
          center.dx + lr * cos(a), center.dy + lr * sin(a));
      final tp = TextPainter(
        text: TextSpan(
            text: labels[i],
            style: TextStyle(
                fontSize: 8,
                color: BiobaseColors.textTertiary.withAlpha(180),
                letterSpacing: 0.3)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(pt.dx - tp.width / 2, pt.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}

// ── Input row ──

class _InputRow extends StatelessWidget {
  final LiveFrame frame;

  const _InputRow({required this.frame});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
