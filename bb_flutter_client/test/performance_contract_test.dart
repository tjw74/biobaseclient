import 'package:flutter_test/flutter_test.dart';
import 'package:biobase_client/models/performance_contract.dart';
import 'package:biobase_client/models/performance_review.dart';
import 'package:biobase_client/models/session_stats.dart';

void main() {
  test('unmeasured categories are unavailable and excluded', () {
    final stats = SessionStats();
    final assessments = stats.releaseAssessments;

    expect(assessments, hasLength(12));
    expect(assessments.every((item) => !item.available), isTrue);
    expect(stats.releaseOverallScore, 0);
    expect(assessments.last.id, PerformanceCategoryId.biometrics);
    expect(assessments.last.state, EvidenceState.unavailable);
  });

  test('movement estimates expose confidence and do not unlock biometrics', () {
    final stats = SessionStats()
      ..totalSamples = 120
      ..speedAvg = 240
      ..pathEfficiency = 0.8
      ..airTimePercent = 15
      ..counterStrafeAccuracy = 74
      ..strafeSyncPercent = 70;
    stats.speedHistory.addAll(List<double>.generate(60, (i) => 220 + i % 5));
    stats.consistencyScore = 88;

    final assessments = stats.releaseAssessments;
    final movement = assessments.first;
    final biometrics = assessments.last;

    expect(movement.available, isTrue);
    expect(movement.state, EvidenceState.derived);
    expect(movement.confidence, greaterThan(0.8));
    expect(biometrics.available, isFalse);
    expect(stats.releaseOverallScore, greaterThan(0));
  });
}
