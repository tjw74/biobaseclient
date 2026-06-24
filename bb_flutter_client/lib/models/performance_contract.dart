enum PerformanceCategoryId {
  movement,
  aim,
  combat,
  utility,
  positioning,
  decisionMaking,
  teamplay,
  economy,
  roundPerformance,
  consistency,
  mechanicalExecution,
  biometrics,
}

enum MetricSource {
  serverTelemetry,
  demoParser,
  gameEvent,
  sessionHistory,
  derivedHeuristic,
  biometricDevice,
}

enum EvidenceState { observed, derived, unavailable }

class CategoryAssessment {
  final PerformanceCategoryId id;
  final String label;
  final double? score;
  final EvidenceState state;
  final MetricSource source;
  final double confidence;
  final String bestSignal;
  final String issue;
  final String impact;
  final String detail;

  const CategoryAssessment({
    required this.id,
    required this.label,
    required this.score,
    required this.state,
    required this.source,
    required this.confidence,
    required this.bestSignal,
    required this.issue,
    required this.impact,
    required this.detail,
  });

  bool get available => score != null && state != EvidenceState.unavailable;

  String get stateLabel => switch (state) {
    EvidenceState.observed => 'Observed',
    EvidenceState.derived => 'Estimated',
    EvidenceState.unavailable => 'Not measured',
  };

  String get sourceLabel => switch (source) {
    MetricSource.serverTelemetry => 'Server telemetry',
    MetricSource.demoParser => 'Demo parser',
    MetricSource.gameEvent => 'Game events',
    MetricSource.sessionHistory => 'Session history',
    MetricSource.derivedHeuristic => 'Derived estimate',
    MetricSource.biometricDevice => 'Biometric device',
  };
}
