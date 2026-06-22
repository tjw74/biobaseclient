import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class LiveScreen extends StatelessWidget {
  final LiveFrame frame;
  final bool live;

  const LiveScreen({super.key, required this.frame, this.live = false});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(0),
      children: [
        _SpeedPanel(frame: frame, live: live),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _VelocityPanel(frame: frame)),
            const SizedBox(width: 8),
            Expanded(child: _PositionPanel(frame: frame)),
          ],
        ),
        const SizedBox(height: 8),
        _KeysAndStatePanel(frame: frame),
        const SizedBox(height: 8),
        _BhopPanel(frame: frame),
        const SizedBox(height: 8),
        Panel(
          title: 'Shooting',
          badge: const SoonBadge(),
          child: Text(
            'Accuracy, spray control, and crosshair placement — coming in a future update.',
            style: TextStyle(
              fontSize: 12,
              color: BiobaseColors.textTertiary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedPanel extends StatelessWidget {
  final LiveFrame frame;
  final bool live;

  const _SpeedPanel({required this.frame, required this.live});

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
                child: Text(
                  'u/s',
                  style: TextStyle(
                    fontSize: 13,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _speedColor(frame.speed).withAlpha(26),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    grade,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _speedColor(frame.speed),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${frame.yaw.toStringAsFixed(1)}° yaw',
                  style: TextStyle(
                    fontSize: 12,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
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
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0', style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
              Text('250 (knife max)', style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _VelocityPanel extends StatelessWidget {
  final LiveFrame frame;

  const _VelocityPanel({required this.frame});

  @override
  Widget build(BuildContext context) {
    final vx = frame.vel.isNotEmpty ? frame.vel[0] : 0.0;
    final vy = frame.vel.length > 1 ? frame.vel[1] : 0.0;
    final vz = frame.vel.length > 2 ? frame.vel[2] : 0.0;

    return Panel(
      title: 'Velocity',
      child: Column(
        children: [
          _VelRow('X', vx),
          const SizedBox(height: 4),
          _VelRow('Y', vy),
          const SizedBox(height: 4),
          _VelRow('Z', vz),
        ],
      ),
    );
  }

  Widget _VelRow(String axis, double val) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(axis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            val.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              color: BiobaseColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _PositionPanel extends StatelessWidget {
  final LiveFrame frame;

  const _PositionPanel({required this.frame});

  @override
  Widget build(BuildContext context) {
    final x = frame.pos.isNotEmpty ? frame.pos[0] : 0.0;
    final y = frame.pos.length > 1 ? frame.pos[1] : 0.0;
    final z = frame.pos.length > 2 ? frame.pos[2] : 0.0;

    return Panel(
      title: 'Position',
      child: Column(
        children: [
          _PosRow('X', x),
          const SizedBox(height: 4),
          _PosRow('Y', y),
          const SizedBox(height: 4),
          _PosRow('Z', z),
        ],
      ),
    );
  }

  Widget _PosRow(String axis, double val) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(axis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            val.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              color: BiobaseColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _KeysAndStatePanel extends StatelessWidget {
  final LiveFrame frame;

  const _KeysAndStatePanel({required this.frame});

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Input & State',
      child: Row(
        children: [
          Expanded(
            child: Wrap(
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
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StateChip(
                label: frame.onGround ? 'GROUNDED' : 'AIRBORNE',
                active: !frame.onGround,
                color: frame.onGround ? BiobaseColors.textTertiary : BiobaseColors.warning,
              ),
              const SizedBox(height: 4),
              _StateChip(
                label: '${frame.pitch.toStringAsFixed(1)}° pitch',
                active: false,
                color: BiobaseColors.textTertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _StateChip({required this.label, required this.active, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(active ? 26 : 13),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

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
                  accent: bhopReady,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: StatCell(
                  label: 'vertical vel',
                  value: frame.velZ.toStringAsFixed(1),
                  accent: frame.velZ > 200,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: StatCell(
                  label: 'state',
                  value: frame.isAirborne
                      ? (perfectBhop ? 'PERFECT' : 'AIR')
                      : 'GROUND',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniStat('Counter-strafe', frame.counterStrafeScore.toStringAsFixed(2)),
              const SizedBox(width: 16),
              _MiniStat('Path efficiency', frame.pathEfficiency.toStringAsFixed(2)),
              const SizedBox(width: 16),
              _MiniStat('Tick', '${frame.tick}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _MiniStat(String label, String value) {
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
