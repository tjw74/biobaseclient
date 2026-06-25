import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

const _installerRelease =
    'https://github.com/tjw74/biobaseserver_cs2/releases/download/v1.0.0/BioBase_CS2_Server_Setup.exe';

enum ServerInstallState { notInstalled, downloading, installing, installed, error }

enum ServerRunState { unknown, running, stopped, partial }

class InstallProgress {
  final String id;
  final String status;
  final String message;
  const InstallProgress({
    required this.id,
    required this.status,
    required this.message,
  });
}

class ServerInfo {
  final String installDir;
  final String rconPassword;
  final String dashboardPassword;
  final int gamePort;
  final int controlPort;
  final int dashboardPort;
  final String serverName;
  final String map;
  final int maxPlayers;
  final String controlToken;

  const ServerInfo({
    required this.installDir,
    required this.rconPassword,
    required this.dashboardPassword,
    this.gamePort = 27015,
    this.controlPort = 8765,
    this.dashboardPort = 8780,
    this.serverName = 'BioBase CS2',
    this.map = 'de_mirage',
    this.maxPlayers = 16,
    this.controlToken = '',
  });
}

class ServerPlayer {
  final int userid;
  final String name;
  final bool isBot;
  final String? connected;
  final int ping;

  const ServerPlayer({
    required this.userid,
    required this.name,
    required this.isBot,
    this.connected,
    this.ping = 0,
  });
}

class GameStatus {
  final String headline;
  final int humans;
  final int bots;
  final String? map;
  final String? hostname;
  final bool rconOk;
  final List<ServerPlayer> players;

  const GameStatus({
    required this.headline,
    this.humans = 0,
    this.bots = 0,
    this.map,
    this.hostname,
    this.rconOk = false,
    this.players = const [],
  });
}

class ServerCapabilities {
  final String cheatsState;
  final String? serverProfile;
  final Map<String, String> plugins;
  final GameStatus? status;

  const ServerCapabilities({
    this.cheatsState = 'unknown',
    this.serverProfile,
    this.plugins = const {},
    this.status,
  });
}

class DemoFile {
  final String name;
  final int sizeBytes;
  final DateTime modified;

  const DemoFile({
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });
}

const _demoContainerDir =
    '/home/steam/cs2-dedicated/game/csgo/MatchZy';
const _containerName = 'bb_cs2_server';

const _defaultControlPort = 8765;

const stockMaps = [
  'de_mirage',
  'de_dust2',
  'de_inferno',
  'de_nuke',
  'de_overpass',
  'de_ancient',
  'de_anubis',
  'de_vertigo',
  'cs_office',
  'cs_italy',
];

class ServerService {
  String get _installDir {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return p.join(home, 'BioBase', 'CS2Server');
  }

  String get _composeFile =>
      p.join(_installDir, 'bb_cs2_server', 'docker-compose.yml');

  String get _envFile => p.join(_installDir, 'bb_cs2_server', '.env');

  String get _installerDir {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        '';
    return p.join(appData, 'BioBase', 'server-installer');
  }

  String get _installerPath =>
      p.join(_installerDir, 'BioBase_CS2_Server_Setup.exe');

  bool get isInstalled => File(_composeFile).existsSync();

  bool get installerReady => File(_installerPath).existsSync();

  String _controlBaseUrl(ServerInfo? info) {
    final port = info?.controlPort ?? _defaultControlPort;
    return 'http://localhost:$port';
  }

  Map<String, String> _authHeaders(ServerInfo? info) {
    final token = info?.controlToken ?? '';
    if (token.isEmpty) return {'Content-Type': 'application/json'};
    return {
      'Content-Type': 'application/json',
      'X-Api-Key': token,
    };
  }

