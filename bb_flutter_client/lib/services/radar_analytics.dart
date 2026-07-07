import 'demo_analytics.dart';
import 'native_demo_service.dart';

/// Role Performance Radar metrics over one parsed demo.
/// Spec: docs/features/role_performance_radar.md. This is the v1 slice:
/// single-demo scope, side filter, static pro-reference normalization.

/// Trade window shared by trade kills, traded deaths, and KAST's "T".
const double kTradeWindowSec = 5.0;

enum RadarSide { both, t, ct }

class RadarMetricDef {
  final String key;
  final String shortLabel;
  final String name;
  final String unit;
  final bool lowerIsBetter;
  final bool styleAxis;
  final int decimals;

  /// Static pro-reference distribution knots: p5, p25, p50, p75, p95.
  /// V1 stand-in until benchmarks are computed from the pro demo library.
  final List<double> knots;

  const RadarMetricDef({
    required this.key,
    required this.shortLabel,
    required this.name,
    required this.unit,
    required this.knots,
    this.lowerIsBetter = false,
    this.styleAxis = false,
    this.decimals = 2,
  });
}

/// Axis order is fixed — coaches learn shapes; changing order breaks them.
const List<RadarMetricDef> kRadarMetrics = [
  RadarMetricDef(
    key: 'rating',
    shortLabel: 'RTG',
    name: 'BB Rating',
    unit: '',
    knots: [0.85, 0.98, 1.08, 1.18, 1.35],
  ),
  RadarMetricDef(
    key: 'adr',
    shortLabel: 'ADR',
    name: 'Damage / round',
    unit: 'dmg',
    knots: [55, 65, 73, 81, 95],
    decimals: 1,
  ),
  RadarMetricDef(
    key: 'kpr',
    shortLabel: 'KPR',
    name: 'Kills / round',
    unit: '',
    knots: [0.50, 0.60, 0.68, 0.76, 0.90],
  ),
  RadarMetricDef(
    key: 'kd',
    shortLabel: 'K/D',
    name: 'Kill / death ratio',
    unit: '',
    knots: [0.75, 0.90, 1.02, 1.15, 1.40],
  ),
  RadarMetricDef(
    key: 'dpr',
    shortLabel: 'DPR',
    name: 'Deaths / round',
    unit: '',
    knots: [0.55, 0.60, 0.65, 0.70, 0.78],
    lowerIsBetter: true,
  ),
  RadarMetricDef(
    key: 'kast',
    shortLabel: 'KAST',
    name: 'KAST',
    unit: '%',
    knots: [62, 67, 70, 73, 78],
    decimals: 0,
  ),
  RadarMetricDef(
    key: 'traded_deaths_pr',
    shortLabel: 'TRD D',
    name: 'Traded deaths / round',
    unit: '',
    knots: [0.05, 0.09, 0.12, 0.16, 0.22],
  ),
  RadarMetricDef(
    key: 'trade_kills_pr',
    shortLabel: 'TRD K',
    name: 'Trade kills / round',
    unit: '',
    knots: [0.05, 0.08, 0.11, 0.14, 0.19],
  ),
  RadarMetricDef(
    key: 'opening_attempts_pr',
    shortLabel: 'OPN ATT',
    name: 'Opening attempts / round',
    unit: '',
    knots: [0.10, 0.15, 0.20, 0.26, 0.36],
    styleAxis: true,
  ),
  RadarMetricDef(
    key: 'opening_kd',
    shortLabel: 'OPN KD',
    name: 'Opening K/D',
    unit: '',
    knots: [0.60, 0.85, 1.05, 1.30, 1.90],
  ),
  RadarMetricDef(
    key: 'flash_assists_pr',
    shortLabel: 'FA',
    name: 'Flash assists / round',
    unit: '',
    knots: [0.01, 0.03, 0.06, 0.10, 0.16],
  ),
  RadarMetricDef(
    key: 'udr',
    shortLabel: 'UD',
    name: 'Utility damage / round',
    unit: 'dmg',
    knots: [2, 4, 6.5, 9, 14],
    decimals: 1,
  ),
];

const Set<String> _utilityWeapons = {
  'hegrenade',
  'inferno',
  'molotov',
  'incgrenade',
};

class RadarAxisValue {
  final RadarMetricDef def;
  final double raw;
  final double normalized; // 0-100, direction-corrected
  final int sample; // denominator behind the value
  final bool stabilized; // Bayesian shrinkage applied (tiny sample)

