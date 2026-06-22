import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

const String defaultApiBaseUrl = 'https://cs2.clarionlab.dev/admin';
const String defaultConnectHost = 'cs2.clarionlab.dev';
const int defaultConnectPort = 27015;

class ApiService {
  final String baseUrl;
  final http.Client _client = http.Client();

  Timer? _statusTimer;
  Timer? _movementTimer;

  LiveServerStatus? lastStatus;
  LiveMovementStatus? lastMovement;

  final StreamController<LiveServerStatus> _statusController =
      StreamController.broadcast();
  final StreamController<LiveMovementStatus> _movementController =
      StreamController.broadcast();

  Stream<LiveServerStatus> get statusStream => _statusController.stream;
  Stream<LiveMovementStatus> get movementStream => _movementController.stream;

  ApiService({this.baseUrl = defaultApiBaseUrl});

  Future<LiveServerStatus> fetchStatus() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/client/live/status'))
          .timeout(const Duration(seconds: 10));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final status = LiveServerStatus.fromJson(json);
      lastStatus = status;
      _statusController.add(status);
      return status;
    } catch (e) {
      final status = LiveServerStatus(ok: false, error: e.toString());
      lastStatus = status;
      _statusController.add(status);
      return status;
    }
  }

  Future<LiveMovementStatus> fetchMovement({String? player}) async {
    try {
      var uri = Uri.parse('$baseUrl/api/client/live/movement');
      if (player != null && player.isNotEmpty) {
        uri = uri.replace(queryParameters: {'player': player});
      }
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 5));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final movement = LiveMovementStatus.fromJson(json);
      lastMovement = movement;
      _movementController.add(movement);
      return movement;
    } catch (e) {
      final movement = LiveMovementStatus(ok: false, error: e.toString());
      lastMovement = movement;
      _movementController.add(movement);
      return movement;
    }
  }

  Future<Map<String, dynamic>> createCompanionLink({
    String playerName = '',
    String deviceName = 'Biobase Client',
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/client/companion/link'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'playerName': playerName,
          'deviceName': deviceName,
        }),
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  void startPolling({String? trackedPlayer}) {
    stopPolling();
    fetchStatus();
    fetchMovement(player: trackedPlayer);
    _statusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => fetchStatus(),
    );
    _movementTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => fetchMovement(player: trackedPlayer),
    );
  }

  void stopPolling() {
    _statusTimer?.cancel();
    _movementTimer?.cancel();
    _statusTimer = null;
    _movementTimer = null;
  }

  void dispose() {
    stopPolling();
    _statusController.close();
    _movementController.close();
    _client.close();
  }
}
