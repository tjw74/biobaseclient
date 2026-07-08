import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'gsi_service.dart';

/// CS2 in-game plugin integration (vendored from CS Demo Manager, MIT —
/// see assets/cs2_plugin/LICENSE-cs-demo-manager).
///
/// The plugin loads inside CS2 (requires -insecure) and gives BioBase two
/// superpowers:
///  1. It connects to a WebSocket server we host on port 4574, so we can tell
///     an ALREADY-RUNNING CS2 to play a demo — no kill-and-relaunch.
///  2. When CS2 plays `<demo>.dem`, the plugin executes the commands in
///     `<demo>.dem.json` at exact ticks (spec_player, demo_gototick, …) —
///     tick-accurate watch sequences.
class Cs2PluginService {
  Cs2PluginService._();
  static final Cs2PluginService instance = Cs2PluginService._();

  /// Must match DEFAULT_WEB_SOCKET_SERVER_PORT in the plugin's main.cpp.
  static const int wsPort = 4574;

  HttpServer? _server;
  WebSocket? _game;
  final _statusWaiters = <Completer<bool>>[];
  final _connectionController = StreamController<bool>.broadcast();

  bool get gameConnected => _game != null;
  Stream<bool> get onConnectionChanged => _connectionController.stream;

  // ── WebSocket server ──

  Future<bool> startServer() async {
    if (_server != null) return true;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        wsPort,
      );
      _server = server;
      server.listen(_handleRequest, onError: (_) {}, cancelOnError: false);
      return true;
    } catch (_) {
      // Port taken (CS Demo Manager running?) — plugin control unavailable,
      // callers fall back to the launch flow.
      return false;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final process = request.uri.queryParameters['process'];
    final socket = await WebSocketTransformer.upgrade(request);
    if (process != 'game') {
      // Only the game process is expected on this server.
      await socket.close();
      return;
    }
    _game?.close();
    _game = socket;
    _connectionController.add(true);
    socket.listen(
      (data) {
        try {
          final message = jsonDecode('$data') as Map<String, dynamic>;
          if (message['name'] == 'status') {
            for (final waiter in _statusWaiters) {
              if (!waiter.isCompleted) waiter.complete(true);
            }
            _statusWaiters.clear();
          }
        } catch (_) {}
      },
      onDone: () => _onGameGone(socket),
      onError: (_) => _onGameGone(socket),
      cancelOnError: true,
    );
  }

  void _onGameGone(WebSocket socket) {
    if (_game == socket) {
      _game = null;
      _connectionController.add(false);
    }
  }

  /// Tells the running CS2 to play a demo. Returns false when no plugin is
  /// connected or the game didn't acknowledge in time.
  Future<bool> playDemo(String demoPath) async {
    final game = _game;
    if (game == null) return false;
    final waiter = Completer<bool>();
    _statusWaiters.add(waiter);
    try {
      game.add(
        jsonEncode({
          'name': 'playdemo',
          'payload': demoPath.replaceAll('\\', '/'),
        }),
      );
      return await waiter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  // ── Plugin install (CSDM layout: game/csgo/csdm/bin/server.dll) ──

  Future<String?> _csgoDir() => GsiService.findCs2GameCsgoPath();

  Future<bool> get installed async {
    final csgo = await _csgoDir();
    if (csgo == null) return false;
    return File(p.join(csgo, 'csdm', 'bin', 'server.dll')).existsSync();
  }

  /// Installs the plugin binary and registers it in gameinfo.gi.
  /// Idempotent; backs up gameinfo.gi before the first patch.
  Future<bool> ensureInstalled() async {
    if (!Platform.isWindows) return false;
    try {
      final csgo = await _csgoDir();
      if (csgo == null) return false;

      final binDir = Directory(p.join(csgo, 'csdm', 'bin'));
      binDir.createSync(recursive: true);
      final dllFile = File(p.join(binDir.path, 'server.dll'));
      final asset = await rootBundle.load('assets/cs2_plugin/server.dll');
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      // Skip the write when identical (CS2 may have the dll mapped).
      if (!dllFile.existsSync() || dllFile.lengthSync() != bytes.length) {
        dllFile.writeAsBytesSync(bytes);
      }

      final gameInfo = File(p.join(csgo, 'gameinfo.gi'));
      if (!gameInfo.existsSync()) return false;
      final content = gameInfo.readAsStringSync();
      if (!content.contains('Game\tcsgo/csdm')) {
        File('${gameInfo.path}.backup').writeAsStringSync(content);
        gameInfo.writeAsStringSync(
          content.replaceFirst(
            'Game\tcsgo',
            'Game\tcsgo/csdm\n\t\t\tGame\tcsgo',
          ),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes the plugin and restores gameinfo.gi from backup.
  Future<void> uninstall() async {
    try {
      final csgo = await _csgoDir();
      if (csgo == null) return;
      final pluginDir = Directory(p.join(csgo, 'csdm'));
      if (pluginDir.existsSync()) pluginDir.deleteSync(recursive: true);
      final gameInfo = File(p.join(csgo, 'gameinfo.gi'));
      final backup = File('${gameInfo.path}.backup');
      if (backup.existsSync()) {
        gameInfo.writeAsStringSync(backup.readAsStringSync());
        backup.deleteSync();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _game?.close();
    _game = null;
    await _server?.close(force: true);
    _server = null;
  }
}
