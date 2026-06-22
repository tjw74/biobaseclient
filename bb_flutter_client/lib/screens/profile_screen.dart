import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(0),
      children: [
        Panel(
          title: 'Performance Scores',
          child: Row(
            children: [
              Expanded(child: _scoreCard('MOVEMENT QUALITY', '—',
                  'Play a session to establish baseline')),
              const SizedBox(width: 6),
              Expanded(child: _scoreCard(
                  'COUNTER-STRAFE', '—', 'Stop accuracy and timing')),
              const SizedBox(width: 6),
              Expanded(child: _scoreCard(
                  'PATH EFFICIENCY', '—', 'Route optimization score')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          title: 'Session History',
          child: const Text(
            'Your performance trends will appear here after you play sessions on Biobase.',
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

  Widget _scoreCard(String label, String value, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BiobaseColors.borderSubtle),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: BiobaseColors.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
