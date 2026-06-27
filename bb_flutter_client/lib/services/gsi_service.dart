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

  static Future<String?> _findSteamPath() async {
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
          if (match != null) return match.group(1)!.trim();
        }
      } catch (_) {}
      for (final path in [
        r'C:\Program Files (x86)\Steam',
        r'D:\Steam',
        r'E:\Steam',
      ]) {
        if (Directory(path).existsSync()) return path;
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      final path = p.join(home, 'Library', 'Application Support', 'Steam');
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }

  static Future<bool> ensureNetconLaunchOption() async {
    final steamPath = await _findSteamPath();
    if (steamPath == null) return false;

    final userdata = Directory(p.join(steamPath, 'userdata'));
    if (!userdata.existsSync()) return false;

    var found = false;
    for (final dir in userdata.listSync().whereType<Directory>()) {
      final vdf = File(p.join(dir.path, 'config', 'localconfig.vdf'));
      if (!vdf.existsSync()) continue;

      var content = vdf.readAsStringSync();
      if (content.contains('-netconport')) {
        found = true;
        continue;
      }

      // Find CS2 (app 730) launch options in the VDF
      final patched = _injectNetconOption(content);
      if (patched != null) {
        vdf.writeAsStringSync(patched);
        found = true;
      }
    }
    return found;
  }

  static String? _injectNetconOption(String content) {
    // VDF is a nested key-value format. We need to find the "730" app block
    // under Software/Valve/Steam/apps and add/modify LaunchOptions.
    // Strategy: find "730" block, look for "LaunchOptions", append or insert.

    // Match "730" followed by its block opening brace
    final app730 = RegExp(r'"730"\s*\{');
    final match = app730.firstMatch(content);
    if (match == null) return null;

    final blockStart = match.end;

    // Find the matching closing brace for app 730's block
    var depth = 1;
    var blockEnd = blockStart;
    for (var i = blockStart; i < content.length && depth > 0; i++) {
      if (content[i] == '{') depth++;
      if (content[i] == '}') depth--;
      if (depth == 0) blockEnd = i;
    }

    final block = content.substring(blockStart, blockEnd);

    // Check if LaunchOptions already exists in this block
    final launchMatch =
        RegExp(r'"LaunchOptions"\s+"([^"]*)"').firstMatch(block);

    if (launchMatch != null) {
      final existing = launchMatch.group(1)!;
      if (existing.contains('-netconport')) return null;
      final updated = '$existing -netconport 2121';
      return content.replaceFirst(
        '"LaunchOptions"\t\t"$existing"',
        '"LaunchOptions"\t\t"$updated"',
      );
    }

    // No LaunchOptions key — insert one right after the opening brace
    final insertion = '\n\t\t\t\t\t"LaunchOptions"\t\t"-netconport 2121"';
    return content.substring(0, blockStart) +
        insertion +
        content.substring(blockStart);
  }

  static Future<bool> hasNetconLaunchOption() async {
    final steamPath = await _findSteamPath();
    if (steamPath == null) return false;
    final userdata = Directory(p.join(steamPath, 'userdata'));
    if (!userdata.existsSync()) return false;

    for (final dir in userdata.listSync().whereType<Directory>()) {
      final vdf = File(p.join(dir.path, 'config', 'localconfig.vdf'));
      if (!vdf.existsSync()) continue;
      if (vdf.readAsStringSync().contains('-netconport')) return true;
    }
    return false;
  }
}
