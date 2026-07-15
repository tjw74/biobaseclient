import 'package:flutter/material.dart';

import '../theme.dart';

/// Thin, low-chrome charts per the Clarion doctrine. Every point carries a
/// demo tick so taps can jump the replay to the exact moment.
class ChartPoint {
  final double x; // seconds (or round index for bars)
  final double y;
  final int tick;

  const ChartPoint({required this.x, required this.y, required this.tick});
}

class MiniLineChart extends StatelessWidget {
  final List<ChartPoint> points;
  final double height;
  final Color color;
  final String? unit;
  final ValueChanged<ChartPoint>? onPointTap;
  final List<double>? markersX; // vertical reference lines (e.g. round starts)
  final (double, double, double)? benchmarkBand; // pro p25/p50/p75, y-units

  const MiniLineChart({
    super.key,
    required this.points,
    this.height = 88,
    this.color = BiobaseColors.accent,
    this.unit,
    this.onPointTap,
    this.markersX,
    this.benchmarkBand,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'No data',
            style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onPointTap == null
                ? null
                : (details) {
                    final p = _nearest(details.localPosition.dx,
                        constraints.maxWidth);
                    if (p != null) onPointTap!(p);
                  },
            child: CustomPaint(
              painter: _LinePainter(
                points: points,
                color: color,
                unit: unit,
                markersX: markersX,
                benchmarkBand: benchmarkBand,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }

  ChartPoint? _nearest(double dx, double width) {
    if (points.isEmpty || width <= 0) return null;
    final minX = points.first.x;
    final maxX = points.last.x;
    final span = (maxX - minX).abs() < 1e-9 ? 1 : maxX - minX;
    final x = minX + (dx / width) * span;
    ChartPoint best = points.first;
    var bestDist = (best.x - x).abs();
    for (final p in points) {
      final d = (p.x - x).abs();
      if (d < bestDist) {
        best = p;
        bestDist = d;
      }
    }
    return best;
  }
}

class _LinePainter extends CustomPainter {
  final List<ChartPoint> points;
  final Color color;
  final String? unit;
  final List<double>? markersX;
  final (double, double, double)? benchmarkBand;

  _LinePainter({
    required this.points,
    required this.color,
    this.unit,
    this.markersX,
    this.benchmarkBand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    final minX = points.first.x;
    final maxX = points.last.x;
    final spanX = (maxX - minX).abs() < 1e-9 ? 1.0 : maxX - minX;
    var maxY = 0.0;
    for (final p in points) {
      if (p.y > maxY) maxY = p.y;
    }
    final band = benchmarkBand;
    if (band != null && band.$3 > maxY) maxY = band.$3;
    if (maxY <= 0) maxY = 1;

    const topPad = 12.0;
    const bottomPad = 4.0;
    final plotH = size.height - topPad - bottomPad;

    double yOf(double v) =>
        topPad + plotH - (v / maxY).clamp(0.0, 1.0) * plotH;

    // Pro benchmark band: p25-p75 shading with the median line.
    if (band != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, yOf(band.$3), size.width, yOf(band.$1)),
        Paint()..color = BiobaseColors.live.withAlpha(20),
      );
      final medianPaint = Paint()
        ..color = BiobaseColors.live.withAlpha(110)
        ..strokeWidth = 0.8;
      canvas.drawLine(
        Offset(0, yOf(band.$2)),
        Offset(size.width, yOf(band.$2)),
        medianPaint,
      );
    }

    Offset toScreen(ChartPoint p) => Offset(
          (p.x - minX) / spanX * size.width,
          topPad + plotH - (p.y / maxY).clamp(0.0, 1.0) * plotH,
        );

    // Round markers
    if (markersX != null) {
      final markerPaint = Paint()
        ..color = BiobaseColors.border
        ..strokeWidth = 0.6;
      for (final mx in markersX!) {
        final x = (mx - minX) / spanX * size.width;
        if (x < 0 || x > size.width) continue;
        canvas.drawLine(
          Offset(x, topPad),
          Offset(x, size.height - bottomPad),
          markerPaint,
        );
      }
    }

    // Baseline grid: max + mid
    final gridPaint = Paint()
      ..color = BiobaseColors.borderSubtle
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(0, topPad), Offset(size.width, topPad), gridPaint);
    canvas.drawLine(
      Offset(0, topPad + plotH / 2),
      Offset(size.width, topPad + plotH / 2),
      gridPaint,
    );

    final path = Path();
    var started = false;
    for (final p in points) {
      final o = toScreen(p);
      if (!started) {
        path.moveTo(o.dx, o.dy);
        started = true;
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color,
    );

    final label = TextPainter(
      text: TextSpan(
        text: '${maxY.round()}${unit ?? ''}',
        style: const TextStyle(
          fontSize: 8,
          fontFamily: 'monospace',
          color: BiobaseColors.textTertiary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(2, 0));
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.points != points ||
      old.color != color ||
      old.benchmarkBand != benchmarkBand;
}

class MiniBarChart extends StatelessWidget {
  final List<ChartPoint> bars;
  final double height;
  final Color color;
  final Color? secondaryColor;
  final List<ChartPoint>? secondaryBars; // drawn side-by-side (e.g. deaths)
  final ValueChanged<ChartPoint>? onBarTap;
  final (double, double, double)? benchmarkBand; // pro p25/p50/p75, y-units

  const MiniBarChart({
    super.key,
    required this.bars,
    this.height = 72,
    this.color = BiobaseColors.accent,
    this.secondaryColor,
    this.secondaryBars,
    this.onBarTap,
    this.benchmarkBand,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'No data',
            style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onBarTap == null
                ? null
                : (details) {
                    final i =
                        (details.localPosition.dx / constraints.maxWidth *
                                bars.length)
                            .floor()
                            .clamp(0, bars.length - 1);
                    onBarTap!(bars[i]);
                  },
            child: CustomPaint(
              painter: _BarPainter(
                bars: bars,
                secondaryBars: secondaryBars,
                color: color,
                secondaryColor: secondaryColor ?? BiobaseColors.error,
                benchmarkBand: benchmarkBand,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<ChartPoint> bars;
  final List<ChartPoint>? secondaryBars;
  final Color color;
  final Color secondaryColor;
  final (double, double, double)? benchmarkBand;

  _BarPainter({
    required this.bars,
    required this.color,
    required this.secondaryColor,
    this.secondaryBars,
    this.benchmarkBand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0) return;
    var maxY = 0.0;
    for (final b in bars) {
      if (b.y > maxY) maxY = b.y;
    }
    if (secondaryBars != null) {
      for (final b in secondaryBars!) {
        if (b.y > maxY) maxY = b.y;
      }
    }
    final band = benchmarkBand;
    if (band != null && band.$3 > maxY) maxY = band.$3;
    if (maxY <= 0) maxY = 1;

    const topPad = 12.0;
    const labelH = 12.0;
    final plotH = size.height - topPad - labelH;

    double yOf(double v) =>
        topPad + plotH - (v / maxY).clamp(0.0, 1.0) * plotH;

    if (band != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, yOf(band.$3), size.width, yOf(band.$1)),
        Paint()..color = BiobaseColors.live.withAlpha(20),
      );
      canvas.drawLine(
        Offset(0, yOf(band.$2)),
        Offset(size.width, yOf(band.$2)),
        Paint()
          ..color = BiobaseColors.live.withAlpha(110)
          ..strokeWidth = 0.8,
      );
    }
    final slot = size.width / bars.length;
    final dual = secondaryBars != null;
    final barW = (slot * (dual ? 0.32 : 0.55)).clamp(1.0, 14.0);

    final paint = Paint()..color = color;
    final secondaryPaint = Paint()..color = secondaryColor;

    for (var i = 0; i < bars.length; i++) {
      final centerX = slot * i + slot / 2;
      final h = (bars[i].y / maxY).clamp(0.0, 1.0) * plotH;
      final x0 = dual ? centerX - barW - 1 : centerX - barW / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x0, topPad + plotH - h, barW, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
      if (dual && i < secondaryBars!.length) {
        final h2 = (secondaryBars![i].y / maxY).clamp(0.0, 1.0) * plotH;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(centerX + 1, topPad + plotH - h2, barW, h2),
            const Radius.circular(1.5),
          ),
          secondaryPaint,
        );
      }
      // Round labels: sparse (every ~5) to stay quiet
      if (bars.length <= 12 || (i + 1) % 5 == 0 || i == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
              fontSize: 7,
              fontFamily: 'monospace',
              color: BiobaseColors.textTertiary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(centerX - label.width / 2, size.height - labelH + 2),
        );
      }
    }

    final maxLabel = TextPainter(
      text: TextSpan(
        text: '${maxY.round()}',
        style: const TextStyle(
          fontSize: 8,
          fontFamily: 'monospace',
          color: BiobaseColors.textTertiary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    maxLabel.paint(canvas, const Offset(2, 0));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.bars != bars ||
      old.secondaryBars != secondaryBars ||
      old.benchmarkBand != benchmarkBand;
}
