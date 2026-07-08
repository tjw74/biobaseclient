import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'gsi_service.dart';
import 'native_demo_service.dart';

/// Renders a marked move to MP4: an actions sequence makes CS2 record the
/// span with its built-in startmovie (TGA frames + WAV, landing in the
/// plugin's movie folder), then FFmpeg assembles the clip.
class VideoExportService {
  VideoExportService._();
  static final VideoExportService instance = VideoExportService._();

  static const int framerate = 60;
  static const String _ffmpegZipUrl =
      'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';

  bool exporting = false;

  Directory get _exportDir {
    final appData =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '';
    return Directory(p.join(appData, 'BioBase', 'exports'));
  }

  Directory get _toolsDir {
    final appData =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '';
    return Directory(p.join(appData, 'BioBase', 'tools', 'ffmpeg'));
  }

  /// Writes the recording actions file for a move. The caller plays the
  /// staged demo afterwards (plugin executes the sequence); recording output
  /// is collected by [collectAndEncode].
  Future<void> writeRecordingActions({
    required String stagedDemoPath,
    required NativeDemo demo,
    required int startTick,
    required int endTick,
    required String sequenceName,
    String? focusPlayerName,
  }) async {
    final rate = demo.tickRateGuess <= 0 ? 64 : demo.tickRateGuess;
    final g = ActionsFileBuilder(stagedDemoPath);
    final entry = demo.startTick + rate;
    final lead = (2 * rate).round();
    final target = (startTick - lead).clamp(demo.startTick, demo.endTick);
    g.goto(entry, target);
    if (focusPlayerName != null) g.spec(target, focusPlayerName);
    g.exec(target, 'host_framerate $framerate');
    g.exec(startTick, 'startmovie $sequenceName');
    g.exec(endTick, 'endmovie');
    g.exec(endTick + rate, 'host_framerate 0');
    g.exec(endTick + rate * 2, 'disconnect');
    await g.write();
  }

  /// Waits for CS2 to finish dumping frames, then encodes the newest movie
  /// take to MP4. Returns the output path.
  Future<String> collectAndEncode({
    required String outputName,
    void Function(String status)? onStatus,
  }) async {
    final csgo = await GsiService.findCs2GameCsgoPath();
    if (csgo == null) throw Exception('CS2 folder not found');
    final pluginMovie = Directory(p.join(csgo, 'csdm', 'movie'));
    final gameMovie = Directory(p.join(csgo, 'movie'));

    onStatus?.call('Waiting for CS2 to finish recording…');
    final takeDir = await _waitForStableTake(pluginMovie);
    if (takeDir == null) {
      throw Exception('No recording appeared — did the demo play?');
    }

    onStatus?.call('Encoding with FFmpeg…');
    final ffmpeg = await _ensureFfmpeg(onStatus);
    final tgas =
        takeDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.tga'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (tgas.isEmpty) throw Exception('Recording produced no frames');

    // Normalize frame names so FFmpeg's image2 sequence input works
    // regardless of CS2's naming.
    for (var i = 0; i < tgas.length; i++) {
      final target = p.join(
        takeDir.path,
        'bbframe_${i.toString().padLeft(6, '0')}.tga',
      );
      if (tgas[i].path != target) tgas[i].renameSync(target);
    }

    File? wav;
    if (gameMovie.existsSync()) {
      final wavs =
          gameMovie
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.wav'))
              .toList()
            ..sort(
              (a, b) =>
                  b.statSync().modified.compareTo(a.statSync().modified),
            );
      if (wavs.isNotEmpty) wav = wavs.first;
    }

    _exportDir.createSync(recursive: true);
    final outPath = p.join(_exportDir.path, '$outputName.mp4');
    final args = <String>[
      '-y',
      '-framerate',
      '$framerate',
      '-i',
      p.join(takeDir.path, 'bbframe_%06d.tga'),
      if (wav != null) ...['-i', wav.path],
      '-c:v',
      'libx264',
      '-crf',
      '20',
      '-pix_fmt',
      'yuv420p',
      if (wav != null) ...['-c:a', 'aac', '-shortest'],
      outPath,
    ];
    final result = await Process.run(
      ffmpeg,
      args,
    ).timeout(const Duration(minutes: 10));
    if (result.exitCode != 0 || !File(outPath).existsSync()) {
      final err = '${result.stderr}';
      throw Exception(
        'FFmpeg failed: ${err.length > 300 ? err.substring(0, 300) : err}',
      );
    }

    // Raw takes are gigabytes — clean up.
    try {
      takeDir.deleteSync(recursive: true);
      if (gameMovie.existsSync()) gameMovie.deleteSync(recursive: true);
    } catch (_) {}
    onStatus?.call('Saved ${p.basename(outPath)}');
    return outPath;
  }

  /// A take is done when its newest file stops growing for several seconds.
  Future<Directory?> _waitForStableTake(Directory movieRoot) async {
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    Directory? take;
    var lastCount = -1;
    var stableFor = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 3));
      if (!movieRoot.existsSync()) continue;
      final takes =
          movieRoot.listSync().whereType<Directory>().toList()..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
      if (takes.isEmpty) continue;
      take = takes.first;
      final count = take
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.tga'))
          .length;
      if (count > 0 && count == lastCount) {
        stableFor += 3;
        if (stableFor >= 9) return take;
      } else {
        stableFor = 0;
        lastCount = count;
      }
    }
    return take;
  }

  Future<String> _ensureFfmpeg(void Function(String)? onStatus) async {
    // PATH first
    try {
      final probe = await Process.run('ffmpeg', ['-version']);
      if (probe.exitCode == 0) return 'ffmpeg';
    } catch (_) {}

    final local = File(p.join(_toolsDir.path, 'ffmpeg.exe'));
    if (local.existsSync()) return local.path;

    onStatus?.call('Downloading FFmpeg (one time, ~150 MB)…');
    final response = await http.get(Uri.parse(_ffmpegZipUrl));
    if (response.statusCode != 200) {
      throw Exception('FFmpeg download failed: HTTP ${response.statusCode}');
    }
    final archive = ZipDecoder().decodeBytes(response.bodyBytes);
    for (final entry in archive) {
      if (entry.isFile && entry.name.endsWith('bin/ffmpeg.exe')) {
        _toolsDir.createSync(recursive: true);
        local.writeAsBytesSync(entry.content as List<int>);
        return local.path;
      }
    }
    throw Exception('ffmpeg.exe not found in archive');
  }
}

/// Small builder mirroring the plugin's actions format, with exec support.
class ActionsFileBuilder {
  final String stagedDemoPath;
  final List<Map<String, Object>> _actions = [];

  ActionsFileBuilder(this.stagedDemoPath);

  void _add(int tick, String cmd) =>
      _actions.add({'cmd': cmd, 'tick': tick < 0 ? 0 : tick});

  void goto(int atTick, int toTick) => _add(atTick, 'demo_gototick $toTick');

  void spec(int tick, String name) {
    _add(tick, 'spec_mode 1');
    _add(tick, 'spec_player "${name.replaceAll('"', '')}"');
  }

  void exec(int tick, String cmd) => _add(tick, cmd);

  Future<void> write() async {
    final file = File('$stagedDemoPath.json');
    file.writeAsStringSync(
      '[{"actions":${_encodeActions()}}]',
    );
  }

  String _encodeActions() {
    final parts = <String>[];
    for (final a in _actions) {
      final cmd = (a['cmd'] as String).replaceAll('"', r'\"');
      parts.add('{"cmd":"$cmd","tick":${a['tick']}}');
    }
    return '[${parts.join(',')}]';
  }
}
