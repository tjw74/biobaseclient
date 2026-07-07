import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_demo_service.dart';

/// A saved move: a named slice of demo data (every frame and event between
/// the start and end tick), self-contained so it outlives the source demo.
class MoveClip {
  final String id;
  final String name;
  final String demoName;
  final String mapName;
  final int tickRate;
  final int startTick;
  final int endTick;
  final DateTime createdAt;
  final List<String> players;
  final String filePath;

  const MoveClip({
    required this.id,
    required this.name,
    required this.demoName,
    required this.mapName,
    required this.tickRate,
    required this.startTick,
    required this.endTick,
    required this.createdAt,
    required this.players,
    required this.filePath,
  });

  double get durationSec =>
      tickRate <= 0 ? 0 : (endTick - startTick) / tickRate;
}

class MoveLibraryService {
  Directory get _dir {
    final appData =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '';
    return Directory(p.join(appData, 'BioBase', 'moves'));
  }

  List<MoveClip> list() {
    final dir = _dir;
    if (!dir.existsSync()) return const [];
    final clips = <MoveClip>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data =
            jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
        clips.add(_metaFromJson(data, entity.path));
      } catch (_) {
        // Skip unreadable clip files.
      }
    }
    clips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return clips;
  }

  /// Slices [demo] between [startTick] and [endTick] and writes a
  /// self-contained clip file. Returns the saved clip.
  MoveClip saveClip({
    required NativeDemo demo,
    required String demoName,
    required String name,
    required int startTick,
    required int endTick,
  }) {
    final lo = startTick < endTick ? startTick : endTick;
    final hi = startTick < endTick ? endTick : startTick;

    final frames = demo.frames
        .where((f) => f.tick >= lo && f.tick <= hi)
        .map(
          (f) => {
            'tick': f.tick,
            'timeSec': f.timeSec,
            'players': [
              for (final pl in f.players)
                {
                  'steamid': pl.steamid,
                  'name': pl.name,
                  'team': pl.team,
                  'x': pl.x,
                  'y': pl.y,
                  if (pl.z != null) 'z': pl.z,
                  if (pl.yaw != null) 'yaw': pl.yaw,
                  if (pl.pitch != null) 'pitch': pl.pitch,
                  if (pl.health != null) 'health': pl.health,
                  if (pl.isAlive != null) 'isAlive': pl.isAlive,
                },
            ],
          },
        )
        .toList();

    final events = demo.events
        .where((e) => e.tick >= lo && e.tick <= hi)
        .map(
          (e) => {
            'tick': e.tick,
            'type': e.type,
            'data': {
              if (e.attackerSteamid != null)
                'attacker_steamid': e.attackerSteamid,
              if (e.attackerName != null) 'attacker_name': e.attackerName,
              if (e.victimSteamid != null) 'user_steamid': e.victimSteamid,
              if (e.victimName != null) 'user_name': e.victimName,
              if (e.weapon != null) 'weapon': e.weapon,
              if (e.headshot != null) 'headshot': e.headshot,
              if (e.dmgHealth != null) 'dmg_health': e.dmgHealth,
              if (e.hitgroup != null) 'hitgroup': e.hitgroup,
              if (e.assisterSteamid != null)
                'assister_steamid': e.assisterSteamid,
              if (e.assistedFlash != null) 'assistedflash': e.assistedFlash,
            },
          },
        )
        .toList();

    final playerNames = <String>{};
    for (final f in demo.frames) {
      if (f.tick < lo || f.tick > hi) continue;
      for (final pl in f.players) {
        if (pl.name.isNotEmpty) playerNames.add(pl.name);
      }
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = DateTime.now();
    final dir = _dir;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final filePath = p.join(dir.path, 'move_$id.json');

    final data = {
      'id': id,
      'name': name,
      'demoName': demoName,
      'mapName': demo.mapName,
      'tickRateGuess': demo.tickRateGuess,
      'startTick': lo,
      'endTick': hi,
      'createdAt': createdAt.toIso8601String(),
      'playerNames': playerNames.toList()..sort(),
      // NativeDemo.fromJson-compatible payload for replay.
      'demoId': 'move-$id',
      'frames': frames,
      'events': events,
    };
    File(filePath).writeAsStringSync(jsonEncode(data));
    return _metaFromJson(data, filePath);
  }

  /// Loads the clip's demo-data slice for replay in the viewer.
  NativeDemo? loadClipDemo(MoveClip clip) {
    try {
      final data =
          jsonDecode(File(clip.filePath).readAsStringSync())
              as Map<String, dynamic>;
      return NativeDemo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  void rename(MoveClip clip, String newName) {
    try {
      final file = File(clip.filePath);
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      data['name'] = newName;
      file.writeAsStringSync(jsonEncode(data));
    } catch (_) {}
  }

  void delete(MoveClip clip) {
    try {
      File(clip.filePath).deleteSync();
    } catch (_) {}
  }

  MoveClip _metaFromJson(Map<String, dynamic> data, String filePath) {
    return MoveClip(
      id: '${data['id'] ?? ''}',
      name: '${data['name'] ?? 'Move'}',
      demoName: '${data['demoName'] ?? ''}',
      mapName: '${data['mapName'] ?? 'unknown'}',
      tickRate: (data['tickRateGuess'] as num?)?.round() ?? 64,
      startTick: (data['startTick'] as num?)?.round() ?? 0,
      endTick: (data['endTick'] as num?)?.round() ?? 0,
      createdAt:
          DateTime.tryParse('${data['createdAt']}') ?? DateTime.now(),
      players: [
        for (final n in (data['playerNames'] as List? ?? const [])) '$n',
      ],
      filePath: filePath,
    );
  }
}
