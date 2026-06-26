import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class HltvMatch {
  final String matchId;
  final String slug;
  final String team1;
  final String team2;
  final String score;
  final String event;

  const HltvMatch({
    required this.matchId,
    required this.slug,
    required this.team1,
    required this.team2,
    required this.score,
    required this.event,
  });
}

class HltvDemo {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime downloaded;

  const HltvDemo({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.downloaded,
  });
}

enum HltvDownloadState { idle, fetching, downloading, extracting, done, error }

class HltvService {
  static const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  String get _demosDir {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return p.join(appData, 'BioBase', 'demos');
  }

  Future<List<HltvMatch>> fetchRecentMatches() async {
    final resp = await http.get(
      Uri.parse('https://www.hltv.org/results'),
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];

    final html = resp.body;
    final matches = <HltvMatch>[];
    final blockPattern = RegExp(
      r'<div class="result-con"[^>]*>\s*<a href="/matches/(\d+)/([^"]+)"',
    );

    for (final m in blockPattern.allMatches(html)) {
      final matchId = m.group(1)!;
      final slug = m.group(2)!;
      final blockStart = m.start;
      final blockEnd = html.indexOf('</a>', blockStart);
      if (blockEnd < 0) continue;
      final block = html.substring(blockStart, blockEnd);

      final teams = RegExp(r'class="team"[^>]*>\s*([^<]+)<')
          .allMatches(block)
          .map((t) => t.group(1)!.trim())
          .toList();
      final scores = RegExp(r'class="score[^"]*"[^>]*>\s*(\d+)\s*<')
          .allMatches(block)
          .map((s) => s.group(1)!)
          .toList();
      final eventMatch = RegExp(r'class="event-name"[^>]*>\s*([^<]+)<')
          .firstMatch(block);

      String team1, team2, score;
      if (teams.length >= 2) {
        team1 = teams[0];
        team2 = teams[1];
      } else {
        final parts = slug.split('-vs-');
        if (parts.length < 2) continue;
        team1 = parts[0].replaceAll('-', ' ');
        team2 = parts[1].split('-').take(2).join(' ');
      }
      score = scores.length >= 2 ? '${scores[0]}–${scores[1]}' : '';
      final event = eventMatch?.group(1)?.trim() ?? '';

      matches.add(HltvMatch(
        matchId: matchId,
        slug: slug,
        team1: team1,
        team2: team2,
        score: score,
        event: event,
      ));
      if (matches.length >= 25) break;
    }
    return matches;
  }

  List<HltvDemo> listDownloaded() {
    final dir = Directory(_demosDir);
    if (!dir.existsSync()) return [];
    final demos = <HltvDemo>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dem')) continue;
      final stat = f.statSync();
      demos.add(HltvDemo(
        name: p.basename(f.path),
        path: f.path,
        sizeBytes: stat.size,
        downloaded: stat.modified,
      ));
    }
    demos.sort((a, b) => b.downloaded.compareTo(a.downloaded));
    return demos;
  }

  String? parseMatchId(String input) {
    input = input.trim();
    final matchUrl = RegExp(r'hltv\.org/matches/(\d+)');
    final m = matchUrl.firstMatch(input);
    if (m != null) return m.group(1);
    if (RegExp(r'^\d+$').hasMatch(input)) return input;
    return null;
  }

  Future<String?> _findDemoId(String matchId) async {
    final url = 'https://www.hltv.org/matches/$matchId';
    final resp = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final pattern = RegExp(r'"/download/demo/(\d+)"');
    final m = pattern.firstMatch(resp.body);
    return m?.group(1);
  }

  Future<HltvDemo> downloadDemo(
    String matchId, {
    void Function(HltvDownloadState state, String message)? onProgress,
  }) async {
    onProgress?.call(HltvDownloadState.fetching, 'Finding demo link...');

    final demoId = await _findDemoId(matchId);
    if (demoId == null) {
      throw Exception('No demo found for match $matchId');
    }

    onProgress?.call(HltvDownloadState.downloading, 'Downloading demo...');

    final downloadUrl = 'https://www.hltv.org/download/demo/$demoId';
    final request = http.Request('GET', Uri.parse(downloadUrl));
    request.headers['User-Agent'] = _userAgent;
    final streamResp = await http.Client().send(request);

    if (streamResp.statusCode != 200 && streamResp.statusCode != 302) {
      throw Exception('Download failed (${streamResp.statusCode})');
    }

    final bytes = await streamResp.stream.toBytes();

    onProgress?.call(HltvDownloadState.extracting, 'Extracting demo...');

    final dir = Directory(_demosDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final demFiles = <File>[];

    if (_isZip(bytes)) {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile && file.name.endsWith('.dem')) {
          final outPath = p.join(_demosDir, p.basename(file.name));
          final outFile = File(outPath);
          await outFile.writeAsBytes(file.content as List<int>);
          demFiles.add(outFile);
        }
      }
    } else if (_isGzip(bytes)) {
      final decompressed = GZipDecoder().decodeBytes(bytes);
      final outPath = p.join(_demosDir, 'hltv_$demoId.dem');
      final outFile = File(outPath);
      await outFile.writeAsBytes(decompressed);
      demFiles.add(outFile);
    } else {
      final outPath = p.join(_demosDir, 'hltv_$demoId.dem.rar');
      final outFile = File(outPath);
      await outFile.writeAsBytes(bytes);

      final extracted = await _extractRar(outFile.path, _demosDir);
      if (extracted) {
        await outFile.delete();
        for (final f in Directory(_demosDir).listSync().whereType<File>()) {
          if (f.path.endsWith('.dem')) {
            final stat = f.statSync();
            if (DateTime.now().difference(stat.modified).inSeconds < 30) {
              demFiles.add(f);
            }
          }
        }
      } else {
        throw Exception('Cannot extract .rar — install 7-Zip or WinRAR');
      }
    }

    if (demFiles.isEmpty) {
      throw Exception('No .dem files found in archive');
    }

    final primary = demFiles.first;
    final stat = primary.statSync();

    onProgress?.call(HltvDownloadState.done, p.basename(primary.path));

    return HltvDemo(
      name: p.basename(primary.path),
      path: primary.path,
      sizeBytes: stat.size,
      downloaded: DateTime.now(),
    );
  }

  bool _isZip(Uint8List bytes) =>
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  bool _isGzip(Uint8List bytes) =>
      bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;

  Future<bool> _extractRar(String rarPath, String outDir) async {
    for (final exe in ['7z', '7za', 'unrar']) {
      try {
        final result = await Process.run(
          exe,
          exe.startsWith('7z')
              ? ['x', '-o$outDir', '-y', rarPath]
              : ['x', '-o+', rarPath, outDir],
        );
        if (result.exitCode == 0) return true;
      } catch (_) {}
    }
    if (Platform.isWindows) {
      for (final path in [
        r'C:\Program Files\7-Zip\7z.exe',
        r'C:\Program Files (x86)\7-Zip\7z.exe',
      ]) {
        if (File(path).existsSync()) {
          final result = await Process.run(path, ['x', '-o$outDir', '-y', rarPath]);
          if (result.exitCode == 0) return true;
        }
      }
    }
    return false;
  }
}
