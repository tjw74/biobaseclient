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

  test('Steam replay command line uses documented playdemo launch command', () {
    final commandLine = ReplayLaunchService.buildSteamReplayCommandLine(
      'biobase_replays/test.dem',
    );

    expect(
      commandLine,
      '-novid -console -netconport $replayNetconPort +playdemo biobase_replays/test.dem',
    );
  });

  test('Steam run URL uses documented double-slash command-line shape', () {
    final url = ReplayLaunchService.buildSteamRunUrl(
      'biobase_replays/test.dem',
    );

    expect(
      url,
      'steam://run/$cs2SteamAppId//-novid%20-console%20-netconport%20$replayNetconPort%20+playdemo%20biobase_replays%2Ftest.dem/',
    );
  });

  test('launch command quotes demo paths with whitespace', () {
    final commandLine = ReplayLaunchService.buildSteamReplayCommandLine(
      r'C:\Users\me\Counter Strike Demos\test demo.dem',
    );

    expect(
      commandLine,
      '-novid -console -netconport $replayNetconPort +playdemo "C:/Users/me/Counter Strike Demos/test demo.dem"',
    );
  });

  test('playdemo command quotes whitespace paths for manual diagnostics', () {
    expect(
      ReplayLaunchService.buildPlaydemoCommand('biobase_replays/test.dem'),
      'playdemo biobase_replays/test.dem',
    );
    expect(
      ReplayLaunchService.buildPlaydemoCommand('C:/demo files/test.dem'),
      'playdemo "C:/demo files/test.dem"',
    );
  });
}
