class ShadowTick {
  final int tickOffset;
  final double x, y, z;
  final double velX, velY, velZ;
  final double speed;
  final double yaw, pitch;
  final bool onGround;
  final bool ducking;

  const ShadowTick({
    required this.tickOffset,
    required this.x,
    required this.y,
    required this.z,
    this.velX = 0,
    this.velY = 0,
    this.velZ = 0,
    this.speed = 0,
    this.yaw = 0,
    this.pitch = 0,
    this.onGround = true,
    this.ducking = false,
  });

  factory ShadowTick.fromJson(Map<String, dynamic> j) => ShadowTick(
        tickOffset: j['tick_offset'] as int? ?? 0,
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        z: (j['z'] as num?)?.toDouble() ?? 0,
        velX: (j['vel_x'] as num?)?.toDouble() ?? 0,
        velY: (j['vel_y'] as num?)?.toDouble() ?? 0,
        velZ: (j['vel_z'] as num?)?.toDouble() ?? 0,
        speed: (j['speed'] as num?)?.toDouble() ?? 0,
        yaw: (j['yaw'] as num?)?.toDouble() ?? 0,
        pitch: (j['pitch'] as num?)?.toDouble() ?? 0,
        onGround: j['on_ground'] == true || j['on_ground'] == 1,
        ducking: j['ducking'] == true || j['ducking'] == 1,
      );

  Map<String, dynamic> toJson() => {
        'tick_offset': tickOffset,
        'x': x,
        'y': y,
        'z': z,
        'vel_x': velX,
        'vel_y': velY,
        'vel_z': velZ,
        'speed': speed,
        'yaw': yaw,
        'pitch': pitch,
        'on_ground': onGround,
        'ducking': ducking,
      };
}

class ShadowMove {
  final String id;
  final String name;
  final String description;
  final String mapName;
  final String moveType;
  final String difficulty;
  final List<String> tags;
  final int durationTicks;
  final String createdAt;
  final String visibility;
  final String status;
  final List<ShadowTick> ticks;
  final int attemptCount;

  const ShadowMove({
    required this.id,
    required this.name,
    this.description = '',
    this.mapName = '',
    this.moveType = 'general',
    this.difficulty = 'medium',
    this.tags = const [],
    this.durationTicks = 0,
    this.createdAt = '',
    this.visibility = 'private',
    this.status = 'draft',
    this.ticks = const [],
    this.attemptCount = 0,
  });

  factory ShadowMove.fromJson(Map<String, dynamic> j) {
    final rawTags = j['tags'];
    final tags = rawTags is List
        ? rawTags.cast<String>()
        : <String>[];
    final rawTicks = j['ticks'] as List<dynamic>?;
    return ShadowMove(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      description: j['description'] as String? ?? '',
      mapName: j['map_name'] as String? ?? '',
      moveType: j['move_type'] as String? ?? 'general',
      difficulty: j['difficulty'] as String? ?? 'medium',
      tags: tags,
      durationTicks: j['duration_ticks'] as int? ?? 0,
      createdAt: j['created_at'] as String? ?? '',
      visibility: j['visibility'] as String? ?? 'private',
      status: j['status'] as String? ?? 'draft',
      ticks: rawTicks?.map((t) => ShadowTick.fromJson(t as Map<String, dynamic>)).toList() ?? [],
      attemptCount: j['attempt_count'] as int? ?? 0,
    );
  }

  double get durationSeconds => durationTicks / 64.0;
}

class ShadowAttempt {
  final String id;
  final String shadowMoveId;
  final String steamId;
  final String startedAt;
  final String? completedAt;
  final double scoreOverall;
  final double scorePath;
  final double scoreSpeed;
  final double scoreTiming;
  final String status;
  final List<ShadowTick> ticks;
  final List<ShadowTick> refTicks;

  const ShadowAttempt({
    required this.id,
    required this.shadowMoveId,
    this.steamId = '',
    this.startedAt = '',
    this.completedAt,
    this.scoreOverall = 0,
    this.scorePath = 0,
    this.scoreSpeed = 0,
    this.scoreTiming = 0,
    this.status = 'completed',
    this.ticks = const [],
    this.refTicks = const [],
  });

  factory ShadowAttempt.fromJson(Map<String, dynamic> j) {
    final rawTicks = j['ticks'] as List<dynamic>?;
    final rawRef = j['ref_ticks'] as List<dynamic>?;
    return ShadowAttempt(
      id: j['id'] as String? ?? '',
      shadowMoveId: j['shadow_move_id'] as String? ?? '',
      steamId: j['steam_id'] as String? ?? '',
      startedAt: j['started_at'] as String? ?? '',
      completedAt: j['completed_at'] as String?,
      scoreOverall: (j['score_overall'] as num?)?.toDouble() ?? 0,
      scorePath: (j['score_path'] as num?)?.toDouble() ?? 0,
      scoreSpeed: (j['score_speed'] as num?)?.toDouble() ?? 0,
      scoreTiming: (j['score_timing'] as num?)?.toDouble() ?? 0,
      status: j['status'] as String? ?? 'completed',
      ticks: rawTicks?.map((t) => ShadowTick.fromJson(t as Map<String, dynamic>)).toList() ?? [],
      refTicks: rawRef?.map((t) => ShadowTick.fromJson(t as Map<String, dynamic>)).toList() ?? [],
    );
  }
}
