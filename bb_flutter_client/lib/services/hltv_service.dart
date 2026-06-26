import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class HltvMatch {
  final String matchId;
  final String team1;
  final String team2;
  final int? score1;
  final int? score2;
  final String event;
  final bool hasDemos;
  final int? totalSize;

  const HltvMatch({
    required this.matchId,
    required this.team1,
    required this.team2,
    this.score1,
    this.score2,
    required this.event,
    required this.hasDemos,
    this.totalSize,
  });

  String get score => '${score1 ?? '–'}–${score2 ?? '–'}';
}

class HltvDemo {
  final int id;
  final String matchId;
  final String filename;
  final int sizeBytes;
  final String? mapName;
  final String team1;
  final String team2;
  final String event;
  String? localPath;

  HltvDemo({
    required this.id,
    required this.matchId,
    required this.filename,
    required this.sizeBytes,
    this.mapName,
    required this.team1,
    required this.team2,
    required this.event,
    this.localPath,
  });

  String get displayName {
    final parts = filename.split('_');
    if (parts.length >= 2) return parts.sublist(1).join('_').replaceAll('.dem', '');
    return filename.replaceAll('.dem', '');
  }
}

class HltvService {
  String _apiBase = 'http://localhost:8790';

  void configure({required String apiBase}) {
    _apiBase = apiBase.endsWith('/') ? apiBase.substring(0, apiBase.length - 1) : apiBase;
  }

  String get _demosDir {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return p.join(appData, 'BioBase', 'demos');
  }

  Future<List<HltvMatch>> fetchMatches({int limit = 50}) async {
    final resp = await http.get(
      Uri.parse('$_apiBase/api/matches?limit=$limit'),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];

    final List<dynamic> data = json.decode(resp.body);
    return data.map((m) => HltvMatch(
      matchId: m['match_id'] as String,
      team1: m['team1'] as String? ?? '',
      team2: m['team2'] as String? ?? '',
      score1: m['score1'] as int?,
      score2: m['score2'] as int?,
      event: m['event'] as String? ?? '',
      hasDemos: m['demo_files'] != null,
      totalSize: m['total_size'] as int?,
    )).toList();
  }

  Future<List<HltvDemo>> fetchDemos({int limit = 200}) async {
    final resp = await http.get(
      Uri.parse('$_apiBase/api/demos?limit=$limit'),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];

    final List<dynamic> data = json.decode(resp.body);
    final demos = data.map((d) => HltvDemo(
      id: d['id'] as int,
      matchId: d['match_id'] as String,
      filename: d['filename'] as String,
      sizeBytes: d['size_bytes'] as int,
      mapName: d['map_name'] as String?,
      team1: d['team1'] as String? ?? '',
      team2: d['team2'] as String? ?? '',
      event: d['event'] as String? ?? '',
    )).toList();

    final dir = Directory(_demosDir);
    if (dir.existsSync()) {
      final localFiles = dir.listSync().whereType<File>().map((f) => p.basename(f.path)).toSet();
      for (final demo in demos) {
        if (localFiles.contains(demo.filename)) {
          demo.localPath = p.join(_demosDir, demo.filename);
        }
      }
    }
    return demos;
  }

  Future<String> downloadDemo(
    HltvDemo demo, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = Directory(_demosDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final outPath = p.join(_demosDir, demo.filename);
    final outFile = File(outPath);
    if (outFile.existsSync()) return outPath;

    final request = http.Request('GET', Uri.parse('$_apiBase/api/demos/${demo.id}/download'));
    final streamResp = await http.Client().send(request);

    if (streamResp.statusCode != 200) {
      throw Exception('Download failed (${streamResp.statusCode})');
    }

    final total = streamResp.contentLength ?? demo.sizeBytes;
    final sink = outFile.openWrite();
    int received = 0;

    await for (final chunk in streamResp.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();

    demo.localPath = outPath;
    return outPath;
  }

  List<String> listLocalDemos() {
    final dir = Directory(_demosDir);
    if (!dir.existsSync()) return [];
    return dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dem'))
        .map((f) => f.path)
        .toList();
  }
}
