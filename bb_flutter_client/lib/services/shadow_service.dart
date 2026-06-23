import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shadow.dart';

class ShadowService {
  final String baseUrl;
  final http.Client _client = http.Client();

  ShadowService({required this.baseUrl});

  Future<List<ShadowMove>> listMoves({String? mapName, String? difficulty}) async {
    final params = <String, String>{};
    if (mapName != null && mapName.isNotEmpty) params['map_name'] = mapName;
    if (difficulty != null && difficulty.isNotEmpty) params['difficulty'] = difficulty;

    final uri = Uri.parse('$baseUrl/api/shadow/moves').replace(queryParameters: params.isNotEmpty ? params : null);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('Failed to list shadow moves');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = body['moves'] as List<dynamic>;
    return list.map((m) => ShadowMove.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<ShadowMove> getMove(String id) async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/shadow/moves/$id')).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('Move not found');
    return ShadowMove.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<ShadowMove> createMove({
    required String name,
    required List<ShadowTick> ticks,
    String description = '',
    String mapName = '',
    String moveType = 'general',
    String difficulty = 'medium',
    List<String> tags = const [],
    String creatorSteamId = '',
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/shadow/moves'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'description': description,
        'map_name': mapName,
        'move_type': moveType,
        'difficulty': difficulty,
        'tags': tags,
        'creator_steam_id': creatorSteamId,
        'ticks': ticks.map((t) => t.toJson()).toList(),
      }),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 201) throw Exception('Failed to create shadow move');
    return ShadowMove.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> deleteMove(String id) async {
    await _client.delete(Uri.parse('$baseUrl/api/shadow/moves/$id')).timeout(const Duration(seconds: 10));
  }

  Future<ShadowAttempt> createAttempt({
    required String moveId,
    required List<ShadowTick> ticks,
    String steamId = '',
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/shadow/moves/$moveId/attempts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'steam_id': steamId,
        'ticks': ticks.map((t) => t.toJson()).toList(),
      }),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 201) throw Exception('Failed to create attempt');
    return ShadowAttempt.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<List<ShadowAttempt>> listAttempts(String moveId) async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/shadow/moves/$moveId/attempts')).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('Failed to list attempts');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = body['attempts'] as List<dynamic>;
    return list.map((a) => ShadowAttempt.fromJson(a as Map<String, dynamic>)).toList();
  }

  Future<ShadowAttempt> getAttempt(String id) async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/shadow/attempts/$id')).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('Attempt not found');
    return ShadowAttempt.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}
