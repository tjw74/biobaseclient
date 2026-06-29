import 'package:biobase_client/services/replay_launch_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo filenames are sanitized for CS2 staging', () {
    expect(
      ReplayLaunchService.sanitizeDemoFileName('NAVI vs Spirit map 1.dem'),
      'NAVI_vs_Spirit_map_1.dem',
    );
    expect(ReplayLaunchService.sanitizeDemoFileName('mirage'), 'mirage.dem');
  });

  test('console paths use forward slashes', () {
    expect(
      ReplayLaunchService.normalizeConsolePath(r'C:\Users\me\demo.dem'),
      'C:/Users/me/demo.dem',
    );
  });

  test(
    'direct CS2 launch includes steam context, netcon, exec cfg, and playdemo',
    () {
      final args = ReplayLaunchService.buildDirectLaunchArgs(
        'biobase_replays/test.dem',
      );

      expect(args, contains('-steam'));
      expect(args, containsAll(['-netconport', '$replayNetconPort']));
      expect(args, containsAll(['+exec', replayExecConfigName]));
      expect(args, containsAll(['+playdemo', 'biobase_replays/test.dem']));
      expect(args.indexOf('+exec'), lessThan(args.indexOf('+playdemo')));
    },
  );

  test(
    'Steam fallback carries the same replay cfg and netcon launch options',
    () {
      final args = ReplayLaunchService.buildSteamLaunchArgs(
        'biobase_replays/test.dem',
      );

      expect(args.take(2), ['-applaunch', '730']);
      expect(args, containsAll(['-netconport', '$replayNetconPort']));
      expect(args, containsAll(['+exec', replayExecConfigName]));
      expect(args, containsAll(['+playdemo', 'biobase_replays/test.dem']));
    },
  );

  test('replay exec cfg starts the selected demo', () {
    final cfg = ReplayLaunchService.buildReplayExecConfig(
      'biobase_replays/test.dem',
    );

    expect(cfg, contains('con_enable "1"'));
    expect(cfg, contains('playdemo "biobase_replays/test.dem"'));
    expect(cfg, contains('demo_resume'));
  });

  test('Windows console fallback focuses CS2 and pastes playdemo command', () {
    final script = ReplayLaunchService.buildWindowsConsolePasteScript(
      ReplayLaunchService.buildPlaydemoCommand('biobase_replays/test.dem'),
    );

    expect(script, contains('Get-Process cs2'));
    expect(script, contains('SetForegroundWindow'));
    expect(script, contains('Set-Clipboard -Value'));
    expect(script, contains('playdemo "biobase_replays/test.dem"'));
    expect(script, contains('SendKeys'));
  });
}
