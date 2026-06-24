import 'package:flutter/material.dart';

import '../models/performance_contract.dart';
import '../theme.dart';

String collapsedAssessmentSummary(CategoryAssessment assessment) {
  if (!assessment.available) return assessment.detail;
  return '${assessment.bestSignal} · ${assessment.issue} · ${assessment.impact}';
}

class PerformanceEvidenceBadge extends StatelessWidget {
  final CategoryAssessment assessment;

  const PerformanceEvidenceBadge({super.key, required this.assessment});

  @override
  Widget build(BuildContext context) {
    final color = switch (assessment.state) {
      EvidenceState.observed => BiobaseColors.live,
      EvidenceState.derived => BiobaseColors.warning,
      EvidenceState.unavailable => BiobaseColors.textTertiary,
    };
    final confidence = assessment.available
        ? ' ${(assessment.confidence * 100).round()}%'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Text(
        '${assessment.stateLabel}$confidence',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: color,
        ),
      ),
    );
  }
}

class PerformanceEvidenceNote extends StatelessWidget {
  final CategoryAssessment assessment;

  const PerformanceEvidenceNote({super.key, required this.assessment});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: BiobaseColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${assessment.sourceLabel} · ${assessment.stateLabel}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            assessment.detail,
            style: const TextStyle(
              fontSize: 9,
              height: 1.35,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
