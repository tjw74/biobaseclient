import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// One of the user's own matchmaking matches, from the Steam Game
/// Coordinator. The demo link points at Valve's replay servers (.dem.bz2)
/// and expires after ~30 days.
class MmMatch {
  final String matchId;
  final DateTime? playedAt;
  final String demoUrl;

  const MmMatch({
    required this.matchId,
    required this.playedAt,
    required this.demoUrl,
  });

  String get fileName {
    final stamp = playedAt != null
        ? '${playedAt!.year}-${playedAt!.month.toString().padLeft(2, '0')}-${playedAt!.day.toString().padLeft(2, '0')}'
        : 'match';
    return 'mm_${stamp}_$matchId.dem';
  }
}

/// Fetches the user's own matchmaking demos through boiler-writter
/// (vendored from akiver/boiler-writter, MIT — license bundled), which asks
/// the CS2 Game Coordinator for the match history via the running Steam
/// client, then parses the protobuf match list and downloads .dem.bz2
/// replays from Valve's servers.
class BoilerService {
  BoilerService._();
  static final BoilerService instance = BoilerService._();

  static const _exitMessages = <int, String>{
    1: 'Unknown boiler error',
    2: 'Invalid arguments',
    3: 'Steam communication failure',
    4: 'Another app is using the CS2 Game Coordinator — close it and retry',
    5: 'Steam restart required',
    6: 'Steam is not running or not logged in',
    7: 'Not logged into Steam',
    8: 'No recent matchmaking matches found',
    9: 'Could not write matches file',
  };

  Directory get _toolsDir {
    final appData =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '';
    return Directory(p.join(appData, 'BioBase', 'tools', 'boiler'));
  }

  Directory get demosDir {
    final appData =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '';
    return Directory(p.join(appData, 'BioBase', 'demos', 'mm'));
  }

