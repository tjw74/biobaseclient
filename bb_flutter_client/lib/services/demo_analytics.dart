import 'dart:math' as math;

import 'native_demo_service.dart';

/// One playable round's tick span.
class RoundSpan {
  final int index; // 1-based
  final int startTick;
  final int endTick;

  const RoundSpan({
    required this.index,
    required this.startTick,
    required this.endTick,
  });
}

class PlayerRef {
  final String steamid;
  final String name;
  final String team;

  const PlayerRef({
    required this.steamid,
    required this.name,
    required this.team,
  });
}

/// A time-series sample tied back to a demo tick so charts can seek to it.
class TickSample {
  final int tick;
  final double timeSec;
  final double value;

  const TickSample({
    required this.tick,
    required this.timeSec,
    required this.value,
  });
}

class PlayerMatchStats {
  final int kills;
  final int deaths;
  final int headshots;
  final double adr;
  final double avgSpeed;
  final double distance;
  final int rounds;
  final double counterStrafePct;
  final double avgFlickSpeed;

  const PlayerMatchStats({
    required this.kills,
    required this.deaths,
    required this.headshots,
    required this.adr,
    required this.avgSpeed,
    required this.distance,
    required this.rounds,
    required this.counterStrafePct,
    required this.avgFlickSpeed,
  });

  double get kd => deaths == 0 ? kills.toDouble() : kills / deaths;
  double get hsPct => kills == 0 ? 0 : headshots / kills * 100;
}

/// Below this 2D speed at the moment a shot leaves the barrel, the shot is
/// counted as "set" (counter-strafed). Running rifle speed is ~215-250 u/s;
/// fully accurate standing shots are near zero.
const double _setShotSpeedThreshold = 60.0;

/// Window before a kill used to measure crosshair (yaw) flick velocity.
const double _flickWindowSec = 0.25;

/// Tick-level analytics over one parsed demo. All series carry ticks so the
/// UI can jump the render to any data point.
class DemoAnalytics {
  final NativeDemo demo;
  late final List<RoundSpan> rounds;
  late final List<PlayerRef> players;

  final Map<String, List<TickSample>> _speedCache = {};

  DemoAnalytics(this.demo) {
    rounds = _buildRounds();
    players = _buildPlayers();
  }

  int get _rate => demo.tickRateGuess <= 0 ? 64 : demo.tickRateGuess;

