import 'package:biobase_client/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('performance review preferences persist', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();

    await settings.setPerformanceCategoryOrder(['aim', 'movement', 'combat']);
    await settings.setExpandedPerformanceCategories(['aim', 'consistency']);

    expect(settings.performanceCategoryOrder, ['aim', 'movement', 'combat']);
    expect(settings.expandedPerformanceCategories, ['aim', 'consistency']);
  });
}
