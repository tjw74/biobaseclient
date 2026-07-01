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

  test('replay cfg contains the selected playdemo command', () {
    final cfg = ReplayLaunchService.buildReplayExecConfig(
      'biobase_replays/test.dem',
    );

    expect(cfg, contains('con_enable "1"'));
    expect(cfg, contains('echo "BioBase Replay bootstrap: launching demo"'));
    expect(cfg, contains('disconnect'));
    expect(cfg, contains('playdemo "biobase_replays/test.dem"'));
    expect(cfg, contains('demo_timescale 1'));
    expect(cfg, contains('demo_resume'));
    expect(cfg, contains('demoui'));
  });

  test('autoexec bootstrap is marker-delimited and idempotent', () {
    const existing = 'sensitivity "1.2"\r\n';
    final patched = ReplayLaunchService.patchAutoexecContent(existing);
    final patchedAgain = ReplayLaunchService.patchAutoexecContent(patched);

    expect(patched, contains('sensitivity "1.2"'));
    expect(patched, contains(replayAutoexecBegin));
    expect(patched, contains('exec $replayExecConfigBase'));
    expect(patched, contains(replayAutoexecEnd));
    expect(patchedAgain, patched);
  });

  test('persistent Steam LaunchOptions add BioBase replay control args', () {
    final options = ReplayLaunchService.buildPersistentSteamLaunchOptions(
      '-novid -high -netconport 1234 +exec autoexec',
    );

    expect(options, contains('-novid'));
    expect(options, contains('-high'));
    expect(options, contains('+exec autoexec'));
    expect(options, contains('-console'));
    expect(options, contains('-condebug'));
    expect(options, contains('-netconport $replayNetconPort'));
    expect(options, contains('+exec $replayExecConfigBase'));
    expect(options, isNot(contains('-netconport 1234')));
  });

  test('Steam localconfig LaunchOptions are patched inside app 730 block', () {
    const vdf = r'''
"UserLocalConfigStore"
{
  "Software"
  {
    "Valve"
    {
      "Steam"
      {
        "Apps"
        {
          "730"
          {
            "LaunchOptions" "-novid -netconport 1234"
          }
        }
      }
    }
  }
}
''';

    final patched = ReplayLaunchService.patchSteamAppLaunchOptionsContent(vdf);

    expect(patched, isNotNull);
    expect(patched!, contains('"730"'));
    expect(patched, contains('"LaunchOptions"'));
    expect(patched, contains('-novid'));
    expect(patched, contains('-console'));
    expect(patched, contains('-condebug'));
    expect(patched, contains('-netconport $replayNetconPort'));
    expect(patched, contains('+exec $replayExecConfigBase'));
    expect(patched, isNot(contains('-netconport 1234')));
  });

  test(
    'Steam localconfig LaunchOptions are inserted when app 730 has none',
    () {
      const vdf = r'''
"Apps"
{
  "730"
  {
    "LastPlayed" "1"
  }
}
''';

      final patched = ReplayLaunchService.patchSteamAppLaunchOptionsContent(
        vdf,
      );

      expect(patched, isNotNull);
      expect(patched!, contains('"LastPlayed" "1"'));
      expect(patched, contains('"LaunchOptions"'));
      expect(patched, contains('-netconport $replayNetconPort'));
      expect(patched, contains('+exec $replayExecConfigBase'));
    },
  );

  test('Steam replay command line launches cfg bootstrap only', () {
    final commandLine = ReplayLaunchService.buildSteamReplayCommandLine(
      'biobase_replays/test.dem',
    );

    expect(
      commandLine,
      '-novid -console -condebug -netconport $replayNetconPort +exec $replayExecConfigBase',
    );
  });

  test('Windows Steam app launch args pass cfg bootstrap only', () {
    final args = ReplayLaunchService.buildSteamAppLaunchArgs(
      'biobase_replays/test.dem',
    );

    expect(args, [
      '-applaunch',
      '$cs2SteamAppId',
      '-novid',
      '-console',
      '-condebug',
      '-netconport',
      '$replayNetconPort',
      '+exec',
      replayExecConfigBase,
    ]);
    expect(
      ReplayLaunchService.formatLaunchCommand(args),
      '-applaunch $cs2SteamAppId -novid -console -condebug -netconport $replayNetconPort +exec $replayExecConfigBase',
    );
  });

  test('Steam run URL uses double-slash command-line shape', () {
    final url = ReplayLaunchService.buildSteamRunUrl(
      'biobase_replays/test.dem',
    );

    expect(
      url,
      'steam://run/$cs2SteamAppId//-novid%20-console%20-condebug%20-netconport%20$replayNetconPort%20+exec%20$replayExecConfigBase/',
    );
  });

  test('launch command quotes demo paths with whitespace', () {
    final commandLine = ReplayLaunchService.buildSteamReplayCommandLine(
      r'C:\Users\me\Counter Strike Demos\test demo.dem',
    );

    expect(
      commandLine,
      '-novid -console -condebug -netconport $replayNetconPort +exec $replayExecConfigBase',
    );
  });

  test('playdemo command quotes whitespace paths for manual diagnostics', () {
    expect(
      ReplayLaunchService.buildPlaydemoCommand('biobase_replays/test.dem'),
      'playdemo "biobase_replays/test.dem"',
    );
    expect(
      ReplayLaunchService.buildPlaydemoCommand('C:/demo files/test.dem'),
      'playdemo "C:/demo files/test.dem"',
    );
  });
}
