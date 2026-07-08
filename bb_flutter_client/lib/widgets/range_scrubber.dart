import 'package:flutter/material.dart';

import '../theme.dart';

/// Timeline scrubber with an optional Plotly-style range selector.
///
/// Normal mode: single playhead, tap/drag to seek, saved move ranges drawn
/// on the track. Range mode: two draggable grips define a move's start and
/// end tick; each grip carries an exact tick + time readout, the selected
/// span is highlighted, and the span width (ticks · seconds) is shown when
/// there is room.
class RangeScrubber extends StatefulWidget {
  final double progress; // 0..1 playhead position
  final int demoStartTick;
  final int demoEndTick;
  final int tickRate;
  final List<(double, double)> moveRanges; // saved moves, position fractions
  final ValueChanged<double> onSeek;

  final bool rangeMode;
  final int? rangeStart; // tick
  final int? rangeEnd; // tick
  /// handle: 0 = left grip, 1 = right grip. Fired continuously during drags.
  final void Function(int startTick, int endTick, int handle)? onRangeChanged;

  const RangeScrubber({
    super.key,
    required this.progress,
    required this.demoStartTick,
    required this.demoEndTick,
    required this.tickRate,
    required this.onSeek,
    this.moveRanges = const [],
    this.rangeMode = false,
    this.rangeStart,
    this.rangeEnd,
    this.onRangeChanged,
  });

  @override
  State<RangeScrubber> createState() => _RangeScrubberState();
}

enum _DragTarget { none, seek, leftGrip, rightGrip }

class _RangeScrubberState extends State<RangeScrubber> {
  _DragTarget _drag = _DragTarget.none;

  int get _span =>
      (widget.demoEndTick - widget.demoStartTick).clamp(1, 1 << 31);

  double _tickToFrac(int tick) =>
      ((tick - widget.demoStartTick) / _span).clamp(0.0, 1.0);

  int _fracToTick(double frac) =>
      widget.demoStartTick + (frac.clamp(0.0, 1.0) * _span).round();

  double get _height => widget.rangeMode ? 34 : 16;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _handleTap(d.localPosition, width),
            onHorizontalDragStart: (d) =>
                _dragStart(d.localPosition, width),
            onHorizontalDragUpdate: (d) =>
                _dragUpdate(d.localPosition, width),
            onHorizontalDragEnd: (_) => _drag = _DragTarget.none,
            onHorizontalDragCancel: () => _drag = _DragTarget.none,
            child: CustomPaint(
              painter: _ScrubberPainter(
                progress: widget.progress,
                moveRanges: widget.moveRanges,
                rangeMode: widget.rangeMode,
                leftFrac: widget.rangeStart != null
                    ? _tickToFrac(widget.rangeStart!)
                    : null,
                rightFrac: widget.rangeEnd != null
                    ? _tickToFrac(widget.rangeEnd!)
                    : null,
                leftLabel: widget.rangeStart != null
                    ? _label(widget.rangeStart!)
                    : null,
                rightLabel: widget.rangeEnd != null
                    ? _label(widget.rangeEnd!)
                    : null,
                spanLabel: _spanLabel(),
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }

  String _label(int tick) {
    final rate = widget.tickRate <= 0 ? 64 : widget.tickRate;
    final sec = (tick - widget.demoStartTick) / rate;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toInt()}:${s.toStringAsFixed(1).padLeft(4, '0')} · t$tick';
  }

  String? _spanLabel() {
    final a = widget.rangeStart, b = widget.rangeEnd;
    if (!widget.rangeMode || a == null || b == null) return null;
    final rate = widget.tickRate <= 0 ? 64 : widget.tickRate;
    final ticks = (b - a).abs();
    return '$ticks ticks · ${(ticks / rate).toStringAsFixed(1)}s';
  }

  void _handleTap(Offset pos, double width) {
    final target = _hitTest(pos, width);
    if (target == _DragTarget.leftGrip || target == _DragTarget.rightGrip) {
      return; // grips respond to drags, not taps
    }
    widget.onSeek((pos.dx / width).clamp(0.0, 1.0));
  }

  void _dragStart(Offset pos, double width) {
    _drag = _hitTest(pos, width);
    _dragUpdate(pos, width);
  }

  void _dragUpdate(Offset pos, double width) {
    final frac = (pos.dx / width).clamp(0.0, 1.0);
    switch (_drag) {
      case _DragTarget.leftGrip:
        final a = widget.rangeStart, b = widget.rangeEnd;
        if (a == null || b == null) return;
        final tick = _fracToTick(frac).clamp(widget.demoStartTick, b - 1);
        widget.onRangeChanged?.call(tick, b, 0);
      case _DragTarget.rightGrip:
        final a = widget.rangeStart, b = widget.rangeEnd;
        if (a == null || b == null) return;
        final tick = _fracToTick(frac).clamp(a + 1, widget.demoEndTick);
        widget.onRangeChanged?.call(a, tick, 1);
      case _DragTarget.seek:
        widget.onSeek(frac);
      case _DragTarget.none:
        break;
    }
  }

