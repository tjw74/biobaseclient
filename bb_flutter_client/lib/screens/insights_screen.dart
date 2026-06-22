import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(0),
      children: [
        Panel(
          title: 'Immediate',
          child: const Text(
            'Play a few sessions to generate movement insights and recommendations.',
            style: TextStyle(
              fontSize: 12,
              color: BiobaseColors.textTertiary,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          title: 'Trends',
          child: const Text(
            'Long-term performance patterns will appear here as your profile builds.',
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
