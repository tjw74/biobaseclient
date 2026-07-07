import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/radar_analytics.dart';
import '../theme.dart';

/// Role Performance Radar. Max two polygons: player (filled) + comparison
/// (dashed). Rings at 25/50/75 — the 50-ring is the benchmark median and is
/// emphasized. Vertex taps select the metric for the detail row/table.
class RadarChart extends StatelessWidget {
  final RadarProfile profile;
  final RadarProfile? comparison;
  final int? selectedAxis;
  final ValueChanged<int>? onAxisTap;
  final double size;
  final bool lowSample;

  const RadarChart({
    super.key,
    required this.profile,
    this.comparison,
    this.selectedAxis,
    this.onAxisTap,
    this.size = 320,
    this.lowSample = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onAxisTap == null
            ? null
            : (details) {
                final axis = _hitAxis(details.localPosition);
                if (axis != null) onAxisTap!(axis);
              },
        child: CustomPaint(
          painter: _RadarPainter(
            profile: profile,
            comparison: comparison,
            selectedAxis: selectedAxis,
            lowSample: lowSample,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  int? _hitAxis(Offset pos) {
    final center = Offset(size / 2, size / 2);
    final n = profile.axes.length;
    if (n == 0) return null;
    final v = pos - center;
    if (v.distance < 12) return null;
    var angle = math.atan2(v.dy, v.dx) + math.pi / 2; // axis 0 at top
    if (angle < 0) angle += 2 * math.pi;
    final idx = ((angle / (2 * math.pi)) * n).round() % n;
    return idx;
  }
}

class _RadarPainter extends CustomPainter {
  final RadarProfile profile;
  final RadarProfile? comparison;
  final int? selectedAxis;
  final bool lowSample;

  _RadarPainter({
    required this.profile,
    this.comparison,
    this.selectedAxis,
    required this.lowSample,
  });

  static const _labelPad = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = profile.axes.length;
    if (n < 3) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _labelPad;

    Offset point(int axis, double norm) {
      final angle = -math.pi / 2 + axis * 2 * math.pi / n;
      final r = radius * (norm / 100).clamp(0.0, 1.0);
      return center + Offset(math.cos(angle), math.sin(angle)) * r;
    }

    // Rings — 50 is the benchmark median, emphasized.
    for (final ring in [25.0, 50.0, 75.0, 100.0]) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring == 50 ? 1.0 : 0.6
        ..color = ring == 50
            ? BiobaseColors.textTertiary.withAlpha(110)
            : BiobaseColors.border;
      final path = Path();
      for (var i = 0; i <= n; i++) {
        final o = point(i % n, ring);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    // Axes + labels
    for (var i = 0; i < n; i++) {
      final edge = point(i, 100);
      final axisPaint = Paint()
        ..strokeWidth = i == selectedAxis ? 1.2 : 0.6
        ..color = i == selectedAxis
            ? BiobaseColors.accent.withAlpha(170)
            : BiobaseColors.border;
      canvas.drawLine(center, edge, axisPaint);

      final def = profile.axes[i].def;
      final label = TextPainter(
        text: TextSpan(
          text: def.shortLabel,
          style: TextStyle(
            fontSize: 8,
            fontWeight: i == selectedAxis ? FontWeight.w700 : FontWeight.w500,
            fontFamily: 'monospace',
            color: i == selectedAxis
                ? BiobaseColors.accent
                : def.styleAxis
                ? BiobaseColors.textTertiary
                : BiobaseColors.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final angle = -math.pi / 2 + i * 2 * math.pi / n;
      final labelCenter =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (radius + 14);
      label.paint(
        canvas,
        labelCenter - Offset(label.width / 2, label.height / 2),
      );
    }

    // Comparison polygon first (under the player's).
    final comp = comparison;
    if (comp != null && comp.axes.length == n) {
      final path = _polygonPath(comp, point, n);
      canvas.drawPath(
        _dashPath(path, 4, 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = BiobaseColors.warning.withAlpha(220),
      );
    }

    // Player polygon
    final playerPath = _polygonPath(profile, point, n);
    canvas.drawPath(
      playerPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = BiobaseColors.accent.withAlpha(45),
    );
    canvas.drawPath(
      lowSample ? _dashPath(playerPath, 5, 4) : playerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = BiobaseColors.accent,
    );

    // Vertices
    for (var i = 0; i < n; i++) {
      final o = point(i, profile.axes[i].normalized);
      canvas.drawCircle(
        o,
        i == selectedAxis ? 3.2 : 2.2,
        Paint()..color = BiobaseColors.accent,
      );
    }
  }

  Path _polygonPath(
    RadarProfile p,
    Offset Function(int, double) point,
    int n,
  ) {
    final path = Path();
    for (var i = 0; i < n; i++) {
      final o = point(i, p.axes[i].normalized);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    path.close();
    return path;
  }

  Path _dashPath(Path source, double dash, double gap) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        result.addPath(
          metric.extractPath(distance, end),
          Offset.zero,
        );
        distance = end + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.profile != profile ||
      old.comparison != comparison ||
      old.selectedAxis != selectedAxis ||
      old.lowSample != lowSample;
}
