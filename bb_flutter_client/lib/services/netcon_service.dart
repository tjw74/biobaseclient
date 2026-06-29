import 'dart:async';
import 'dart:convert';
import 'dart:io';

class NetconService {
  Socket? _socket;
  final _output = StreamController<String>.broadcast();
  final int port;
  bool _connected = false;
  Timer? _reconnect;

  NetconService({this.port = 2121});

  bool get connected => _connected;
  Stream<String> get output => _output.stream;

  Future<bool> connect() async {
    if (_connected) return true;
    try {
      _socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 3),
      );
      _connected = true;
      _socket!.listen(
        (data) => _output.add(utf8.decode(data, allowMalformed: true)),
        onError: (_) => _onDisconnect(),
        onDone: _onDisconnect,
      );
      return true;
    } catch (_) {
      _connected = false;
      return false;
    }
  }

  void _onDisconnect() {
    _connected = false;
    _socket?.destroy();
    _socket = null;
  }

  void startReconnect({Duration interval = const Duration(seconds: 3)}) {
    _reconnect?.cancel();
    _reconnect = Timer.periodic(interval, (_) {
      if (!_connected) connect();
    });
  }

  void stopReconnect() {
    _reconnect?.cancel();
    _reconnect = null;
  }

  Future<bool> send(String command) async {
    if (_socket == null || !_connected) return false;
    try {
      _socket!.write('$command\n');
      await _socket!.flush();
      return true;
    } catch (_) {
      _onDisconnect();
      return false;
    }
  }

  Future<bool> playDemo(String path) async {
    return send('playdemo "${path.replaceAll('\\', '/')}"');
  }

  Future<bool> pauseDemo() => send('demo_pause');
  Future<bool> resumeDemo() => send('demo_resume');

  Future<bool> gotoTick(int tick) async {
    final modern = await send('demo_goto $tick');
    final legacy = await send('demo_gototick $tick');
    return modern || legacy;
  }

  Future<bool> setTimescale(double speed) => send('demo_timescale $speed');
  Future<bool> stopDemo() => send('stopdemo');

  void disconnect() {
    stopReconnect();
    _onDisconnect();
  }

  void dispose() {
    disconnect();
    _output.close();
  }
}
