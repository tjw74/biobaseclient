import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  SharedPreferences? _prefs;

  String get apiBaseUrl =>
      _prefs?.getString('apiBaseUrl') ?? 'https://cs2.clarionlab.dev/admin';
  String get deviceName => _prefs?.getString('deviceName') ?? '';
  String get trackedPlayerName => _prefs?.getString('trackedPlayerName') ?? '';
  bool get shareStats => _prefs?.getBool('shareStats') ?? true;
  List<String> get performanceCategoryOrder =>
      _prefs?.getStringList('performanceCategoryOrder') ?? const [];
  List<String> get expandedPerformanceCategories =>
      _prefs?.getStringList('expandedPerformanceCategories') ?? const [];

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> setApiBaseUrl(String url) async {
    await init();
    await _prefs!.setString('apiBaseUrl', url);
  }

  Future<void> setDeviceName(String name) async {
    await init();
    await _prefs!.setString('deviceName', name);
  }

  Future<void> setTrackedPlayerName(String name) async {
    await init();
    await _prefs!.setString('trackedPlayerName', name);
  }

  Future<void> setShareStats(bool value) async {
    await init();
    await _prefs!.setBool('shareStats', value);
  }

  Future<void> setPerformanceCategoryOrder(List<String> value) async {
    await init();
    await _prefs!.setStringList('performanceCategoryOrder', value);
  }

  Future<void> setExpandedPerformanceCategories(List<String> value) async {
    await init();
    await _prefs!.setStringList('expandedPerformanceCategories', value);
  }
}
