import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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
  final int dashboardPort;
  final String serverName;
  final String map;
  final int maxPlayers;

  const ServerInfo({
    required this.installDir,
    required this.rconPassword,
    required this.dashboardPassword,
    this.gamePort = 27015,
    this.dashboardPort = 8780,
    this.serverName = 'BioBase CS2',
    this.map = 'de_mirage',
    this.maxPlayers = 16,
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
        ['compose', '-f', _composeFile, 'ps', '--format', 'json'],
        stdoutEncoding: utf8,
      );
      if (result.exitCode != 0) return ServerRunState.stopped;
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return ServerRunState.stopped;

      final lines = output.split('\n');
      var running = 0;
      var total = 0;
      for (final line in lines) {
        try {
          final c = jsonDecode(line) as Map<String, dynamic>;
          total++;
          if (c['State'] == 'running') running++;
        } catch (_) {}
      }
      if (total == 0) return ServerRunState.stopped;
      if (running == total) return ServerRunState.running;
      if (running > 0) return ServerRunState.partial;
      return ServerRunState.stopped;
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
    );
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
