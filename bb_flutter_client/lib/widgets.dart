import 'package:flutter/material.dart';
import 'theme.dart';
import 'models.dart';

class StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const StatCell({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent ? BiobaseColors.liveDim : BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accent
              ? BiobaseColors.live.withAlpha(38)
              : BiobaseColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.text,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: BiobaseColors.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class KeyIndicator extends StatelessWidget {
  final String label;
  final bool active;

  const KeyIndicator({super.key, required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 42),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: active ? BiobaseColors.live : BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: active ? Colors.white : BiobaseColors.textTertiary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final StatusLevel status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      StatusLevel.live => ('LIVE', BiobaseColors.live, BiobaseColors.liveDim),
      StatusLevel.online => (
        'ONLINE',
        BiobaseColors.accent,
        BiobaseColors.accentDim
      ),
      StatusLevel.offline => (
        'OFFLINE',
        BiobaseColors.error,
        BiobaseColors.errorDim
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BiobaseColors.warning.withAlpha(26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'SOON',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: BiobaseColors.warning,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  final String title;
  final Widget? badge;
  final Widget child;

  const Panel({
    super.key,
    required this.title,
    this.badge,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BiobaseColors.borderSubtle),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                  letterSpacing: -0.1,
                ),
              ),
              if (badge != null) badge!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class MovementPanel extends StatelessWidget {
  final LiveFrame frame;
  final bool live;

  const MovementPanel({super.key, required this.frame, this.live = false});

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Movement',
      badge: StatusBadge(
          status: live ? StatusLevel.live : StatusLevel.offline),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatCell(
                  label: 'speed',
                  value: '${frame.speed}',
                  accent: frame.speed > 200,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: StatCell(
                  label: 'counter-strafe',
                  value: frame.counterStrafeScore.toStringAsFixed(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: StatCell(
                  label: 'path efficiency',
                  value: frame.pathEfficiency.toStringAsFixed(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: StatCell(label: 'tick', value: '${frame.tick}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String label;
  final String title;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.label,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: BiobaseColors.accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                  letterSpacing: -0.4,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class StatusDot extends StatelessWidget {
  final StatusLevel level;
  final double size;

  const StatusDot({super.key, required this.level, this.size = 6});

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      StatusLevel.live => BiobaseColors.live,
      StatusLevel.online => BiobaseColors.accent,
      StatusLevel.offline => BiobaseColors.error,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: level == StatusLevel.live
            ? [BoxShadow(color: color.withAlpha(102), blurRadius: 6)]
            : null,
      ),
    );
  }
}
