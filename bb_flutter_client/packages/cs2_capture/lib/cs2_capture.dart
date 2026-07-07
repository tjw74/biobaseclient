import 'dart:io';

import 'package:flutter/services.dart';

/// Result of starting a window capture.
class Cs2CaptureSession {
  final int textureId;
  final int width;
  final int height;

  const Cs2CaptureSession({
    required this.textureId,
    required this.width,
    required this.height,
  });

  double get aspectRatio => height == 0 ? 16 / 9 : width / height;
}

/// Windows Graphics Capture of the CS2 window (the API OBS uses for game
/// windows — BitBlt-style capture returns black for Direct3D games).
class Cs2Capture {
  static const MethodChannel _channel = MethodChannel('biobase/cs2_capture');

  /// Starts capturing the first visible window whose title contains
  /// [titleContains]. Returns null when no such window exists (e.g. CS2 not
  /// running yet) or on non-Windows platforms.
  static Future<Cs2CaptureSession?> start({
    String titleContains = 'Counter-Strike',
  }) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('start', {
        'title': titleContains,
      });
      if (result == null) return null;
      final id = result['textureId'] as int?;
      if (id == null || id < 0) return null;
      return Cs2CaptureSession(
        textureId: id,
        width: (result['width'] as int?) ?? 1920,
        height: (result['height'] as int?) ?? 1080,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
