import 'dart:convert';
import 'dart:io';

import 'native_demo_service.dart';

/// Generates `<demo>.dem.json` watch-sequence files executed by the in-game
/// plugin at exact ticks (CS Demo Manager's VDM-replacement format: a JSON
/// array of sequences, each an array of {cmd, tick} actions).
class ActionsFileService {
  static const double _beforeKillSec = 4.0;
  static const double _afterKillSec = 2.0;

  final List<Map<String, Object>> _actions = [];

  void _add(int tick, String cmd) {
    _actions.add({'cmd': cmd, 'tick': tick < 0 ? 0 : tick});
  }

  void _spec(int tick, String playerName) {
    // spec_mode before spec_player, or the camera can stay in free mode.
    _add(tick, 'spec_mode 1');
    _add(tick, 'spec_player "${playerName.replaceAll('"', '')}"');
  }

  void _goto(int atTick, int toTick) {
    _add(atTick, 'demo_gototick $toTick');
  }

  /// Jump straight to a marked move and lock onto a player.
  static Future<String> writeMoveJump({
    required String stagedDemoPath,
    required NativeDemo demo,
    required int startTick,
    required int endTick,
    String? focusPlayerName,
  }) async {
    final g = ActionsFileService();
    final rate = demo.tickRateGuess <= 0 ? 64 : demo.tickRateGuess;
    final lead = (1.5 * rate).round();
    final entry = demo.startTick + rate; // earliest reliable action tick
    final target = (startTick - lead).clamp(demo.startTick, demo.endTick);
    g._goto(entry, target);
    if (focusPlayerName != null) {
      g._spec(target, focusPlayerName);
    }
    return g._write(stagedDemoPath);
  }

  /// Kill-to-kill (or death-to-death) reel for one player: skip everything
  /// between the moments, locked to their POV.
  static Future<String> writeReel({
    required String stagedDemoPath,
    required NativeDemo demo,
    required List<int> momentTicks,
    required String playerName,
  }) async {
    final g = ActionsFileService();
    final rate = demo.tickRateGuess <= 0 ? 64 : demo.tickRateGuess;
    final before = (_beforeKillSec * rate).round();
    final after = (_afterKillSec * rate).round();
    final ticks = [...momentTicks]..sort();

    var cursor = demo.startTick + rate;
    for (final moment in ticks) {
      final segmentStart = (moment - before).clamp(
        demo.startTick,
        demo.endTick,
      );
      if (segmentStart > cursor) {
        g._goto(cursor, segmentStart);
      }
      g._spec(segmentStart > cursor ? segmentStart : cursor, playerName);
      cursor = (moment + after).clamp(demo.startTick, demo.endTick);
    }
    // Stop at the end of the last moment instead of playing out the demo.
    g._add(cursor, 'disconnect');
    return g._write(stagedDemoPath);
  }

  static Future<void> deleteFor(String stagedDemoPath) async {
    try {
      final f = File('$stagedDemoPath.json');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<String> _write(String stagedDemoPath) async {
    final path = '$stagedDemoPath.json';
    final sequences = [
      {'actions': _actions},
    ];
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(sequences),
    );
    return path;
  }
}
