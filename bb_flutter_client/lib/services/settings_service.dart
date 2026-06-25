import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SavedServer {
  final String name;
  final String host;
  final int port;

  const SavedServer({required this.name, required this.host, this.port = 27015});

  String get address => '$host:$port';

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'port': port};

  factory SavedServer.fromJson(Map<String, dynamic> json) => SavedServer(
    name: json['name'] as String? ?? '',
    host: json['host'] as String? ?? '',
    port: json['port'] as int? ?? 27015,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedServer && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

const _defaultServers = [
  SavedServer(name: 'BioBase Cloud', host: 'cs2.clarionlab.dev'),
];

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

  List<SavedServer> get savedServers {
    final raw = _prefs?.getStringList('savedServers');
    if (raw == null) return List.of(_defaultServers);
    return raw.map((s) {
      try { return SavedServer.fromJson(jsonDecode(s) as Map<String, dynamic>); }
      catch (_) { return null; }
    }).whereType<SavedServer>().toList();
  }

  String get activeServerAddress => _prefs?.getString('activeServer') ?? 'cs2.clarionlab.dev:27015';

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

  Future<void> setSavedServers(List<SavedServer> servers) async {
    await init();
    await _prefs!.setStringList(
      'savedServers',
      servers.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  Future<void> addServer(SavedServer server) async {
    final list = savedServers;
    if (list.contains(server)) return;
    list.add(server);
    await setSavedServers(list);
  }

  Future<void> removeServer(SavedServer server) async {
    final list = savedServers;
    list.remove(server);
    await setSavedServers(list);
  }

  Future<void> setActiveServer(String address) async {
    await init();
    await _prefs!.setString('activeServer', address);
  }
}
