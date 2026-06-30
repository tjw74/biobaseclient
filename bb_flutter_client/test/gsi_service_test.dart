import 'package:biobase_client/services/gsi_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Steam library VDF parser reads structured and legacy paths', () {
    const vdf = r'''
"libraryfolders"
{
  "0"
  {
    "path" "C:\\Program Files (x86)\\Steam"
    "apps"
    {
      "730" "123456"
    }
  }
  "1" "D:\\SteamLibrary"
  "2"
  {
    "path" "E:\\Games\\Steam Library"
  }
}
''';

    final libraries = GsiService.steamLibraryPathsFromVdf(
      vdf,
      steamRoot: r'C:\Program Files (x86)\Steam',
    );

    expect(libraries, contains(r'C:\Program Files (x86)\Steam'));
    expect(libraries, contains(r'D:\SteamLibrary'));
    expect(libraries, contains(r'E:\Games\Steam Library'));
    expect(
      libraries.where((path) => path.contains('Program Files')),
      hasLength(1),
    );
  });

  test('CS2 cfg candidate is derived from a Steam library root', () {
    final cfgPath = GsiService.cs2CfgPathForSteamLibrary(r'D:\SteamLibrary');

    expect(cfgPath, contains('steamapps'));
    expect(cfgPath, contains('Counter-Strike Global Offensive'));
    expect(cfgPath, contains('game'));
    expect(cfgPath, contains('csgo'));
    expect(cfgPath, contains('cfg'));
  });
}
