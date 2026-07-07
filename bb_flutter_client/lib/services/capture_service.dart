import 'package:cs2_capture/cs2_capture.dart';

/// Captures the CS2 game window into a Flutter texture so the live render can
/// be displayed inside BioBase. Uses Windows Graphics Capture (the API OBS
/// uses for game windows — BitBlt-style capture returns black frames for
/// Direct3D games).
class CaptureService {
  Cs2CaptureSession? _session;

  bool get active => _session != null;
  int? get textureId => _session?.textureId;
  double get aspectRatio => _session?.aspectRatio ?? 16 / 9;

  /// Starts capturing the CS2 window. Returns true when capture is live,
  /// false when the CS2 window doesn't exist yet.
  Future<bool> start() async {
    if (_session != null) return true;
    _session = await Cs2Capture.start();
    return _session != null;
  }

  Future<void> stop() async {
    if (_session == null) return;
    _session = null;
    await Cs2Capture.stop();
  }

  Future<void> dispose() => stop();
}
