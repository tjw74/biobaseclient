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
      expect(args, contains('-dev'));
      expect(args, containsAll(['-netconport', '$replayNetconPort']));
      expect(args, containsAll(['+con_enable', '1']));
      expect(args, contains('+toggleconsole'));
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
      expect(args, contains('-dev'));
      expect(args, containsAll(['-netconport', '$replayNetconPort']));
      expect(args, containsAll(['+con_enable', '1']));
      expect(args, contains('+toggleconsole'));
      expect(args, containsAll(['+exec', replayExecConfigName]));
      expect(args, containsAll(['+playdemo', 'biobase_replays/test.dem']));
    },
  );

  test('replay exec cfg starts the selected demo', () {
    final cfg = ReplayLaunchService.buildReplayExecConfig(
      'biobase_replays/test.dem',
    );

    expect(cfg, contains('con_enable "1"'));
    expect(cfg, contains('bind "`" "toggleconsole"'));
    expect(cfg, contains('bind "F8" "toggleconsole"'));
    expect(cfg, contains('playdemo biobase_replays/test.dem'));
    expect(cfg, contains('demo_resume'));
  });

  test(
    'console fallback executes cfg and playdemo through multiple input paths',
    () {
      final commands = ReplayLaunchService.buildConsoleFallbackCommands(
        'biobase_replays/test.dem',
      );
      final script = ReplayLaunchService.buildWindowsConsoleInjectionScript(
        commands,
      );

      expect(commands, [
        'exec biobase_replay',
        'playdemo biobase_replays/test.dem',
      ]);
      expect(script, contains('Get-Process cs2'));
      expect(script, contains('SetForegroundWindow'));
      expect(script, contains('BringWindowToTop'));
      expect(script, contains('ForceForeground'));
      expect(script, contains('Set-Clipboard -Value'));
      expect(script, contains('playdemo biobase_replays/test.dem'));
      expect(script, contains('SendInput'));
      expect(script, contains('KEYEVENTF_SCANCODE'));
      expect(script, contains('VkKeyScan'));
      expect(script, contains('MapVirtualKey'));
      expect(script, contains('CtrlV'));
      expect(script, contains('CtrlA'));
      expect(script, contains('VK_BACK'));
      expect(script, contains('VK_OEM_3'));
      expect(script, contains('VK_F8'));
      expect(script, contains('Send-BioBaseReplayCommands'));
      expect(script, contains('foreach'));
      expect(script, contains('BioBaseInput'));
    },
  );
}
