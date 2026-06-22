import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

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
      padding: const EdgeInsets.all(0),
      children: [
        _SpeedPanel(frame: frame, live: live, history: history),
        const SizedBox(height: 8),
        _VelocityTracePanel(history: history, frame: frame),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _KeysAndStatePanel(frame: frame)),
            const SizedBox(width: 8),
            Expanded(child: _MovementRadarPanel(history: history)),
          ],
        ),
        const SizedBox(height: 8),
        _BhopPanel(frame: frame),
      ],
    );
  }
}

// ── Speed panel with real-time trace ──

class _SpeedPanel extends StatelessWidget {
  final LiveFrame frame;
  final bool live;
  final List<LiveMovementSample> history;

  const _SpeedPanel(
      {required this.frame, required this.live, required this.history});

  String _speedGrade(int speed) {
    if (speed >= 250) return 'MAX';
    if (speed >= 220) return 'FAST';
    if (speed >= 150) return 'RUN';
    if (speed >= 80) return 'WALK';
    if (speed > 5) return 'CREEP';
    return 'STILL';
  }

  Color _speedColor(int speed) {
    if (speed >= 250) return BiobaseColors.live;
    if (speed >= 220) return BiobaseColors.accent;
    if (speed >= 150) return BiobaseColors.text;
    return BiobaseColors.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    final grade = _speedGrade(frame.speed);
    final speedPct = (frame.speed / 250).clamp(0.0, 1.0);
    final speeds = history.map((s) => s.speed).toList();
    final grounds = history.map((s) => s.onGround).toList();

    return Panel(
      title: 'Speed',
      badge: StatusBadge(status: live ? StatusLevel.live : StatusLevel.offline),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${frame.speed}',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  color: _speedColor(frame.speed),
                  letterSpacing: -2,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('u/s',
                    style: TextStyle(
                        fontSize: 13, color: BiobaseColors.textTertiary)),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _speedColor(frame.speed).withAlpha(26),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(grade,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _speedColor(frame.speed),
                        letterSpacing: 0.5,
                      )),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${frame.yaw.toStringAsFixed(1)}° yaw',
                    style: TextStyle(
                        fontSize: 12, color: BiobaseColors.textTertiary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: speedPct,
              minHeight: 4,
              backgroundColor: BiobaseColors.surfaceRaised,
              valueColor: AlwaysStoppedAnimation(_speedColor(frame.speed)),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 100,
              color: BiobaseColors.bg,
              child: CustomPaint(
                size: const Size(double.infinity, 100),
                painter:
                    _SpeedTracePainter(speeds: speeds, onGround: grounds),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('60s ago',
                  style: TextStyle(
                      fontSize: 9, color: BiobaseColors.textTertiary)),
              Text('SPEED TRACE',
                  style: TextStyle(
                      fontSize: 9,
                      color: BiobaseColors.textTertiary,
                      letterSpacing: 0.5)),
              Text('now',
                  style: TextStyle(
                      fontSize: 9, color: BiobaseColors.textTertiary)),
            ],
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
    const regionHeight = 3.0;

    final gridPaint = Paint()
      ..color = BiobaseColors.surfaceRaised
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final thresholdY = size.height * (1 - 250 / maxSpeed);
    final dashPaint = Paint()
      ..color = BiobaseColors.accent.withAlpha(40)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, thresholdY),
          Offset(min(x + 3, size.width), thresholdY), dashPaint);
    }

    if (speeds.isEmpty) return;

    final n = speeds.length;
    final div = max(1, n - 1).toDouble();

    for (int i = 0; i < n && i < onGround.length; i++) {
      final x = (i / div) * size.width;
      final nextX = ((i + 1) / div) * size.width;
      canvas.drawRect(
        Rect.fromLTWH(
            x, size.height - regionHeight, nextX - x, regionHeight),
        Paint()
          ..color = onGround[i]
              ? BiobaseColors.textTertiary.withAlpha(30)
              : BiobaseColors.warning.withAlpha(50),
      );
    }

    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < n; i++) {
      final x = (i / div) * size.width;
      final y = size.height -
          (speeds[i] / maxSpeed).clamp(0.0, 1.0) *
              (size.height - regionHeight);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height - regionHeight);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(((n - 1) / div) * size.width, size.height - regionHeight);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BiobaseColors.accent.withAlpha(35),
            BiobaseColors.accent.withAlpha(5),
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

    final lastX = ((n - 1) / div) * size.width;
    final lastY = size.height -
        (speeds.last / maxSpeed).clamp(0.0, 1.0) *
            (size.height - regionHeight);
    canvas.drawCircle(Offset(lastX, lastY), 4,
        Paint()..color = BiobaseColors.accent.withAlpha(60));
    canvas.drawCircle(
        Offset(lastX, lastY), 2, Paint()..color = BiobaseColors.accent);
  }

  @override
  bool shouldRepaint(covariant _SpeedTracePainter old) =>
      speeds.length != old.speeds.length;
}