  Future<String> _ensureExtracted() async {
    final dir = _toolsDir;
    dir.createSync(recursive: true);
    for (final asset in [
      'boiler-writter.exe',
      'steam_api64.dll',
      'steam_appid.txt',
    ]) {
      final file = File(p.join(dir.path, asset));
      if (!file.existsSync()) {
        final data = await rootBundle.load('assets/boiler/$asset');
        file.writeAsBytesSync(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
    }
    return p.join(dir.path, 'boiler-writter.exe');
  }

  /// Asks the Game Coordinator for the user's recent matches. Steam must be
  /// running and logged in; CS2 must not be using the GC (we close it).
  Future<List<MmMatch>> fetchMatches() async {
    if (!Platform.isWindows) {
      throw Exception('Matchmaking downloads are Windows-only');
    }
    final exe = await _ensureExtracted();
    final outFile = p.join(_toolsDir.path, 'matches.info');
    try {
      final f = File(outFile);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}

    // The GC allows one connected client — a running CS2 would block boiler.
    try {
      final check = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq cs2.exe',
        '/NH',
      ]);
      if ((check.stdout as String).contains('cs2.exe')) {
        await Process.run('taskkill', ['/F', '/IM', 'cs2.exe']);
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (_) {}

    final result = await Process.run(
      exe,
      [outFile],
    ).timeout(const Duration(minutes: 2));
    if (result.exitCode != 0) {
      throw Exception(
        _exitMessages[result.exitCode] ??
            'boiler failed (${result.exitCode})',
      );
    }
    final bytes = File(outFile).readAsBytesSync();
    final matches = _parseMatchList(bytes);
    matches.sort(
      (a, b) => (b.playedAt ?? DateTime(2000)).compareTo(
        a.playedAt ?? DateTime(2000),
      ),
    );
    return matches;
  }

  /// Downloads and decompresses one match's demo. Returns the local path.
  Future<String> downloadDemo(
    MmMatch match, {
    void Function(double progress)? onProgress,
  }) async {
    demosDir.createSync(recursive: true);
    final outPath = p.join(demosDir.path, match.fileName);
    final out = File(outPath);
    if (out.existsSync() && out.lengthSync() > 1024 * 1024) return outPath;

    final request = http.Request('GET', Uri.parse(match.demoUrl));
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception(
        response.statusCode == 404
            ? 'Demo link expired (Valve keeps replays ~30 days)'
            : 'Download failed: HTTP ${response.statusCode}',
      );
    }
    final total = response.contentLength ?? 0;
    final compressed = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream) {
      compressed.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total * 0.8);
    }
    final demoBytes = BZip2Decoder().decodeBytes(compressed.takeBytes());
    onProgress?.call(0.95);
    out.writeAsBytesSync(demoBytes);
    onProgress?.call(1);
    return outPath;
  }

  // ── Minimal protobuf wire-format walker ──
  //
  // We only need matchid, matchtime, and the replay URL from
  // CMsgGCCStrike15_v2_MatchList, so instead of generated protobuf code we
  // walk the wire format: top-level repeated messages are matches; inside a
  // match, field 1 varint = matchid, field 2 varint = matchtime, and the
  // demo URL is the string field starting with "http" found in the last
  // round-stats submessage.

  List<MmMatch> _parseMatchList(Uint8List bytes) {
    final matches = <MmMatch>[];
    for (final field in _fields(bytes)) {
      if (field.wireType != 2 || field.bytes == null) continue;
      final match = _tryParseMatch(field.bytes!);
      if (match != null) matches.add(match);
    }
    return matches;
  }

  MmMatch? _tryParseMatch(Uint8List bytes) {
    BigInt? matchId;
    int? matchTime;
    String? demoUrl;
    try {
      for (final field in _fields(bytes)) {
        if (field.number == 1 && field.wireType == 0) {
          matchId = field.varint;
        } else if (field.number == 2 && field.wireType == 0) {
          matchTime = field.varint?.toInt();
        } else if (field.wireType == 2 && field.bytes != null) {
          // Any submessage may hold round stats; the last URL wins (the
          // final round-stats message carries the downloadable demo URL).
          final url = _findHttpString(field.bytes!, depth: 0);
          if (url != null) demoUrl = url;
        }
      }
    } catch (_) {
      return null;
    }
    if (matchId == null || demoUrl == null) return null;
    return MmMatch(
      matchId: matchId.toString(),
      playedAt: matchTime != null && matchTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(matchTime * 1000)
          : null,
      demoUrl: demoUrl,
    );
  }

  String? _findHttpString(Uint8List bytes, {required int depth}) {
    if (depth > 4) return null;
    String? found;
    try {
      for (final field in _fields(bytes)) {
        if (field.wireType != 2 || field.bytes == null) continue;
        final data = field.bytes!;
        if (data.length > 12 && data.length < 400) {
          try {
            final s = utf8.decode(data);
            if (s.startsWith('http') && s.contains('.dem')) {
              found = s;
              continue;
            }
          } catch (_) {}
        }
        found = _findHttpString(data, depth: depth + 1) ?? found;
      }
    } catch (_) {}
    return found;
  }

  Iterable<_ProtoField> _fields(Uint8List bytes) sync* {
    var offset = 0;
    while (offset < bytes.length) {
      final tag = _readVarint(bytes, offset);
      offset = tag.$2;
      final number = (tag.$1 >> 3).toInt();
      final wireType = (tag.$1 & BigInt.from(7)).toInt();
      switch (wireType) {
        case 0: // varint
          final v = _readVarint(bytes, offset);
          offset = v.$2;
          yield _ProtoField(number, wireType, varint: v.$1);
        case 1: // 64-bit
          if (offset + 8 > bytes.length) return;
          yield _ProtoField(
            number,
            wireType,
            varint: _readLittleEndian(bytes, offset, 8),
          );
          offset += 8;
        case 2: // length-delimited
          final len = _readVarint(bytes, offset);
          offset = len.$2;
          final length = len.$1.toInt();
          if (length < 0 || offset + length > bytes.length) return;
          yield _ProtoField(
            number,
            wireType,
            bytes: Uint8List.sublistView(bytes, offset, offset + length),
          );
          offset += length;
        case 5: // 32-bit
          if (offset + 4 > bytes.length) return;
          yield _ProtoField(
            number,
            wireType,
            varint: _readLittleEndian(bytes, offset, 4),
          );
          offset += 4;
        default:
          return; // groups/unknown — stop parsing this scope
      }
    }
  }

  (BigInt, int) _readVarint(Uint8List bytes, int offset) {
    var result = BigInt.zero;
    var shift = 0;
    var pos = offset;
    while (pos < bytes.length) {
      final byte = bytes[pos];
      result |= BigInt.from(byte & 0x7f) << shift;
      pos++;
      if (byte & 0x80 == 0) return (result, pos);
      shift += 7;
      if (shift > 70) break;
    }
    throw const FormatException('varint overflow');
  }

  BigInt _readLittleEndian(Uint8List bytes, int offset, int size) {
    var result = BigInt.zero;
    for (var i = size - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[offset + i]);
    }
    return result;
  }
}

class _ProtoField {
  final int number;
  final int wireType;
  final BigInt? varint;
  final Uint8List? bytes;

  const _ProtoField(this.number, this.wireType, {this.varint, this.bytes});
}
