class ServerConnectInfo {
  final String host;
  final int port;
  final String console;
  final String? steamUrl;

  const ServerConnectInfo({
    required this.host,
    required this.port,
    required this.console,
    this.steamUrl,
  });

  factory ServerConnectInfo.fromJson(Map<String, dynamic> json) {
    return ServerConnectInfo(
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 27015,
      console: json['console'] as String? ?? '',
      steamUrl: json['steamUrl'] as String?,
    );
  }
}

class LiveServerPlayer {
  final int userid;
  final String name;
  final String? steamid;
  final int ping;
  final String state;

  const LiveServerPlayer({
    required this.userid,
    required this.name,
    this.steamid,
    required this.ping,
    required this.state,
  });

  factory LiveServerPlayer.fromJson(Map<String, dynamic> json) {
    return LiveServerPlayer(
      userid: json['userid'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      steamid: json['steamid'] as String?,
      ping: json['ping'] as int? ?? 0,
      state: json['state'] as String? ?? '',
    );
  }

  bool get isHuman => steamid != null && steamid != 'BOT';
}

class LiveServerStatus {
  final bool ok;
  final String? map;
  final String? hostname;
  final List<LiveServerPlayer> players;
  final ServerConnectInfo? connect;
  final String? error;

  const LiveServerStatus({
    required this.ok,
    this.map,
    this.hostname,
    this.players = const [],
    this.connect,
    this.error,
  });

  factory LiveServerStatus.fromJson(Map<String, dynamic> json) {
    final playerList = (json['players'] as List<dynamic>?)
            ?.map((p) => LiveServerPlayer.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];
    final connectJson = json['connect'] as Map<String, dynamic>?;
    return LiveServerStatus(
      ok: json['ok'] as bool? ?? false,
      map: json['map'] as String?,
      hostname: json['hostname'] as String?,
      players: playerList,
      connect: connectJson != null
          ? ServerConnectInfo.fromJson(connectJson)
          : null,
      error: json['error'] as String?,
    );
  }

  List<LiveServerPlayer> get humans =>
      players.where((p) => p.isHuman).toList();

  int get botCount => players.length - humans.length;
}

class MovementKeys {
  final bool w, a, s, d, crouch, jump;

  const MovementKeys({
    this.w = false,
    this.a = false,
    this.s = false,
    this.d = false,
    this.crouch = false,
    this.jump = false,
  });

  factory MovementKeys.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MovementKeys();
    return MovementKeys(
      w: json['w'] as bool? ?? false,
      a: json['a'] as bool? ?? false,
      s: json['s'] as bool? ?? false,
      d: json['d'] as bool? ?? false,
      crouch: json['crouch'] as bool? ?? false,
      jump: json['jump'] as bool? ?? false,
    );
  }
}

class LiveMovementSample {
  final String? player;
  final String steamid;
  final int tick;
  final double speed;
  final bool onGround;
  final double counterStrafeScore;
  final double pathEfficiency;
  final MovementKeys keys;
  final List<double> pos;
  final List<double> vel;
  final double yaw;
  final double pitch;
  final String? observedAt;

  const LiveMovementSample({
    this.player,
    required this.steamid,
    required this.tick,
    required this.speed,
    required this.onGround,
    this.counterStrafeScore = 0.5,
    this.pathEfficiency = 0.7,
    this.keys = const MovementKeys(),
    this.pos = const [0, 0, 0],
    this.vel = const [0, 0, 0],
    this.yaw = 0,
    this.pitch = 0,
    this.observedAt,
  });

  double get velX => vel.isNotEmpty ? vel[0] : 0;
  double get velY => vel.length > 1 ? vel[1] : 0;
  double get velZ => vel.length > 2 ? vel[2] : 0;
  double get horizontalSpeed {
    final vx = velX, vy = velY;
    return (vx * vx + vy * vy).clamp(0, double.infinity);
  }

