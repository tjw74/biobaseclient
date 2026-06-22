import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';

class ReplayScreen extends StatelessWidget {
  const ReplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(0),
      children: [
        Panel(
          title: 'Demo Files',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            child: const Text(
              'Demo file parsing will be available in a future update.\nUse the Electron client for demo replay until then.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: BiobaseColors.textTertiary,
                height: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          title: 'Timeline',
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: 0,
                  minHeight: 3,
                  backgroundColor: BiobaseColors.surfaceHover,
                  valueColor: const AlwaysStoppedAnimation(BiobaseColors.accent),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '0.00s · tick 0',
                  style: TextStyle(
                    fontSize: 11,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
