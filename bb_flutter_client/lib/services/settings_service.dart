import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  late SharedPreferences _prefs;

  String get apiBaseUrl =>
      _prefs.getString('apiBaseUrl') ?? 'https://cs2.clarionlab.dev/admin';
  String get deviceName => _prefs.getString('deviceName') ?? '';
  String get trackedPlayerName => _prefs.getString('trackedPlayerName') ?? '';
  bool get shareStats => _prefs.getBool('shareStats') ?? true;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> setApiBaseUrl(String url) =>
      _prefs.setString('apiBaseUrl', url);
  Future<void> setDeviceName(String name) =>
      _prefs.setString('deviceName', name);
  Future<void> setTrackedPlayerName(String name) =>
      _prefs.setString('trackedPlayerName', name);
  Future<void> setShareStats(bool value) =>
      _prefs.setBool('shareStats', value);
}