  factory LiveMovementSample.fromJson(Map<String, dynamic> json) {
    final posList = (json['pos'] as List<dynamic>?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        [0.0, 0.0, 0.0];
    final velList = (json['vel'] as List<dynamic>?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        [0.0, 0.0, 0.0];
    return LiveMovementSample(
      player: json['player'] as String?,
      steamid: json['steamid'] as String? ?? '',
      tick: json['tick'] as int? ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      onGround: json['on_ground'] as bool? ?? true,
      counterStrafeScore:
          (json['counterStrafeScore'] as num?)?.toDouble() ?? 0.5,
      pathEfficiency: (json['pathEfficiency'] as num?)?.toDouble() ?? 0.7,
      keys: MovementKeys.fromJson(json['keys'] as Map<String, dynamic>?),
      pos: posList,
      vel: velList,
      yaw: (json['yaw'] as num?)?.toDouble() ?? 0,
      pitch: (json['pitch'] as num?)?.toDouble() ?? 0,
      observedAt: json['observedAt'] as String?,
    );
  }
}

class LiveMovementStatus {
  final bool ok;
  final List<LiveMovementSample> samples;
  final LiveMovementSample? tracked;
  final String? error;

  const LiveMovementStatus({
    required this.ok,
    this.samples = const [],
    this.tracked,
    this.error,
  });

  factory LiveMovementStatus.fromJson(Map<String, dynamic> json) {
    final sampleList = (json['samples'] as List<dynamic>?)
            ?.map(
                (s) => LiveMovementSample.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];
    final trackedJson = json['tracked'] as Map<String, dynamic>?;
    return LiveMovementStatus(
      ok: json['ok'] as bool? ?? false,
      samples: sampleList,
      tracked: trackedJson != null
          ? LiveMovementSample.fromJson(trackedJson)
          : null,
      error: json['error'] as String?,
    );
  }
}

class LiveFrame {
  final String mapName;
  final String playerName;
  final int tick;
  final double timeSec;
  final int speed;
  final double counterStrafeScore;
  final double pathEfficiency;
  final MovementKeys keys;
  final double yaw;
  final double pitch;
  final bool onGround;
  final List<double> vel;
  final List<double> pos;

  const LiveFrame({
    this.mapName = 'offline',
    this.playerName = 'OFFLINE',
    this.tick = 0,
    this.timeSec = 0,
    this.speed = 0,
    this.counterStrafeScore = 0,
    this.pathEfficiency = 0,
    this.keys = const MovementKeys(),
    this.yaw = 0,
    this.pitch = 0,
    this.onGround = true,
    this.vel = const [0, 0, 0],
    this.pos = const [0, 0, 0],
  });

  double get velZ => vel.length > 2 ? vel[2] : 0;
  bool get isAirborne => !onGround;
  bool get isMoving => speed > 5;

  factory LiveFrame.fromServerData(
    LiveServerStatus? status,
    LiveMovementSample? movement,
  ) {
    if (movement == null) {
      return LiveFrame(
        mapName: status?.map ?? 'offline',
        playerName: status?.ok == true ? 'WAITING' : 'OFFLINE',
      );
    }
    const tickRate = 64;
    final tick = movement.tick;
    return LiveFrame(
      mapName: status?.map ?? 'live-server',
      playerName: movement.player ?? 'LIVE',
      tick: tick,
      timeSec: tick / tickRate,
      speed: movement.speed.round(),
      counterStrafeScore: movement.counterStrafeScore,
      pathEfficiency: movement.pathEfficiency,
      keys: movement.keys.w || movement.keys.a || movement.keys.s || movement.keys.d
          ? movement.keys
          : MovementKeys(jump: !movement.onGround),
      yaw: movement.yaw,
      pitch: movement.pitch,
      onGround: movement.onGround,
      vel: movement.vel,
      pos: movement.pos,
    );
  }
}

enum StatusLevel { live, online, offline }
