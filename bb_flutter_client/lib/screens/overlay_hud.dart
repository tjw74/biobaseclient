import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../models.dart';
import '../theme.dart';

class OverlayHud extends StatelessWidget {
  final LiveFrame frame;
  final bool live;
  final bool stale;
  final VoidCallback onExit;

  const OverlayHud({
    super.key,
    required this.frame,
    required this.live,
    required this.stale,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final dataLive = live && !stale;

    return Scaffold(
      backgroundColor: BiobaseColors.bg,
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(dataLive),
            const SizedBox(height: 10),
            _speed(dataLive),
            const SizedBox(height: 10),
            _bar('C-Strafe', frame.counterStrafeScore, BiobaseColors.accent),
            const SizedBox(height: 5),
            _bar('Path Eff', frame.pathEfficiency, BiobaseColors.live),
            const Spacer(),
            _bottom(),
          ],
        ),
      ),
    );
  }

  Widget _header(bool dataLive) {
    return DragToMoveArea(
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stale
                  ? BiobaseColors.warning
                  : dataLive
                      ? BiobaseColors.live
                      : BiobaseColors.textTertiary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            stale ? 'BioBase — stale' : 'BioBase',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: dataLive ? BiobaseColors.text : BiobaseColors.textTertiary,
            ),
          ),
          const Spacer(),
          Text(
            'Ctrl+Shift+O',
            style: TextStyle(
              fontSize: 8,
              color: BiobaseColors.textTertiary.withAlpha(80),
            ),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onExit,
              child: const Icon(
                Icons.close,
                size: 12,
                color: BiobaseColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speed(bool dataLive) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '${frame.speed}',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w700,
            color: dataLive ? BiobaseColors.text : BiobaseColors.textTertiary,
            fontFamily: 'monospace',
            height: 1,
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'u/s',
          style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary),
        ),
        const Spacer(),
        if (frame.isAirborne)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: BiobaseColors.accentDim,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'AIR',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.accent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: BiobaseColors.surfaceRaised,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 30,
          child: Text(
            '${(value * 100).toInt()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottom() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _wasd(frame.keys),
        const Spacer(),
        Text(
          'tick ${frame.tick}',
          style: const TextStyle(
            fontSize: 9,
            color: BiobaseColors.textTertiary,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  static Widget _wasd(MovementKeys k) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [_k('W', k.w)],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [_k('A', k.a), _k('S', k.s), _k('D', k.d)],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _k('⇧', k.crouch, w: 32),
            const SizedBox(width: 2),
            _k('␣', k.jump, w: 44),
          ],
        ),
      ],
    );
  }

  static Widget _k(String label, bool on, {double w = 20}) {
    return Container(
      width: w,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: on ? BiobaseColors.accent : BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: on ? BiobaseColors.accent : BiobaseColors.border,
          width: 0.5,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : BiobaseColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
