import 'package:flutter/foundation.dart';

import 'native_demo_service.dart';

/// Shared state between Replay (which loads/parses demos and drives CS2) and
/// Review (which analyzes the same demo). Singleton — screens live side by
/// side in an IndexedStack.
class DemoSession extends ChangeNotifier {
  DemoSession._();
  static final DemoSession instance = DemoSession._();

  NativeDemo? demo;
  String? demoName;
  String? demoPath;

  /// Set by Review when the user taps a chart point; Replay consumes it and
  /// seeks (CS2 follows when live). The shell switches tabs on this signal.
  int? pendingSeekTick;

  void setDemo({
    required NativeDemo parsed,
    required String name,
    required String path,
  }) {
    demo = parsed;
    demoName = name;
    demoPath = path;
    pendingSeekTick = null;
    notifyListeners();
  }

  void clearDemo() {
    demo = null;
    demoName = null;
    demoPath = null;
    pendingSeekTick = null;
    notifyListeners();
  }

  void requestSeek(int tick) {
    pendingSeekTick = tick;
    notifyListeners();
  }

  void consumeSeek() {
    pendingSeekTick = null;
  }
}
