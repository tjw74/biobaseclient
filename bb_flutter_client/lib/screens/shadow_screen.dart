import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ShadowScreen extends StatefulWidget {
  final LiveFrame frame;
  final bool live;

  const ShadowScreen({super.key, required this.frame, this.live = false});

  @override
  State<ShadowScreen> createState() => _ShadowScreenState();
}

class _ShadowScreenState extends State<ShadowScreen> {
  int _selectedMode = 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(0),
      children: [
        Panel(
          title: 'Performance Comparison',
          badge: StatusBadge(
              status: widget.live ? StatusLevel.live : StatusLevel.offline),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compare your real-time stats against benchmarks. Shadow mode adapts to your averages and highlights where you can improve.',
                style: TextStyle(
                  fontSize: 12,
                  color: BiobaseColors.textTertiary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildColumn('Your Stats', false)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildColumn('Benchmark', true)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          title: 'Shadow Modes',
          child: Column(
            children: [
              _modeCard(0, 'Personal Average',
                  'Compare against your own rolling average'),
              const SizedBox(height: 4),
              _modeCard(1, 'Pro Benchmark',
                  'Compare against shared pro player profiles'),
              const SizedBox(height: 4),
              _modeCard(2, 'Custom Threshold',
                  'Set your own target values to train against'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColumn(String label, bool isBenchmark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: BiobaseColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        StatCell(
          label: 'speed',
          value: isBenchmark ? '245' : '${widget.frame.speed}',
          accent: isBenchmark,
        ),
        const SizedBox(height: 4),
        StatCell(
          label: 'counter-strafe',
          value: isBenchmark
              ? '0.92'
              : widget.frame.counterStrafeScore.toStringAsFixed(2),
          accent: isBenchmark,
        ),
        const SizedBox(height: 4),
        StatCell(
          label: 'path efficiency',
          value: isBenchmark
              ? '0.88'
              : widget.frame.pathEfficiency.toStringAsFixed(2),
          accent: isBenchmark,
        ),
      ],
    );
  }

  Widget _modeCard(int index, String title, String description) {
    final selected = _selectedMode == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? BiobaseColors.accentDim
              : BiobaseColors.surfaceRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? BiobaseColors.accent
                : BiobaseColors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: const TextStyle(
                fontSize: 11,
                color: BiobaseColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
