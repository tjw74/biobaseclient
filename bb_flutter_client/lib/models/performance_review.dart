import 'performance_contract.dart';
import 'session_stats.dart';

extension ReleasePerformanceReview on SessionStats {
  double get releaseOverallScore {
    final active = releaseAssessments.where((a) => a.available).toList();
    if (active.isEmpty) return 0;
    final confidenceTotal = active.fold<double>(
      0,
      (sum, a) => sum + a.confidence,
    );
    if (confidenceTotal <= 0) return 0;
    return active.fold<double>(0, (sum, a) => sum + (a.score! * a.confidence)) /
        confidenceTotal;
  }

  List<CategoryAssessment> get releaseAssessments {
    final sampleConfidence = (totalSamples / 120).clamp(0.0, 0.92);
    final historyConfidence = ((speedHistory.length - 10) / 50).clamp(
      0.0,
      0.85,
    );
    final hasMovement = totalSamples >= 10;
    final hasHistory = speedHistory.length >= 12;

    CategoryAssessment unavailable({
      required PerformanceCategoryId id,
      required String label,
      required MetricSource source,
      required String detail,
    }) => CategoryAssessment(
      id: id,
      label: label,
      score: null,
      state: EvidenceState.unavailable,
      source: source,
      confidence: 0,
      bestSignal: 'No verified signal yet',
      issue: 'Required data is not connected',
      impact: 'Excluded from overall score',
      detail: detail,
    );

    return [
      hasMovement
          ? CategoryAssessment(
              id: PerformanceCategoryId.movement,
              label: 'Movement',
              score: movementScore,
              state: EvidenceState.derived,
              source: MetricSource.serverTelemetry,
              confidence: sampleConfidence,
              bestSignal: 'Path efficiency ${(pathEfficiency * 100).toInt()}%',
              issue:
                  'Counter-strafe estimate ${counterStrafeAccuracy.toInt()}%',
              impact: '$totalSamples live samples analyzed',
              detail: 'Position, velocity, ground state, and movement history.',
            )
          : unavailable(
              id: PerformanceCategoryId.movement,
              label: 'Movement',
              source: MetricSource.serverTelemetry,
              detail: 'Needs at least 10 valid live movement samples.',
            ),
      hasMovement
          ? CategoryAssessment(
              id: PerformanceCategoryId.aim,
              label: 'Aim',
              score: aimScore,
              state: EvidenceState.derived,
              source: MetricSource.derivedHeuristic,
              confidence: sampleConfidence * 0.55,
              bestSignal:
                  'Head-level estimate ${crosshairHeadLevelPercent.toInt()}%',
              issue: 'Shot and target events are not connected',
              impact: 'Crosshair orientation only',
              detail:
                  'Pitch estimate, not verified crosshair-to-enemy placement.',
            )
          : unavailable(
              id: PerformanceCategoryId.aim,
              label: 'Aim',
              source: MetricSource.demoParser,
              detail: 'Needs view angles plus shot and target events.',
            ),
      unavailable(
        id: PerformanceCategoryId.combat,
        label: 'Combat',
        source: MetricSource.gameEvent,
        detail: 'Needs kills, damage, assists, trades, and round context.',
      ),
      unavailable(
        id: PerformanceCategoryId.utility,
        label: 'Utility',
        source: MetricSource.gameEvent,
        detail: 'Needs grenade events and their outcome windows.',
      ),
      unavailable(
        id: PerformanceCategoryId.positioning,
        label: 'Positioning',
        source: MetricSource.demoParser,
        detail: 'Needs map geometry, exposure, peek, and location events.',
      ),
      unavailable(
        id: PerformanceCategoryId.decisionMaking,
        label: 'Decision Making',
        source: MetricSource.gameEvent,
        detail: 'Needs round state, rotations, saves, entries, and retakes.',
      ),
      unavailable(
        id: PerformanceCategoryId.teamplay,
        label: 'Teamplay',
        source: MetricSource.demoParser,
        detail: 'Needs teammate positions, trades, flashes, and timing.',
      ),
      unavailable(
        id: PerformanceCategoryId.economy,
        label: 'Economy',
        source: MetricSource.gameEvent,
        detail: 'Needs buy, inventory, equipment value, and round economy.',
      ),
      unavailable(
        id: PerformanceCategoryId.roundPerformance,
        label: 'Round Performance',
        source: MetricSource.gameEvent,
        detail: 'Needs complete round outcomes and objective events.',
      ),
      hasHistory
          ? CategoryAssessment(
              id: PerformanceCategoryId.consistency,
              label: 'Consistency',
              score: consistencyScoreCategory,
              state: EvidenceState.derived,
              source: MetricSource.sessionHistory,
              confidence: historyConfidence,
              bestSignal: 'Speed stability ${consistencyScore.toInt()}%',
              issue: fatigueScore > 15
                  ? 'Recent speed is trending down'
                  : 'No strong fatigue signal',
              impact: '${speedHistory.length} recent samples',
              detail:
                  'Short-window movement consistency, not cross-session form.',
            )
          : unavailable(
              id: PerformanceCategoryId.consistency,
              label: 'Consistency',
              source: MetricSource.sessionHistory,
              detail: 'Needs a longer sample window and saved sessions.',
            ),
      hasMovement
          ? CategoryAssessment(
              id: PerformanceCategoryId.mechanicalExecution,
              label: 'Mechanical Execution',
              score: mechanicalExecutionScore,
              state: EvidenceState.derived,
              source: MetricSource.derivedHeuristic,
              confidence: sampleConfidence * 0.7,
              bestSignal: 'Strafe sync ${strafeSyncPercent.toInt()}%',
              issue: 'Inputs are inferred from velocity',
              impact: 'Movement mechanics only',
              detail:
                  'Weapon handling and true input events are not connected.',
            )
          : unavailable(
              id: PerformanceCategoryId.mechanicalExecution,
              label: 'Mechanical Execution',
              source: MetricSource.serverTelemetry,
              detail: 'Needs movement and input or weapon-handling events.',
            ),
      unavailable(
        id: PerformanceCategoryId.biometrics,
        label: 'BioBase Biometrics',
        source: MetricSource.biometricDevice,
        detail:
            'No biometric stream is connected. Movement fatigue is not biometric evidence.',
      ),
    ];
  }
}
