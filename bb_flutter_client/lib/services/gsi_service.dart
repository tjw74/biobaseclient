import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class GsiState {
  final String mapName;
  final int round;
  final String mapPhase;
  final String roundPhase;
  final int timestamp;
  final String? playerName;

  const GsiState({
    this.mapName = '',
    this.round = 0,
    this.mapPhase = '',
    this.roundPhase = '',
    this.timestamp = 0,
    this.playerName,
  });
}

const _gsiPort = 29741;

const _gsiConfig = '''
"BioBase"
{
    "uri"          "http://127.0.0.1:$_gsiPort"
    "timeout"      "5.0"
    "buffer"       "0.1"
    "throttle"     "0.5"
    "heartbeat"    "10.0"
    "data"
    {
        "provider"              "1"
        "map"                   "1"
        "round"                 "1"
        "player_id"             "1"
        "player_state"          "1"
        "allplayers_id"         "1"
        "allplayers_state"      "1"
        "allplayers_position"   "1"
    }
}
''';

class GsiService {
  HttpServer? _server;
  final _state = StreamController<GsiState>.broadcast();
  GsiState? last;

  Stream<GsiState> get stateStream => _state.stream;
  bool get running => _server != null;

  Future<bool> start() async {
    if (_server != null) return true;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _gsiPort);
      _server!.listen(_handleRequest);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleRequest(HttpRequest req) async {
    if (req.method == 'POST') {
      try {
        final body = await utf8.decoder.bind(req).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final state = _parse(json);
        last = state;
        _state.add(state);
      } catch (_) {}
    }
    req.response
      ..statusCode = 200
      ..close();
  }

  GsiState _parse(Map<String, dynamic> json) {
    final map = json['map'] as Map<String, dynamic>? ?? {};
    final round = json['round'] as Map<String, dynamic>? ?? {};
    final player = json['player'] as Map<String, dynamic>? ?? {};
    final provider = json['provider'] as Map<String, dynamic>? ?? {};

    return GsiState(
      mapName: map['name'] as String? ?? '',
      round: map['round'] as int? ?? 0,
      mapPhase: map['phase'] as String? ?? '',
      roundPhase: round['phase'] as String? ?? '',
      timestamp: provider['timestamp'] as int? ?? 0,
      playerName: player['name'] as String?,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void dispose() {
    stop();
    _state.close();
  }

  // --- CS2 path detection & config install ---

  static Future<String?> findCs2CfgPath() async {
    final candidates = <String>[];

    if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', [
          'query',
          r'HKLM\SOFTWARE\WOW6432Node\Valve\Steam',
          '/v',
          'InstallPath',
        ]);
        if (result.exitCode == 0) {
          final match =
              RegExp(r'REG_SZ\s+(.+)').firstMatch(result.stdout as String);
          if (match != null) {
            candidates.add(p.join(
              match.group(1)!.trim(),
              'steamapps',
              'common',
              'Counter-Strike Global Offensive',
              'game',
              'csgo',
              'cfg',
            ));
          }
        }
      } catch (_) {}
      candidates.addAll([
        r'C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
        r'D:\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
        r'E:\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
      ]);
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      candidates.add(p.join(
        home,
        'Library',
        'Application Support',
        'Steam',
        'steamapps',
        'common',
        'Counter-Strike Global Offensive',
        'game',
        'csgo',
        'cfg',
      ));
    }

    for (final c in candidates) {
      if (Directory(c).existsSync()) return c;
    }
    return null;
  }

  static Future<bool> installConfig() async {
    final cfgPath = await findCs2CfgPath();
    if (cfgPath == null) return false;
    final file =
        File(p.join(cfgPath, 'gamestate_integration_biobase.cfg'));
    await file.writeAsString(_gsiConfig);
    return true;
  }

  static Future<bool> isConfigInstalled() async {
    final cfgPath = await findCs2CfgPath();
    if (cfgPath == null) return false;
    return File(p.join(cfgPath, 'gamestate_integration_biobase.cfg'))
        .existsSync();
  }
}