  List<RoundSpan> _buildRounds() {
    final starts = demo.events
        .where((e) => e.type == 'round_start')
        .map((e) => e.tick)
        .toList();
    final spans = <RoundSpan>[];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] - 1 : demo.endTick;
      spans.add(RoundSpan(index: i + 1, startTick: starts[i], endTick: end));
    }
    if (spans.isEmpty) {
      spans.add(
        RoundSpan(index: 1, startTick: demo.startTick, endTick: demo.endTick),
      );
    }
    return spans;
  }

  List<PlayerRef> _buildPlayers() {
    final seen = <String, PlayerRef>{};
    for (final frame in demo.frames) {
      for (final p in frame.players) {
        if (p.steamid == 'unknown' || p.steamid.isEmpty) continue;
        final existing = seen[p.steamid];
        if (existing == null ||
            (existing.team == 'UNKNOWN' && p.team != 'UNKNOWN')) {
          seen[p.steamid] = PlayerRef(
            steamid: p.steamid,
            name: p.name,
            team: p.team,
          );
        }
      }
    }
    final list = seen.values.toList()
      ..sort((a, b) {
        final t = a.team.compareTo(b.team);
        return t != 0 ? t : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  RoundSpan? roundAtTick(int tick) {
    for (final r in rounds) {
      if (tick >= r.startTick && tick <= r.endTick) return r;
    }
    return null;
  }

  bool _isRealKill(NativeDemoEvent e) {
    if (e.type != 'player_death') return false;
    if (e.attackerSteamid == null || e.victimSteamid == null) return false;
    if (e.attackerSteamid == e.victimSteamid) return false;
    if (e.weapon == 'world') return false;
    return true;
  }

  List<NativeDemoEvent> killsBy(String steamid) => demo.events
      .where((e) => _isRealKill(e) && e.attackerSteamid == steamid)
      .toList();

  List<NativeDemoEvent> deathsOf(String steamid) => demo.events
      .where((e) => e.type == 'player_death' && e.victimSteamid == steamid)
      .toList();

  List<NativeDemoEvent> shotsBy(String steamid) => demo.events
      .where(
        (e) =>
            e.type == 'weapon_fire' &&
            e.victimSteamid == steamid && // user_steamid = the shooter
            !(e.weapon ?? '').contains('knife') &&
            !(e.weapon ?? '').contains('grenade') &&
            !(e.weapon ?? '').contains('molotov') &&
            !(e.weapon ?? '').contains('flashbang') &&
            !(e.weapon ?? '').contains('smoke') &&
            !(e.weapon ?? '').contains('decoy'),
      )
      .toList();

  /// 2D movement speed series (u/s) sampled at the parser's frame rate.
  List<TickSample> speedSeries(String steamid) {
    final cached = _speedCache[steamid];
    if (cached != null) return cached;
    final series = <TickSample>[];
    double? lastX, lastY, lastTime;
    for (final frame in demo.frames) {
      NativePlayerState? p;
      for (final candidate in frame.players) {
        if (candidate.steamid == steamid) {
          p = candidate;
          break;
        }
      }
      if (p == null) continue;
      if (lastX != null && lastY != null && lastTime != null) {
        final dt = frame.timeSec - lastTime;
        if (dt > 0 && dt < 3) {
          final dx = p.x - lastX;
          final dy = p.y - lastY;
          final speed = math.sqrt(dx * dx + dy * dy) / dt;
          if (speed < 1200) {
            // Teleports (spawns, round resets) would spike the chart.
            series.add(
              TickSample(
                tick: frame.tick,
                timeSec: frame.timeSec,
                value: speed,
              ),
            );
          }
        }
      }
      lastX = p.x;
      lastY = p.y;
      lastTime = frame.timeSec;
    }
    _speedCache[steamid] = series;
    return series;
  }

  double _speedAtTick(String steamid, int tick) {
    final series = speedSeries(steamid);
    if (series.isEmpty) return 0;
    var lo = 0, hi = series.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (series[mid].tick < tick) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return series[lo].value;
  }

  /// Yaw angular velocity (deg/s) over the window before [tick].
  double _flickSpeedBefore(String steamid, int tick) {
    final windowTicks = (_flickWindowSec * _rate).round();
    final fromTick = tick - windowTicks;
    double? yawStart, yawEnd, tStart, tEnd;
    for (final frame in demo.frames) {
      if (frame.tick < fromTick) continue;
      if (frame.tick > tick) break;
      for (final p in frame.players) {
        if (p.steamid != steamid || p.yaw == null) continue;
        if (yawStart == null) {
          yawStart = p.yaw;
          tStart = frame.timeSec;
        }
        yawEnd = p.yaw;
        tEnd = frame.timeSec;
        break;
      }
    }
    if (yawStart == null || yawEnd == null || tEnd == null || tStart == null) {
      return 0;
    }
    final dt = tEnd - tStart;
    if (dt <= 0) return 0;
    var dyaw = (yawEnd - yawStart).abs() % 360;
    if (dyaw > 180) dyaw = 360 - dyaw;
    return dyaw / dt;
  }

  /// Speed at the moment of every (gun) shot — counter-strafe quality.
  List<TickSample> shotSpeeds(String steamid) {
    return [
      for (final shot in shotsBy(steamid))
        TickSample(
          tick: shot.tick,
          timeSec: (shot.tick - demo.startTick) / _rate,
          value: _speedAtTick(steamid, shot.tick),
        ),
    ];
  }

  /// Crosshair flick velocity before each kill.
  List<TickSample> killFlicks(String steamid) {
    return [
      for (final kill in killsBy(steamid))
        TickSample(
          tick: kill.tick,
          timeSec: (kill.tick - demo.startTick) / _rate,
          value: _flickSpeedBefore(steamid, kill.tick),
        ),
    ];
  }

  List<int> killsPerRound(String steamid) =>
      _countPerRound(killsBy(steamid).map((e) => e.tick));

  List<int> deathsPerRound(String steamid) =>
      _countPerRound(deathsOf(steamid).map((e) => e.tick));

  List<double> damagePerRound(String steamid) {
    final totals = List<double>.filled(rounds.length, 0);
    for (final e in demo.events) {
      if (e.type != 'player_hurt') continue;
      if (e.attackerSteamid != steamid) continue;
      if (e.victimSteamid == steamid) continue;
      final r = roundAtTick(e.tick);
      if (r == null) continue;
      totals[r.index - 1] += (e.dmgHealth ?? 0).clamp(0, 100).toDouble();
    }
    return totals;
  }

  List<double> avgSpeedPerRound(String steamid) {
    final sums = List<double>.filled(rounds.length, 0);
    final counts = List<int>.filled(rounds.length, 0);
    for (final s in speedSeries(steamid)) {
      final r = roundAtTick(s.tick);
      if (r == null) continue;
      sums[r.index - 1] += s.value;
      counts[r.index - 1]++;
    }
    return [
      for (var i = 0; i < rounds.length; i++)
        counts[i] == 0 ? 0 : sums[i] / counts[i],
    ];
  }

  List<double> distancePerRound(String steamid) {
    final totals = List<double>.filled(rounds.length, 0);
    final series = speedSeries(steamid);
    for (var i = 1; i < series.length; i++) {
      final dt = series[i].timeSec - series[i - 1].timeSec;
      if (dt <= 0 || dt > 3) continue;
      final r = roundAtTick(series[i].tick);
      if (r == null) continue;
      totals[r.index - 1] += series[i].value * dt;
    }
    return totals;
  }

  List<int> _countPerRound(Iterable<int> ticks) {
    final counts = List<int>.filled(rounds.length, 0);
    for (final tick in ticks) {
      final r = roundAtTick(tick);
      if (r == null) continue;
      counts[r.index - 1]++;
    }
    return counts;
  }

  PlayerMatchStats statsFor(String steamid) {
    final kills = killsBy(steamid);
    final deaths = deathsOf(steamid);
    final headshots = kills.where((e) => e.headshot == true).length;
    final damage = damagePerRound(steamid);
    final totalDamage = damage.fold<double>(0, (a, b) => a + b);
    final speeds = speedSeries(steamid);
    final avgSpeed = speeds.isEmpty
        ? 0.0
        : speeds.map((s) => s.value).reduce((a, b) => a + b) / speeds.length;
    final distance = distancePerRound(
      steamid,
    ).fold<double>(0, (a, b) => a + b);
    final shots = shotSpeeds(steamid);
    final setShots = shots
        .where((s) => s.value <= _setShotSpeedThreshold)
        .length;
    final flicks = killFlicks(steamid);
    final avgFlick = flicks.isEmpty
        ? 0.0
        : flicks.map((f) => f.value).reduce((a, b) => a + b) / flicks.length;
    return PlayerMatchStats(
      kills: kills.length,
      deaths: deaths.length,
      headshots: headshots,
      adr: rounds.isEmpty ? 0 : totalDamage / rounds.length,
      avgSpeed: avgSpeed,
      distance: distance,
      rounds: rounds.length,
      counterStrafePct: shots.isEmpty ? 0 : setShots / shots.length * 100,
      avgFlickSpeed: avgFlick,
    );
  }

  /// Standard deviation helper for consistency metrics.
  static double stdDev(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }
}
