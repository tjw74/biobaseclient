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
        MovementPanel(frame: frame, live: live),
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
