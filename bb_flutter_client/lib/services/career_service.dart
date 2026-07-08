import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'demo_analytics.dart';
import 'native_demo_service.dart';
import 'radar_analytics.dart';

/// One player's raw radar metrics in one demo.
class CareerEntry {
  final String demoId;
  final String demoName;
  final String mapName;
  final DateTime recordedAt;
  final String steamid;
  final String name;
  final String team;
  final int rounds;
  final Map<String, double> metrics; // radar metric key -> raw value

  const CareerEntry({
    required this.demoId,
    required this.demoName,
    required this.mapName,
    required this.recordedAt,
    required this.steamid,
    required this.name,
    required this.team,
    required this.rounds,
    required this.metrics,
  });
}

/// Local cross-demo player index: every parsed demo contributes one summary
/// file, Review aggregates them into match history and trends. This is the
/// client-side seed of the spec's player_match_stats table.
class CareerService {
  CareerService._();
  static final CareerService instance = CareerService._();

  Directory get _dir {
    final appData =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '';
    return Directory(p.join(appData, 'BioBase', 'career'));
  }

  File _fileFor(String demoId) => File(p.join(_dir.path, '$demoId.json'));

  /// Records per-player summaries for a parsed demo. Skips demos already
  /// recorded and move-clip replays (their demoId starts with "move-").
  void record({required NativeDemo demo, required String demoName}) {
    try {
      if (demo.demoId.isEmpty || demo.demoId.startsWith('move-')) return;
      final file = _fileFor(demo.demoId);
      if (file.existsSync()) return;

      final analytics = DemoAnalytics(demo);
      final radar = RadarAnalytics(analytics);
      final players = <Map<String, dynamic>>[];
      for (final player in analytics.players) {
        final profile = radar.profileFor(player.steamid);
        players.add({
          'steamid': player.steamid,
          'name': player.name,
          'team': player.team,
          'rounds': profile.rounds,
          'metrics': {
            for (final axis in profile.axes) axis.def.key: axis.raw,
          },
        });
      }

      _dir.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'demoId': demo.demoId,
          'demoName': demoName,
          'mapName': demo.mapName,
          'recordedAt': DateTime.now().toIso8601String(),
          'players': players,
        }),
      );
    } catch (_) {
      // Career recording must never break demo playback.
    }
  }

  /// All entries for one player, oldest first.
  List<CareerEntry> forPlayer(String steamid) {
    final dir = _dir;
    if (!dir.existsSync()) return const [];
    final entries = <CareerEntry>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data =
            jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
        for (final raw in (data['players'] as List? ?? const [])) {
          if (raw is! Map) continue;
          if ('${raw['steamid']}' != steamid) continue;
          entries.add(
            CareerEntry(
              demoId: '${data['demoId']}',
              demoName: '${data['demoName']}',
              mapName: '${data['mapName']}',
              recordedAt:
                  DateTime.tryParse('${data['recordedAt']}') ?? DateTime.now(),
              steamid: steamid,
              name: '${raw['name']}',
              team: '${raw['team']}',
              rounds: (raw['rounds'] as num?)?.round() ?? 0,
              metrics: {
                for (final e in (raw['metrics'] as Map? ?? {}).entries)
                  '${e.key}': (e.value as num?)?.toDouble() ?? 0,
              },
            ),
          );
        }
      } catch (_) {}
    }
    entries.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return entries;
  }
}
