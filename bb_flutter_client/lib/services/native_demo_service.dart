import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class NativePlayerState {
  final String steamid;
  final String name;
  final String team;
  final double x;
  final double y;
  final double? z;
  final double? yaw;
  final double? pitch;
  final double? health;
  final bool? isAlive;

  const NativePlayerState({
    required this.steamid,
    required this.name,
    required this.team,
    required this.x,
    required this.y,
    this.z,
    this.yaw,
    this.pitch,
    this.health,
    this.isAlive,
  });

  factory NativePlayerState.fromJson(Map<String, dynamic> json) {
    double? n(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('$value');
    return NativePlayerState(
      steamid: '${json['steamid'] ?? ''}',
      name: '${json['name'] ?? json['steamid'] ?? 'unknown'}',
      team: '${json['team'] ?? 'UNKNOWN'}',
      x: n(json['x']) ?? 0,
      y: n(json['y']) ?? 0,
      z: n(json['z']),
      yaw: n(json['yaw']),
      pitch: n(json['pitch']),
      health: n(json['health']),
      isAlive: json['isAlive'] is bool ? json['isAlive'] as bool : null,
    );
  }
}

class NativeDemoFrame {
  final int tick;
  final double timeSec;
  final List<NativePlayerState> players;

  const NativeDemoFrame({
    required this.tick,
    required this.timeSec,
    required this.players,
  });

  factory NativeDemoFrame.fromJson(Map<String, dynamic> json) {
    final players = (json['players'] as List? ?? const [])
        .whereType<Map>()
        .map((p) => NativePlayerState.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    return NativeDemoFrame(
      tick: (json['tick'] as num?)?.round() ?? 0,
      timeSec: (json['timeSec'] as num?)?.toDouble() ?? 0,
      players: players,
    );
  }
}

class NativeDemoEvent {
  final int tick;
  final String type;

  // Attribution payload (present on player_death / player_hurt / weapon_fire;
  // the parser stores the raw demoparser2 event row under `data`).
  final String? attackerSteamid;
  final String? attackerName;
  final String? victimSteamid;
  final String? victimName;
  final String? weapon;
  final bool? headshot;
  final int? dmgHealth;
  final String? hitgroup;

  const NativeDemoEvent({
    required this.tick,
    required this.type,
    this.attackerSteamid,
    this.attackerName,
    this.victimSteamid,
    this.victimName,
    this.weapon,
    this.headshot,
    this.dmgHealth,
    this.hitgroup,
  });

  factory NativeDemoEvent.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    String? s(Object? v) => v == null ? null : '$v';
    if (data is Map) {
      return NativeDemoEvent(
        tick: (json['tick'] as num?)?.round() ?? 0,
        type: '${json['type'] ?? 'event'}',
        attackerSteamid: s(data['attacker_steamid']),
        attackerName: s(data['attacker_name']),
        victimSteamid: s(data['user_steamid']),
        victimName: s(data['user_name']),
        weapon: s(data['weapon']),
        headshot: data['headshot'] is bool ? data['headshot'] as bool : null,
        dmgHealth: (data['dmg_health'] as num?)?.round(),
        hitgroup: s(data['hitgroup']),
      );
    }
    return NativeDemoEvent(
      tick: (json['tick'] as num?)?.round() ?? 0,
      type: '${json['type'] ?? 'event'}',
    );
  }
}

class NativeDemo {
  final String demoId;
  final String mapName;
  final int tickRateGuess;
  final int startTick;
  final int endTick;
  final List<NativeDemoFrame> frames;
  final List<NativeDemoEvent> events;

  const NativeDemo({
    required this.demoId,
    required this.mapName,
    required this.tickRateGuess,
    required this.startTick,
    required this.endTick,
    required this.frames,
    required this.events,
  });

  int get tickSpan => (endTick - startTick).clamp(1, 1 << 31).toInt();

  factory NativeDemo.fromJson(Map<String, dynamic> json) {
    final frames = (json['frames'] as List? ?? const [])
        .whereType<Map>()
        .map((f) => NativeDemoFrame.fromJson(Map<String, dynamic>.from(f)))
        .toList();
    final events = (json['events'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => NativeDemoEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return NativeDemo(
      demoId: '${json['demoId'] ?? ''}',
      mapName: '${json['mapName'] ?? 'unknown'}',
      tickRateGuess: (json['tickRateGuess'] as num?)?.round() ?? 64,
      startTick: (json['startTick'] as num?)?.round() ?? 0,
      endTick: (json['endTick'] as num?)?.round() ?? 0,
      frames: frames,
      events: events,
    );
  }
}

class NativeDemoLabel {
  final String id;
  final String demoId;
  final int startTick;
  final int endTick;
  final String title;
  final String note;
  final List<String> tags;

  const NativeDemoLabel({
    required this.id,
    required this.demoId,
    required this.startTick,
    required this.endTick,
    required this.title,
    required this.note,
    required this.tags,
  });

  factory NativeDemoLabel.fromJson(Map<String, dynamic> json) {
    return NativeDemoLabel(
      id: '${json['id'] ?? ''}',
      demoId: '${json['demoId'] ?? ''}',
      startTick: (json['startTick'] as num?)?.round() ?? 0,
      endTick: (json['endTick'] as num?)?.round() ?? 0,
      title: '${json['title'] ?? 'Untitled moment'}',
      note: '${json['note'] ?? ''}',
      tags: (json['tags'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }
}

class NativeDemoService {
  final String baseUrl;
  final http.Client _client;

  NativeDemoService({this.baseUrl = defaultApiBaseUrl, http.Client? client})
    : _client = client ?? http.Client();

  Future<NativeDemo> uploadAndLoad(File file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/demos/upload'),
    );
    request.files.add(await http.MultipartFile.fromPath('demo', file.path));
    final streamed = await _client
        .send(request)
        .timeout(const Duration(minutes: 15));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(_extractError(body, streamed.statusCode));
    }
    final uploaded = jsonDecode(body) as Map<String, dynamic>;
    final demoId = '${uploaded['demoId'] ?? ''}';
    if (demoId.isEmpty) {
      throw Exception('Demo upload did not return a demo id.');
    }
    return fetchDemo(demoId);
  }

  Future<NativeDemo> fetchDemo(String demoId) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/demos/$demoId'))
        .timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
    return NativeDemo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<NativeDemoLabel>> fetchLabels(String demoId) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/demos/$demoId/labels'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final data = jsonDecode(response.body) as List;
    return data
        .whereType<Map>()
        .map((e) => NativeDemoLabel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<NativeDemoLabel> createLabel({
    required String demoId,
    required int startTick,
    required int endTick,
    required String title,
    String note = '',
    List<String> tags = const [],
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/demos/$demoId/labels'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'startTick': startTick,
            'endTick': endTick,
            'title': title,
            'note': note,
            'tags': tags,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
    return NativeDemoLabel.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  String _extractError(String body, int statusCode) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['detail'] != null) return '${data['detail']}';
      if (data is Map && data['error'] != null) return '${data['error']}';
    } catch (_) {
      // fall through
    }
    return 'HTTP $statusCode';
  }

  void dispose() => _client.close();
}
