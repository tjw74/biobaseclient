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

const _gsiConfig =
    '''
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
    final candidates = await findCs2CfgPathCandidates();

    for (final candidate in candidates) {
      if (isLikelyCs2CfgPath(candidate)) return candidate;
    }

    // Fallback for partially-installed or moving Steam libraries: a real cfg
    // directory is still better than no automation, but appmanifest-backed
    // candidates above are preferred to avoid writing into stale CS2 folders.
    for (final candidate in candidates) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static Future<List<String>> findCs2CfgPathCandidates() async {
    final steamPath = await findSteamPath();
    final libraryPaths = <String>[];

    if (steamPath != null) {
      libraryPaths.add(steamPath);
      final libraryVdf = File(
        p.join(steamPath, 'steamapps', 'libraryfolders.vdf'),
      );
      if (libraryVdf.existsSync()) {
        try {
          libraryPaths.addAll(
            steamLibraryPathsFromVdf(
              libraryVdf.readAsStringSync(),
              steamRoot: steamPath,
            ),
          );
        } catch (_) {}
      }
    }

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      libraryPaths.add(p.join(home, 'Library', 'Application Support', 'Steam'));
    }

    final manifestBacked = <String>[];
    final discovered = <String>[];
    for (final library in _uniquePaths(libraryPaths)) {
      final cfg = cs2CfgPathForSteamLibrary(library);
      final manifest = p.join(library, 'steamapps', 'appmanifest_730.acf');
      if (File(manifest).existsSync()) {
        manifestBacked.add(cfg);
      } else {
        discovered.add(cfg);
      }
    }

    if (Platform.isWindows) {
      discovered.addAll([
        r'C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
        r'C:\Program Files\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
        r'D:\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
        r'D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
        r'E:\Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
        r'E:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg',
      ]);
    }

    return _uniquePaths([...manifestBacked, ...discovered]);
  }

  static String cs2CfgPathForSteamLibrary(String libraryPath) {
    return p.join(
      libraryPath,
      'steamapps',
      'common',
      'Counter-Strike Global Offensive',
      'game',
      'csgo',
      'cfg',
    );
  }

  static List<String> steamLibraryPathsFromVdf(
    String content, {
    String? steamRoot,
  }) {
    final paths = <String>[];
    if (steamRoot != null && steamRoot.trim().isNotEmpty) {
      paths.add(steamRoot.trim());
    }

    final structuredPath = RegExp(r'"path"\s+"((?:\\.|[^"\\])*)"');
    for (final match in structuredPath.allMatches(content)) {
      paths.add(_decodeVdfString(match.group(1)!));
    }

    // Older Steam libraryfolders.vdf files used: "1" "D:\\SteamLibrary".
    final legacyPath = RegExp(r'"\d+"\s+"((?:\\.|[^"\\])*)"');
    for (final match in legacyPath.allMatches(content)) {
      final decoded = _decodeVdfString(match.group(1)!);
      if (_looksLikeSteamLibraryPath(decoded)) paths.add(decoded);
    }

    return _uniquePaths(paths);
  }

  static bool isLikelyCs2CfgPath(String cfgPath) {
    if (!Directory(cfgPath).existsSync()) return false;
    final gameDir = Directory(cfgPath).parent.parent.path;
    return File(p.join(gameDir, 'bin', 'win64', 'cs2.exe')).existsSync() ||
        File(p.join(gameDir, 'bin', 'linuxsteamrt64', 'cs2')).existsSync();
  }

  static Future<String?> findSteamPath() async {
    if (Platform.isWindows) {
      for (final key in [
        r'HKLM\SOFTWARE\WOW6432Node\Valve\Steam',
        r'HKCU\Software\Valve\Steam',
      ]) {
        for (final valueName in ['InstallPath', 'SteamPath']) {
          final path = await _readWindowsRegistryString(key, valueName);
          if (path != null && Directory(path).existsSync()) return path;
        }
      }

      for (final path in [
        r'C:\Program Files (x86)\Steam',
        r'C:\Program Files\Steam',
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

  static Future<String?> _readWindowsRegistryString(
    String key,
    String valueName,
  ) async {
    try {
      final result = await Process.run('reg', ['query', key, '/v', valueName]);
      if (result.exitCode != 0) return null;
      final match = RegExp(
        '$valueName\\s+REG_SZ\\s+(.+)',
        caseSensitive: false,
      ).firstMatch(result.stdout as String);
      return match?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  static String _decodeVdfString(String value) {
    return value.replaceAll('\\\\', '\\').replaceAll(r'\"', '"');
  }

  static bool _looksLikeSteamLibraryPath(String value) {
    return value.contains(':\\') ||
        value.startsWith('/') ||
        value.contains('\\');
  }

  static List<String> _uniquePaths(Iterable<String> paths) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in paths) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final key = value.replaceAll('\\', '/').toLowerCase();
      if (seen.add(key)) result.add(value);
    }
    return result;
  }

  static Future<bool> installConfig() async {
    final cfgPath = await findCs2CfgPath();
    if (cfgPath == null) return false;
    final file = File(p.join(cfgPath, 'gamestate_integration_biobase.cfg'));
    await file.writeAsString(_gsiConfig);
    return true;
  }

  static Future<String?> findCs2Exe() async {
    final cfgPath = await findCs2CfgPath();
    if (cfgPath == null) return null;
    // cfg = .../game/csgo/cfg → up to game → bin/win64/cs2.exe
    final gameDir = Directory(cfgPath).parent.parent.path;
    final exePath = p.join(gameDir, 'bin', 'win64', 'cs2.exe');
    if (File(exePath).existsSync()) return exePath;
    return null;
  }

  static Future<String?> findCs2GameCsgoPath() async {
    final cfgPath = await findCs2CfgPath();
    if (cfgPath == null) return null;
    final csgoDir = Directory(cfgPath).parent.path;
    if (Directory(csgoDir).existsSync()) return csgoDir;
    return null;
  }

  static Future<bool> isConfigInstalled() async {
    final cfgPath = await findCs2CfgPath();
    if (cfgPath == null) return false;
    return File(
      p.join(cfgPath, 'gamestate_integration_biobase.cfg'),
    ).existsSync();
  }

  static Future<String?> _findSteamPath() => findSteamPath();

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
    final app730 = RegExp(r'"730"\s*\{');
    final match = app730.firstMatch(content);
    if (match == null) return null;

    final blockStart = match.end;

    var depth = 1;
    var blockEnd = blockStart;
    for (var i = blockStart; i < content.length && depth > 0; i++) {
      if (content[i] == '{') depth++;
      if (content[i] == '}') depth--;
      if (depth == 0) blockEnd = i;
    }

    final block = content.substring(blockStart, blockEnd);

    final launchMatch = RegExp(
      r'"LaunchOptions"\s+"([^"]*)"',
    ).firstMatch(block);

    if (launchMatch != null) {
      final existing = launchMatch.group(1)!;
      if (existing.contains('-netconport')) return null;
      final updated = '$existing -netconport 2121';
      final absStart = blockStart + launchMatch.start;
      final absEnd = blockStart + launchMatch.end;
      final original = content.substring(absStart, absEnd);
      final replaced = original.replaceFirst('"$existing"', '"$updated"');
      return content.substring(0, absStart) +
          replaced +
          content.substring(absEnd);
    }

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
