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

  test('direct CS2 launch includes netcon and launch-time playdemo', () {
    final args = ReplayLaunchService.buildDirectLaunchArgs(
      'biobase_replays/test.dem',
    );

    expect(args, containsAll(['-netconport', '$replayNetconPort']));
    expect(args, containsAll(['+playdemo', 'biobase_replays/test.dem']));
    expect(args.indexOf('+playdemo'), lessThan(args.length - 1));
  });

  test('Steam fallback launches the demo without claiming netcon control', () {
    final args = ReplayLaunchService.buildSteamLaunchArgs(
      'biobase_replays/test.dem',
    );

    expect(args.take(2), ['-applaunch', '730']);
    expect(args, containsAll(['+playdemo', 'biobase_replays/test.dem']));
    expect(args, isNot(contains('-netconport')));
  });
}