  Future<void> downloadInstaller({
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = Directory(_installerDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final request = http.Request('GET', Uri.parse(_installerRelease));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) throw Exception('Download failed (${response.statusCode})');

    final total = response.contentLength ?? -1;
    var received = 0;
    final sink = File(_installerPath).openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();
  }

  Stream<InstallProgress> install() async* {
    if (!installerReady) {
      yield const InstallProgress(
        id: 'download',
        status: 'start',
        message: 'Downloading installer...',
      );
      await downloadInstaller();
      yield const InstallProgress(
        id: 'download',
        status: 'done',
        message: 'Downloaded',
      );
    }

    final process = await Process.start(
      _installerPath,
      ['--json'],
      mode: ProcessStartMode.normal,
    );

    await for (final line in process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      try {
        final data = jsonDecode(line) as Map<String, dynamic>;
        yield InstallProgress(
          id: data['id'] as String? ?? data['type'] as String? ?? '',
          status: data['status'] as String? ?? data['type'] as String? ?? '',
          message: data['message'] as String? ?? '',
        );
      } catch (_) {}
    }

    await process.exitCode;
  }

  Future<ServerRunState> getRunState() async {
    if (!isInstalled) return ServerRunState.unknown;
    try {
      final result = await Process.run(
        'docker',
        [
          'inspect', '--format', '{{.State.Running}}',
          'bb_cs2_server', 'bb_cs2_control', 'bb_cs2_dashboard',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final lines = (result.stdout as String)
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) return ServerRunState.stopped;
      final running = lines.where((l) => l.trim() == 'true').length;
      if (running == 0) return ServerRunState.stopped;
      if (running == lines.length) return ServerRunState.running;
      return ServerRunState.partial;
    } catch (_) {
      return ServerRunState.unknown;
    }
  }

  Future<void> start() async {
    await Process.run(
      'docker',
      ['compose', '-f', _composeFile, 'up', '-d'],
    );
  }

  Future<void> stop() async {
    await Process.run(
      'docker',
      ['compose', '-f', _composeFile, 'down'],
    );
  }

  Future<void> restart() async {
    await Process.run(
      'docker',
      ['compose', '-f', _composeFile, 'restart'],
    );
  }

  ServerInfo? readServerInfo() {
    final file = File(_envFile);
    if (!file.existsSync()) return null;
    final env = _parseEnv(file.readAsStringSync());
    return ServerInfo(
      installDir: _installDir,
      rconPassword: env['CS2_RCONPW'] ?? '',
      dashboardPassword: env['BB_CS2_DASHBOARD_TOKEN'] ?? '',
      serverName: env['CS2_SERVERNAME'] ?? 'BioBase CS2',
      map: env['CS2_STARTMAP'] ?? 'de_mirage',
      maxPlayers: int.tryParse(env['CS2_MAXPLAYERS'] ?? '') ?? 16,
      controlPort: int.tryParse(env['BB_CS2_CONTROL_PORT'] ?? '') ?? _defaultControlPort,
      controlToken: env['BB_CS2_CONTROL_TOKEN'] ?? '',
    );
  }

  Future<GameStatus> fetchGameStatus(ServerInfo? info) async {
    try {
      final resp = await http.get(
        Uri.parse('${_controlBaseUrl(info)}/api/status'),
        headers: _authHeaders(info),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        return const GameStatus(headline: 'API unreachable');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final playerList = <ServerPlayer>[];
      if (data['players'] is List) {
        for (final p in data['players'] as List) {
          if (p is! Map<String, dynamic>) continue;
          playerList.add(ServerPlayer(
            userid: p['userid'] as int? ?? 0,
            name: p['name'] as String? ?? '',
            isBot: p['steamid'] == 'BOT',
            connected: p['connected'] as String?,
            ping: p['ping'] as int? ?? 0,
          ));
        }
      }
      return GameStatus(
        headline: data['headline'] as String? ?? '',
        humans: data['humans'] as int? ?? 0,
        bots: data['bots'] as int? ?? 0,
        map: data['map'] as String?,
        hostname: data['hostname'] as String?,
        rconOk: data['rcon_ok'] as bool? ?? false,
        players: playerList,
      );
    } catch (_) {
      return const GameStatus(headline: 'API unreachable');
    }
  }

  Future<ServerCapabilities> fetchCapabilities(ServerInfo? info) async {
    try {
      final resp = await http.get(
        Uri.parse('${_controlBaseUrl(info)}/api/capabilities'),
        headers: _authHeaders(info),
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        return const ServerCapabilities();
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      final cheats = data['cheats'] as Map<String, dynamic>?;
      final cheatsState = cheats?['state'] as String? ?? 'unknown';

      final profile = data['server_profile'] as Map<String, dynamic>?;
      final profileValue = profile?['value'] as String?;

      final pluginsRaw = data['plugins'] as Map<String, dynamic>?;
      final plugins = <String, String>{};
      if (pluginsRaw != null) {
        for (final entry in pluginsRaw.entries) {
          final val = entry.value as Map<String, dynamic>?;
          plugins[entry.key] = val?['state'] as String? ?? 'unknown';
        }
      }

      final rcon = data['rcon'] as Map<String, dynamic>?;
      final statusBlock = rcon?['status'] as Map<String, dynamic>?;
      GameStatus? gameStatus;
      if (statusBlock != null) {
        gameStatus = GameStatus(
          headline: statusBlock['headline'] as String? ?? '',
          humans: statusBlock['humans'] as int? ?? 0,
          bots: statusBlock['bots'] as int? ?? 0,
          map: statusBlock['map'] as String?,
          hostname: statusBlock['hostname'] as String?,
          rconOk: statusBlock['ok'] as bool? ?? false,
        );
      }

      return ServerCapabilities(
        cheatsState: cheatsState,
        serverProfile: profileValue,
        plugins: plugins,
        status: gameStatus,
      );
    } catch (_) {
      return const ServerCapabilities();
    }
  }

  Future<bool> startBots(ServerInfo? info) async {
    try {
      final resp = await http.post(
        Uri.parse('${_controlBaseUrl(info)}/api/bots/start'),
        headers: _authHeaders(info),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopBots(ServerInfo? info) async {
    try {
      final resp = await http.post(
        Uri.parse('${_controlBaseUrl(info)}/api/bots/stop'),
        headers: _authHeaders(info),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changeMap(ServerInfo? info, String mapName) async {
    try {
      final resp = await http.post(
        Uri.parse('${_controlBaseUrl(info)}/api/map'),
        headers: _authHeaders(info),
        body: jsonEncode({'map': mapName}),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<(bool, String)> sendRcon(ServerInfo? info, String command) async {
    try {
      final resp = await http.post(
        Uri.parse('${_controlBaseUrl(info)}/api/rcon'),
        headers: _authHeaders(info),
        body: jsonEncode({'command': command}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final ok = data['ok'] as bool? ?? false;
      final output = data['output'] as String? ?? '';
      return (ok, output);
    } catch (e) {
      return (false, e.toString());
    }
  }

  Future<bool> setCheats(ServerInfo? info, bool enabled) async {
    final (ok, _) = await sendRcon(info, 'sv_cheats ${enabled ? 1 : 0}');
    return ok;
  }

  Future<void> connectToServer(String address) async {
    final uri = Uri.parse('steam://connect/$address');
    await launchUrl(uri);
  }

  Future<List<DemoFile>> listDemos() async {
    try {
      final result = await Process.run(
        'docker',
        [
          'exec', _containerName,
          'find', _demoContainerDir,
          '-name', '*.dem',
          '-printf', r'%f\t%s\t%T@\n',
        ],
        stdoutEncoding: utf8,
      );
      if (result.exitCode != 0) return [];
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return [];

      final demos = <DemoFile>[];
      for (final line in output.split('\n')) {
        final parts = line.split('\t');
        if (parts.length < 3) continue;
        demos.add(DemoFile(
          name: parts[0],
          sizeBytes: int.tryParse(parts[1]) ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch(
            ((double.tryParse(parts[2]) ?? 0) * 1000).toInt(),
          ),
        ));
      }
      demos.sort((a, b) => b.modified.compareTo(a.modified));
      return demos;
    } catch (_) {
      return [];
    }
  }

  Future<String?> copyDemoToLocal(String demoName) async {
    final tempDir = p.join(
      Platform.environment['TEMP'] ??
          Platform.environment['TMPDIR'] ??
          Directory.systemTemp.path,
      'biobase_demos',
    );
    final dir = Directory(tempDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final localPath = p.join(tempDir, demoName);
    if (File(localPath).existsSync()) return localPath;

    final result = await Process.run(
      'docker',
      ['cp', '$_containerName:$_demoContainerDir/$demoName', localPath],
    );
    if (result.exitCode != 0) return null;
    return localPath;
  }

  Map<String, String> _parseEnv(String content) {
    final env = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf('=');
      if (idx > 0) {
        env[trimmed.substring(0, idx)] = trimmed.substring(idx + 1);
      }
    }
    return env;
  }
}
