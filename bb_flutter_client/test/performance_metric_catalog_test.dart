import 'package:biobase_client/models/performance_contract.dart';
import 'package:biobase_client/models/performance_metric_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog contains all canonical categories and 121 unique metrics', () {
    expect(
      performanceMetricCatalog.keys.toSet(),
      PerformanceCategoryId.values.toSet(),
    );

    final metrics = performanceMetricCatalog.values.expand((items) => items);
    expect(metrics.length, 121);
    expect(metrics.map((metric) => metric.id).toSet().length, 121);
  });

  test('every category has a non-empty metric inventory', () {
    for (final category in PerformanceCategoryId.values) {
      expect(performanceMetricCatalog[category], isNotEmpty);
    }
  });
}