// ── Velocity trace ──

class _VelocityTracePanel extends StatelessWidget {
  final List<LiveMovementSample> history;
  final LiveFrame frame;

  const _VelocityTracePanel({required this.history, required this.frame});

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Velocity',
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 80,
              color: BiobaseColors.bg,
              child: CustomPaint(
                size: const Size(double.infinity, 80),
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
              _velLegend(
                  'X', const Color(0xFF3B82F6),
                  frame.vel.isNotEmpty ? frame.vel[0] : 0),
              const SizedBox(width: 16),
              _velLegend(
                  'Y', const Color(0xFF10B981),
                  frame.vel.length > 1 ? frame.vel[1] : 0),
              const SizedBox(width: 16),
              _velLegend(
                  'Z', const Color(0xFFF59E0B),
                  frame.vel.length > 2 ? frame.vel[2] : 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _velLegend(String axis, Color color, double val) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 2, color: color),
        const SizedBox(width: 4),
        Text('$axis ',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        Text(val.toStringAsFixed(1),
            style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: BiobaseColors.text)),
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
    final gridPaint = Paint()
      ..color = BiobaseColors.surfaceRaised
      ..strokeWidth = 0.5;

    canvas.drawLine(Offset(0, size.height / 2),
        Offset(size.width, size.height / 2), gridPaint);
    for (final f in [0.25, 0.75]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (velX.isEmpty) return;

    double maxVal = 1;
    for (final list in [velX, velY, velZ]) {
      for (final v in list) {
        if (v.abs() > maxVal) maxVal = v.abs();
      }
    }
    maxVal *= 1.1;

    void drawTrace(List<double> vals, Color color) {
      if (vals.isEmpty) return;
      final path = Path();
      final div = max(1, vals.length - 1).toDouble();
      for (int i = 0; i < vals.length; i++) {
        final x = (i / div) * size.width;
        final y = size.height / 2 - (vals[i] / maxVal) * (size.height / 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round);
    }

    drawTrace(velX, const Color(0xFF3B82F6));
    drawTrace(velY, const Color(0xFF10B981));
    drawTrace(velZ, const Color(0xFFF59E0B));
  }

  @override
  bool shouldRepaint(covariant _VelocityTracePainter old) =>
      velX.length != old.velX.length;
}

// ── Movement quality radar ──

class _MovementRadarPanel extends StatelessWidget {
  final List<LiveMovementSample> history;

  const _MovementRadarPanel({required this.history});

  List<double> _compute() {
    if (history.length < 2) return [0, 0, 0, 0, 0];

    final speeds = history.map((s) => s.speed).toList();
    final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
    final avgCS =
        history.map((s) => s.counterStrafeScore).reduce((a, b) => a + b) /
            history.length;
    final avgPE =
        history.map((s) => s.pathEfficiency).reduce((a, b) => a + b) /
            history.length;

    final air = history.where((s) => !s.onGround);
    final airCtrl = air.isNotEmpty
        ? air.where((s) => s.speed > 200).length / air.length
        : 0.0;

    double consistency = 0;
    if (avgSpeed > 0) {
      final variance = speeds
              .map((s) => (s - avgSpeed) * (s - avgSpeed))
              .reduce((a, b) => a + b) /
          speeds.length;
      consistency = (1 - sqrt(variance) / avgSpeed).clamp(0.0, 1.0);
    }

    return [
      (avgSpeed / 250).clamp(0.0, 1.0),
      avgCS.clamp(0.0, 1.0),
      avgPE.clamp(0.0, 1.0),
      airCtrl.clamp(0.0, 1.0),
      consistency,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Movement Quality',
      child: SizedBox(
        height: 160,
        child: CustomPaint(
          size: const Size(double.infinity, 160),
          painter: _RadarPainter(
            values: _compute(),
            labels: const ['Speed', 'Strafe', 'Path', 'Air Ctrl', 'Consist.'],
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
    final radius = min(size.width, size.height) / 2 - 24;
    final axes = values.length;

    for (int ring = 1; ring <= 3; ring++) {
      final r = radius * (ring / 3);
      final webPath = Path();
      for (int i = 0; i <= axes; i++) {
        final a = -pi / 2 + (2 * pi / axes) * (i % axes);
        final pt =
            Offset(center.dx + r * cos(a), center.dy + r * sin(a));
        if (i == 0) {
          webPath.moveTo(pt.dx, pt.dy);
        } else {
          webPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
          webPath,
          Paint()
            ..color = BiobaseColors.surfaceRaised
            ..strokeWidth = 0.5
            ..style = PaintingStyle.stroke);
    }

    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      canvas.drawLine(
          center,
          Offset(
              center.dx + radius * cos(a), center.dy + radius * sin(a)),
          Paint()
            ..color = BiobaseColors.surfaceRaised
            ..strokeWidth = 0.5);
    }

    final dataPath = Path();
    for (int i = 0; i <= axes; i++) {
      final idx = i % axes;
      final a = -pi / 2 + (2 * pi / axes) * idx;
      final r = radius * values[idx].clamp(0.0, 1.0);
      final pt =
          Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      if (i == 0) {
        dataPath.moveTo(pt.dx, pt.dy);
      } else {
        dataPath.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
        dataPath, Paint()..color = BiobaseColors.accent.withAlpha(40));
    canvas.drawPath(
        dataPath,
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
          2.5,
          Paint()..color = BiobaseColors.accent);
    }

    for (int i = 0; i < axes; i++) {
      final a = -pi / 2 + (2 * pi / axes) * i;
      final lr = radius + 14;
      final pt =
          Offset(center.dx + lr * cos(a), center.dy + lr * sin(a));
      final tp = TextPainter(
        text: TextSpan(
            text: labels[i],
            style: const TextStyle(
                fontSize: 9, color: BiobaseColors.textTertiary)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(pt.dx - tp.width / 2, pt.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}

// ── Input & state ──

class _KeysAndStatePanel extends StatelessWidget {
  final LiveFrame frame;

  const _KeysAndStatePanel({required this.frame});

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Input & State',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              KeyIndicator(label: 'W', active: frame.keys.w),
              KeyIndicator(label: 'A', active: frame.keys.a),
              KeyIndicator(label: 'S', active: frame.keys.s),
              KeyIndicator(label: 'D', active: frame.keys.d),
              KeyIndicator(label: 'JUMP', active: frame.keys.jump),
              KeyIndicator(label: 'DUCK', active: frame.keys.crouch),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip(
                frame.onGround ? 'GROUNDED' : 'AIRBORNE',
                frame.onGround
                    ? BiobaseColors.textTertiary
                    : BiobaseColors.warning,
                !frame.onGround,
              ),
              const SizedBox(width: 6),
              _chip(
                '${frame.pitch.toStringAsFixed(1)}° pitch',
                BiobaseColors.textTertiary,
                false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(active ? 26 : 13),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.3)),
    );
  }
}

// ── Bhop analysis ──

class _BhopPanel extends StatelessWidget {
  final LiveFrame frame;

  const _BhopPanel({required this.frame});

  @override
  Widget build(BuildContext context) {
    final bhopReady = !frame.onGround && frame.speed > 200;
    final perfectBhop = !frame.onGround && frame.speed >= 250;

    return Panel(
      title: 'Bhop Analysis',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: StatCell(
                      label: 'air speed',
                      value: frame.isAirborne ? '${frame.speed}' : '—',
                      accent: bhopReady)),
              const SizedBox(width: 6),
              Expanded(
                  child: StatCell(
                      label: 'vertical vel',
                      value: frame.velZ.toStringAsFixed(1),
                      accent: frame.velZ > 200)),
              const SizedBox(width: 6),
              Expanded(
                  child: StatCell(
                      label: 'state',
                      value: frame.isAirborne
                          ? (perfectBhop ? 'PERFECT' : 'AIR')
                          : 'GROUND')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _mini('Counter-strafe',
                  frame.counterStrafeScore.toStringAsFixed(2)),
              const SizedBox(width: 16),
              _mini('Path efficiency',
                  frame.pathEfficiency.toStringAsFixed(2)),
              const SizedBox(width: 16),
              _mini('Tick', '${frame.tick}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.text)),
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 9,
                color: BiobaseColors.textTertiary,
                letterSpacing: 0.3)),
      ],
    );
  }
}