  const RadarAxisValue({
    required this.def,
    required this.raw,
    required this.normalized,
    required this.sample,
    this.stabilized = false,
  });
}

class RadarProfile {
  final String label;
  final int rounds;
  final List<RadarAxisValue> axes;

  const RadarProfile({
    required this.label,
    required this.rounds,
    required this.axes,
  });

  RadarAxisValue operator [](int i) => axes[i];
}

class _RoundAtoms {
  int kills = 0;
  int deaths = 0;
  int assists = 0;
  double damage = 0;
  double utilityDamage = 0;
  int flashAssists = 0;
  int tradeKills = 0;
  bool tradedDeath = false;
  bool openingKill = false;
  bool openingDeath = false;
  bool get survived => deaths == 0;
  bool get kastRound => kills > 0 || assists > 0 || survived || tradedDeath;
}

class RadarAnalytics {
  final DemoAnalytics analytics;
  NativeDemo get demo => analytics.demo;

  /// side ('T'/'CT') per player per round; teams swap at halftime so this is
  /// resolved from frames inside each round.
  late final List<Map<String, String>> _sideByRound;

  RadarAnalytics(this.analytics) {
    _sideByRound = _resolveSides();
  }

  int get _rate => demo.tickRateGuess <= 0 ? 64 : demo.tickRateGuess;
  int get _tradeTicks => (kTradeWindowSec * _rate).round();

  List<Map<String, String>> _resolveSides() {
    final result = <Map<String, String>>[];
    var frameIdx = 0;
    for (final round in analytics.rounds) {
      final sides = <String, String>{};
      // Advance to the first frame inside the round, then read teams from a
      // frame a few seconds in (spawn teams are already correct at start).
      while (frameIdx < demo.frames.length &&
          demo.frames[frameIdx].tick < round.startTick) {
        frameIdx++;
      }
      var probe = frameIdx;
      while (probe < demo.frames.length &&
          demo.frames[probe].tick <= round.endTick) {
        for (final p in demo.frames[probe].players) {
          if (p.team == 'T' || p.team == 'CT') {
            sides.putIfAbsent(p.steamid, () => p.team);
          }
        }
        if (sides.length >= 10) break;
        probe++;
      }
      result.add(sides);
    }
    return result;
  }

  String? sideInRound(String steamid, int roundIdx) {
    if (roundIdx < 0 || roundIdx >= _sideByRound.length) return null;
    return _sideByRound[roundIdx][steamid];
  }