  _DragTarget _hitTest(Offset pos, double width) {
    if (widget.rangeMode &&
        widget.rangeStart != null &&
        widget.rangeEnd != null) {
      final lx = _tickToFrac(widget.rangeStart!) * width;
      final rx = _tickToFrac(widget.rangeEnd!) * width;
      // Nearest grip wins when both are close (narrow ranges).
      final dl = (pos.dx - lx).abs();
      final dr = (pos.dx - rx).abs();
      const grab = 14.0;
      if (dl <= grab || dr <= grab) {
        return dl <= dr ? _DragTarget.leftGrip : _DragTarget.rightGrip;
      }
    }
    return _DragTarget.seek;
  }
}

class _ScrubberPainter extends CustomPainter {
  final double progress;
  final List<(double, double)> moveRanges;
  final bool rangeMode;
  final double? leftFrac;
  final double? rightFrac;
  final String? leftLabel;
  final String? rightLabel;
  final String? spanLabel;

  _ScrubberPainter({
    required this.progress,
    required this.moveRanges,
    required this.rangeMode,
    this.leftFrac,
    this.rightFrac,
    this.leftLabel,
    this.rightLabel,
    this.spanLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Track sits at the bottom; label row above it in range mode.
    final trackCenterY = size.height - 8;
    const trackH = 4.0;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackCenterY - trackH / 2, size.width, trackH),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = BiobaseColors.surfaceRaised.withAlpha(200),
    );

    // Saved move ranges
    for (final (a, b) in moveRanges) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            a * size.width,
            trackCenterY - trackH / 2,
            ((b - a) * size.width).clamp(1.0, size.width),
            trackH,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = BiobaseColors.live.withAlpha(120),
      );
    }

    // Progress fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          trackCenterY - trackH / 2,
          progress.clamp(0.0, 1.0) * size.width,
          trackH,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = BiobaseColors.accent,
    );

    // Playhead
    final px = progress.clamp(0.0, 1.0) * size.width;
    canvas.drawCircle(
      Offset(px, trackCenterY),
      rangeMode ? 4 : 6,
      Paint()..color = BiobaseColors.accent,
    );

    if (!rangeMode || leftFrac == null || rightFrac == null) return;

    final lx = leftFrac! * size.width;
    final rx = rightFrac! * size.width;

    // Selected region
    canvas.drawRect(
      Rect.fromLTRB(lx, trackCenterY - 8, rx, trackCenterY + 8),
      Paint()..color = BiobaseColors.warning.withAlpha(36),
    );
    canvas.drawRect(
      Rect.fromLTRB(lx, trackCenterY - 8, rx, trackCenterY + 8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = BiobaseColors.warning.withAlpha(120),
    );

    // Grips — vertical bars with a notch, Plotly-style.
    for (final (x, isLeft) in [(lx, true), (rx, false)]) {
      final grip = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, trackCenterY),
          width: 8,
          height: 20,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(grip, Paint()..color = BiobaseColors.warning);
      canvas.drawLine(
        Offset(x, trackCenterY - 5),
        Offset(x, trackCenterY + 5),
        Paint()
          ..strokeWidth = 1.4
          ..color = Colors.black.withAlpha(140),
      );

      final labelText = isLeft ? leftLabel : rightLabel;
      if (labelText == null) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            fontSize: 8,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            color: BiobaseColors.warning,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Left grip label anchors left of the grip, right grip to the right,
      // clamped inside the widget.
      var labelX = isLeft ? x - tp.width - 6 : x + 6;
      labelX = labelX.clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(labelX, 0));
    }

    // Span readout centered in the region when it fits.
    if (spanLabel != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: spanLabel,
          style: TextStyle(
            fontSize: 8,
            fontFamily: 'monospace',
            color: BiobaseColors.text.withAlpha(220),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (rx - lx > tp.width + 12) {
        tp.paint(
          canvas,
          Offset((lx + rx) / 2 - tp.width / 2, trackCenterY - 26 + 12),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter old) =>
      old.progress != progress ||
      old.moveRanges != moveRanges ||
      old.rangeMode != rangeMode ||
      old.leftFrac != leftFrac ||
      old.rightFrac != rightFrac ||
      old.spanLabel != spanLabel;
}
