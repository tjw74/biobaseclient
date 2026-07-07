import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Captures the CS2 game window into a [MediaStream] so the live render can
/// be displayed inside BioBase (same mechanism OBS uses for window capture).
class CaptureService {
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  MediaStream? _stream;
  bool _rendererReady = false;

  bool get active => _stream != null;

  Future<void> _ensureRenderer() async {
    if (_rendererReady) return;
    await renderer.initialize();
    _rendererReady = true;
  }

  /// Finds the CS2 window among capturable windows. Returns null when CS2
  /// isn't running or its window hasn't been created yet.
  Future<DesktopCapturerSource?> findCs2Window() async {
    final sources = await desktopCapturer.getSources(
      types: [SourceType.Window],
    );
    for (final s in sources) {
      if (s.name.trim() == 'Counter-Strike 2') return s;
    }
    for (final s in sources) {
      if (s.name.contains('Counter-Strike')) return s;
    }
    return null;
  }

  /// Starts capturing the CS2 window. Returns true when capture is live.
  Future<bool> start() async {
    if (_stream != null) return true;
    await _ensureRenderer();
    final source = await findCs2Window();
    if (source == null) return false;
    final stream = await navigator.mediaDevices.getDisplayMedia(
      <String, dynamic>{
        'video': {
          'deviceId': {'exact': source.id},
          'mandatory': {'frameRate': 60.0},
        },
        'audio': false,
      },
    );
    _stream = stream;
    renderer.srcObject = stream;
    return true;
  }

  Future<void> stop() async {
    renderer.srcObject = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
  }

  Future<void> dispose() async {
    await stop();
    if (_rendererReady) {
      await renderer.dispose();
      _rendererReady = false;
    }
  }
}