  /// Teammates of [steamid]: players on the same side in the majority of
  /// rounds where both are present.
  List<String> teammatesOf(String steamid, {bool opponents = false}) {
    final counts = <String, int>{};
    final totals = <String, int>{};
    for (var r = 0; r < _sideByRound.length; r++) {
      final mySide = _sideByRound[r][steamid];
      if (mySide == null) continue;
      for (final entry in _sideByRound[r].entries) {
        if (entry.key == steamid) continue;
        totals[entry.key] = (totals[entry.key] ?? 0) + 1;
        if (entry.value == mySide) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
        }
      }
    }
    final result = <String>[];
    for (final entry in totals.entries) {
      final same = (counts[entry.key] ?? 0) / entry.value > 0.5;
      if (same != opponents) result.add(entry.key);
    }
    return result;
  }

  bool _isRealKillEvent(NativeDemoEvent e) =>
      e.type == 'player_death' &&
      e.attackerSteamid != null &&
      e.victimSteamid != null &&
      e.attackerSteamid != e.victimSteamid &&
      e.weapon != 'world';

  /// Per-round atoms for one player. Rounds the player has no side data for
  /// (not present) are skipped.
  Map<int, _RoundAtoms> _atomsFor(String steamid, RadarSide side) {
    final atoms = <int, _RoundAtoms>{};
    final wantSide = switch (side) {
      RadarSide.both => null,
      RadarSide.t => 'T',
      RadarSide.ct => 'CT',
    };

    bool inScope(int roundIdx) {
      final s = sideInRound(steamid, roundIdx);
      if (s == null) return false;
      return wantSide == null || s == wantSide;
    }

    for (var r = 0; r < analytics.rounds.length; r++) {
      if (inScope(r)) atoms[r] = _RoundAtoms();
    }
    if (atoms.isEmpty) return atoms;

    int? roundOf(int tick) {
      final span = analytics.roundAtTick(tick);
      return span == null ? null : span.index - 1;
    }

    // Deaths in tick order per round, for openings and trades.
    final deathsByRound = <int, List<NativeDemoEvent>>{};
    for (final e in demo.events) {
      if (e.type != 'player_death') continue;
      final r = roundOf(e.tick);
      if (r == null) continue;
      deathsByRound.putIfAbsent(r, () => []).add(e);
    }

    for (final entry in deathsByRound.entries) {
      final r = entry.key;
      final a = atoms[r];
      final deaths = entry.value..sort((x, y) => x.tick.compareTo(y.tick));
      final realKills = deaths.where(_isRealKillEvent).toList();

      // Opening duel: first real kill of the round.
      if (a != null && realKills.isNotEmpty) {
        final first = realKills.first;
        if (first.attackerSteamid == steamid) a.openingKill = true;
        if (first.victimSteamid == steamid) a.openingDeath = true;
      }

      for (final e in deaths) {
        if (a == null) break;
        if (e.victimSteamid == steamid) {
          a.deaths++;
          // Traded death: any teammate kills my killer within the window.
          final killer = e.attackerSteamid;
          if (killer != null && killer != steamid) {
            for (final later in realKills) {
              if (later.tick <= e.tick) continue;
              if (later.tick - e.tick > _tradeTicks) break;
              if (later.victimSteamid == killer &&
                  sideInRound(later.attackerSteamid!, r) ==
                      sideInRound(steamid, r) &&
                  later.attackerSteamid != steamid) {
                a.tradedDeath = true;
                break;
              }
            }
          }
        }
        if (_isRealKillEvent(e) && e.attackerSteamid == steamid) {
          a.kills++;
          // Trade kill: my victim killed a teammate within the window before.
          final victim = e.victimSteamid;
          for (final earlier in realKills) {
            if (earlier.tick >= e.tick) break;
            if (e.tick - earlier.tick > _tradeTicks) continue;
            if (earlier.attackerSteamid == victim &&
                earlier.victimSteamid != steamid &&
                sideInRound(earlier.victimSteamid!, r) ==
                    sideInRound(steamid, r)) {
              a.tradeKills++;
              break;
            }
          }
        }
        if (e.assisterSteamid == steamid && e.victimSteamid != steamid) {
          a.assists++;
          if (e.assistedFlash == true) a.flashAssists++;
        }
      }
    }

    for (final e in demo.events) {
      if (e.type != 'player_hurt') continue;
      if (e.attackerSteamid != steamid) continue;
      if (e.victimSteamid == steamid) continue;
      final r = roundOf(e.tick);
      final a = r == null ? null : atoms[r];
      if (a == null) continue;
      // Skip team damage when sides are known.
      final victimSide = sideInRound(e.victimSteamid ?? '', r!);
      final mySide = sideInRound(steamid, r);
      if (victimSide != null && mySide != null && victimSide == mySide) {
        continue;
      }
      final dmg = (e.dmgHealth ?? 0).clamp(0, 100).toDouble();
      a.damage += dmg;
      if (_utilityWeapons.contains(e.weapon)) a.utilityDamage += dmg;
    }

    return atoms;
  }

  RadarProfile profileFor(
    String steamid, {
    RadarSide side = RadarSide.both,
    String? label,
  }) {
    final atoms = _atomsFor(steamid, side);
    final raw = _aggregate(atoms.values.toList());
    return _profileFromRaw(
      raw,
      rounds: atoms.length,
      label: label ?? steamid,
    );
  }

  /// Mean of the raw metrics across a set of players (team/opponent average).
  RadarProfile averageProfile(
    List<String> steamids, {
    RadarSide side = RadarSide.both,
    required String label,
  }) {
    if (steamids.isEmpty) {
      return _profileFromRaw(
        {for (final d in kRadarMetrics) d.key: (0.0, 0)},
        rounds: 0,
        label: label,
      );
    }
    final rawPerPlayer = <Map<String, (double, int)>>[];
    var rounds = 0;
    for (final id in steamids) {
      final atoms = _atomsFor(id, side);
      rawPerPlayer.add(_aggregate(atoms.values.toList()));
      if (atoms.length > rounds) rounds = atoms.length;
    }
    final mean = <String, (double, int)>{};
    for (final def in kRadarMetrics) {
      var sum = 0.0;
      var sampleSum = 0;
      for (final m in rawPerPlayer) {
        sum += m[def.key]!.$1;
        sampleSum += m[def.key]!.$2;
      }
      mean[def.key] = (sum / rawPerPlayer.length, sampleSum);
    }
    return _profileFromRaw(mean, rounds: rounds, label: label);
  }

  /// raw value + sample size per metric key.
  Map<String, (double, int)> _aggregate(List<_RoundAtoms> rounds) {
    final n = rounds.length;
    if (n == 0) {
      return {for (final d in kRadarMetrics) d.key: (0.0, 0)};
    }
    var kills = 0, deaths = 0, assists = 0, kastRounds = 0;
    var tradeKills = 0, tradedDeaths = 0, flashAssists = 0;
    var openK = 0, openD = 0;
    var damage = 0.0, utility = 0.0;
    for (final a in rounds) {
      kills += a.kills;
      deaths += a.deaths;
      assists += a.assists;
      damage += a.damage;
      utility += a.utilityDamage;
      flashAssists += a.flashAssists;
      tradeKills += a.tradeKills;
      if (a.tradedDeath) tradedDeaths++;
      if (a.kastRound) kastRounds++;
      if (a.openingKill) openK++;
      if (a.openingDeath) openD++;
    }
    final kpr = kills / n;
    final dpr = deaths / n;
    final apr = assists / n;
    final adr = damage / n;
    final kastPct = kastRounds / n * 100;
    final impact = 2.13 * kpr + 0.42 * apr - 0.41;
    final rating =
        0.0073 * kastPct +
        0.3591 * kpr -
        0.5329 * dpr +
        0.2372 * impact +
        0.0032 * adr +
        0.1587;
    final openAttempts = openK + openD;
    return {
      'rating': (rating, n),
      'adr': (adr, n),
      'kpr': (kpr, n),
      'kd': (deaths == 0 ? kills.toDouble() : kills / deaths, deaths),
      'dpr': (dpr, n),
      'kast': (kastPct, n),
      'traded_deaths_pr': (tradedDeaths / n, n),
      'trade_kills_pr': (tradeKills / n, n),
      'opening_attempts_pr': (openAttempts / n, n),
      'opening_kd': (
        openD == 0 ? openK.toDouble() : openK / openD,
        openAttempts,
      ),
      'flash_assists_pr': (flashAssists / n, n),
      'udr': (utility / n, n),
    };
  }

  RadarProfile _profileFromRaw(
    Map<String, (double, int)> raw, {
    required int rounds,
    required String label,
  }) {
    final axes = <RadarAxisValue>[];
    for (final def in kRadarMetrics) {
      final (value, sample) = raw[def.key]!;
      var effective = value;
      var stabilized = false;
      // Tiny-denominator ratios get empirical-Bayes shrinkage toward the
      // reference median so a 3-attempt 3.0 opening K/D can't max the axis.
      if (def.key == 'opening_kd' && sample < 10) {
        const k = 10;
        effective = (sample * value + k * 1.05) / (sample + k);
        stabilized = true;
      }
      axes.add(
        RadarAxisValue(
          def: def,
          raw: value,
          normalized: _normalize(effective, def),
          sample: sample,
          stabilized: stabilized,
        ),
      );
    }
    return RadarProfile(label: label, rounds: rounds, axes: axes);
  }

  /// Percentile against the reference knots (p5..p95 → 0..100), direction-
  /// corrected. Piecewise linear between knots, clamped.
  double _normalize(double value, RadarMetricDef def) {
    const knotPcts = [5.0, 25.0, 50.0, 75.0, 95.0];
    final knots = def.knots;
    double pct;
    if (value <= knots.first) {
      pct = knotPcts.first * (value / (knots.first <= 0 ? 1 : knots.first));
      if (value <= 0) pct = 0;
    } else if (value >= knots.last) {
      pct = 100;
    } else {
      pct = knotPcts.last;
      for (var i = 1; i < knots.length; i++) {
        if (value <= knots[i]) {
          final t = (value - knots[i - 1]) / (knots[i] - knots[i - 1]);
          pct = knotPcts[i - 1] + t * (knotPcts[i] - knotPcts[i - 1]);
          break;
        }
      }
    }
    pct = pct.clamp(0, 100);
    return def.lowerIsBetter ? 100 - pct : pct;
  }
}
