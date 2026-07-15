import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'api_service.dart';

/// Live pro benchmark distributions computed server-side from the parsed
/// demo library. Parsing survives CS2 updates, so these stay valid even when
/// the demos themselves can no longer be rendered.
class ProBenchmarks {
  final int players;
  final int demos;
  final int playerRounds;

  /// metric key -> [p5, p25, p50, p75, p95]
  final Map<String, List<double>> metrics;

  /// per-round sample key (damage/kills/deaths/distance/avg_speed) -> knots
  final Map<String, List<double>> perRound;

  const ProBenchmarks({
    required this.players,
    required this.demos,
    required this.playerRounds,
    required this.metrics,
    required this.perRound,
  });

  factory ProBenchmarks.fromJson(Map<String, dynamic> json) {
    Map<String, List<double>> knots(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is List && (e.value as List).length == 5)
            '${e.key}': [
              for (final v in e.value as List) (v as num).toDouble(),
            ],
    };
    final population = json['population'] as Map? ?? {};
    return ProBenchmarks(
      players: (population['players'] as num?)?.round() ?? 0,
      demos: (population['demos'] as num?)?.round() ?? 0,
      playerRounds: (population['player_rounds'] as num?)?.round() ?? 0,
      metrics: knots(json['metrics']),
      perRound: knots(json['perRound']),
    );
  }

  /// (p25, p50, p75) band for a per-round chart, when available.
  (double, double, double)? band(String key) {
    final k = perRound[key];
    if (k == null) return null;
    return (k[1], k[2], k[3]);
  }
}

class BenchmarkService {
  BenchmarkService._();
  static final BenchmarkService instance = BenchmarkService._();

  ProBenchmarks? current;
  bool _loading = false;

  File get _cacheFile {
    final appData =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '';
    return File(p.join(appData, 'BioBase', 'benchmarks.json'));
  }

  /// Loads benchmarks: disk cache immediately, then refresh from the server.
  Future<ProBenchmarks?> load({void Function()? onUpdated}) async {
    if (current == null) {
      try {
        final cached = jsonDecode(_cacheFile.readAsStringSync());
        current = ProBenchmarks.fromJson(cached as Map<String, dynamic>);
      } catch (_) {}
    }
    if (!_loading) {
      _loading = true;
      _refresh().then((updated) {
        _loading = false;
        if (updated) onUpdated?.call();
      });
    }
    return current;
  }

  Future<bool> _refresh() async {
    try {
      final response = await http
          .get(Uri.parse('$defaultApiBaseUrl/api/demos/benchmarks'))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) return false;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final fresh = ProBenchmarks.fromJson(json);
      if (fresh.players <= 0 || fresh.metrics.isEmpty) return false;
      current = fresh;
      try {
        _cacheFile.parent.createSync(recursive: true);
        _cacheFile.writeAsStringSync(response.body);
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }
}
