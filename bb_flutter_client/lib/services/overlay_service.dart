import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

class OverlayService {
  static const _hudSize = Size(420, 220);
  static const _hudMaxSize = Size(480, 280);
  static const _margin = 16.0;
  static const _autoCloseMinutes = 240;
  static const _heartbeatTimeoutSec = 60;

  bool _active = false;
  Size? _savedSize;
  Offset? _savedPosition;
  Timer? _autoCloseTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastDataTime;
  bool _stale = false;

  bool get active => _active;
  bool get stale => _stale;

  void Function()? onAutoClose;
  void Function()? onStaleChanged;

  Future<void> activate() async {
    if (_active) return;
    _savedSize = await windowManager.getSize();
    _savedPosition = await windowManager.getPosition();

    await windowManager.setMinimumSize(const Size(300, 150));
    await windowManager.setMaximumSize(_hudMaxSize);
    await windowManager.setSize(_hudSize);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setOpacity(0.92);
    await windowManager.setSkipTaskbar(true);

    await windowManager.setAlignment(Alignment.topRight);
    final pos = await windowManager.getPosition();
    await windowManager.setPosition(Offset(pos.dx - _margin, pos.dy + _margin));

    _active = true;
    _stale = false;
    _lastDataTime = DateTime.now();
    _startAutoCloseTimer();
    _startHeartbeatCheck();
  }

  Future<void> deactivate() async {
    if (!_active) return;
    _autoCloseTimer?.cancel();
    _heartbeatTimer?.cancel();

    await windowManager.setAlwaysOnTop(false);
    await windowManager.setOpacity(1.0);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setMaximumSize(const Size(9999, 9999));
    await windowManager.setMinimumSize(const Size(600, 400));
    if (_savedSize != null) await windowManager.setSize(_savedSize!);
    if (_savedPosition != null) await windowManager.setPosition(_savedPosition!);

    _active = false;
    _stale = false;
  }

  void recordHeartbeat() {
    _lastDataTime = DateTime.now();
    if (_stale) {
      _stale = false;
      onStaleChanged?.call();
    }
  }

  void _startAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(
      const Duration(minutes: _autoCloseMinutes),
      () => onAutoClose?.call(),
    );
  }

  void _startHeartbeatCheck() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_lastDataTime == null) return;
      final elapsed = DateTime.now().difference(_lastDataTime!).inSeconds;
      final wasStale = _stale;
      _stale = elapsed > _heartbeatTimeoutSec;
      if (_stale != wasStale) onStaleChanged?.call();
    });
  }

  void dispose() {
    _autoCloseTimer?.cancel();
    _heartbeatTimer?.cancel();
  }
}
