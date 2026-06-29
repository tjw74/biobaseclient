import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gsi_service.dart';

const int replayNetconPort = 2121;

class ReplayDemoTarget {
  final String sourcePath;
  final String consolePath;
  final String? stagedPath;
  final bool staged;

  const ReplayDemoTarget({
    required this.sourcePath,
    required this.consolePath,
    required this.stagedPath,
    required this.staged,
  });
}

class ReplayLaunchResult {
  final bool started;
  final String method;
  final List<String> diagnostics;

  const ReplayLaunchResult({
    required this.started,
    required this.method,
    required this.diagnostics,
  });
}

class ReplayLaunchService {
  Future<ReplayDemoTarget> prepareDemo(String sourcePath) async {
    final source = File(sourcePath);
    final absoluteSource = source.absolute.path;
    final csgoDir = await GsiService.findCs2GameCsgoPath();

    if (csgoDir != null && await source.exists()) {
      try {
        final replayDir = Directory(p.join(csgoDir, 'biobase_replays'));
        if (!await replayDir.exists()) {
          await replayDir.create(recursive: true);
        }

        final safeName = sanitizeDemoFileName(p.basename(source.path));
        final stagedPath = p.join(replayDir.path, safeName);
        final staged = File(stagedPath);
        var shouldCopy = source.absolute.path != staged.absolute.path;
        if (await staged.exists()) {
          final sourceStat = await source.stat();
          final stagedStat = await staged.stat();
          shouldCopy =
              sourceStat.size != stagedStat.size ||
              sourceStat.modified.isAfter(stagedStat.modified);
        }
        if (shouldCopy) {
          await source.copy(stagedPath);
        }

        return ReplayDemoTarget(
          sourcePath: absoluteSource,
          stagedPath: stagedPath,
          staged: true,
          consolePath: 'biobase_replays/$safeName',
        );
      } catch (_) {
        // Fall through to absolute-path playback. Some Steam library folders
        // are not writable from a normal user account.
      }
    }

    return ReplayDemoTarget(
      sourcePath: absoluteSource,
      stagedPath: null,
      staged: false,
      consolePath: normalizeConsolePath(absoluteSource),
    );
  }

  Future<ReplayLaunchResult> launchForReplay(ReplayDemoTarget demo) async {
    final diagnostics = <String>[];

    if (Platform.isWindows) {
      await _closeRunningCs2(diagnostics);
      await _ensureSteamRunning(diagnostics);

      final cs2Exe = await GsiService.findCs2Exe();
      if (cs2Exe != null) {
        final args = buildDirectLaunchArgs(demo.consolePath);
        diagnostics.add('Launching CS2 directly with Netcon + demo.');
        try {
          await Process.start(
            cs2Exe,
            args,
            mode: ProcessStartMode.detached,
            workingDirectory: File(cs2Exe).parent.path,
          );
          return ReplayLaunchResult(
            started: true,
            method: 'direct-cs2',
            diagnostics: diagnostics,
          );
        } catch (e) {
          diagnostics.add('Direct launch failed: $e');
        }
      } else {
        diagnostics.add('CS2 executable was not found from Steam cfg path.');
      }

      final steamExe = await findSteamExe();
      if (steamExe != null) {
        final args = buildSteamLaunchArgs(demo.consolePath);
        diagnostics.add('Falling back to Steam +playdemo launch.');
        try {
          await Process.start(steamExe, args, mode: ProcessStartMode.detached);
          return ReplayLaunchResult(
            started: true,
            method: 'steam-playdemo',
            diagnostics: diagnostics,
          );
        } catch (e) {
          diagnostics.add('Steam fallback failed: $e');
        }
      } else {
        diagnostics.add('Steam executable was not found.');
      }
    } else if (Platform.isMacOS) {
      try {
        await Process.start('open', [
          'steam://rungameid/730',
        ], mode: ProcessStartMode.detached);
        diagnostics.add('Opened CS2 through Steam on macOS.');
        return ReplayLaunchResult(
          started: true,
          method: 'steam-macos',
          diagnostics: diagnostics,
        );
      } catch (e) {
        diagnostics.add('macOS Steam launch failed: $e');
      }
    } else {
      diagnostics.add('Replay launch is only automated on Windows/macOS.');
    }

    return ReplayLaunchResult(
      started: false,
      method: 'none',
      diagnostics: diagnostics,
    );
  }

  static List<String> buildDirectLaunchArgs(String consoleDemoPath) => [
    '-novid',
    '-console',
    '-windowed',
    '-noborder',
    '-netconport',
    '$replayNetconPort',
    '+playdemo',
    consoleDemoPath,
  ];

  static List<String> buildSteamLaunchArgs(String consoleDemoPath) => [
    '-applaunch',
    '730',
    '-console',
    '+playdemo',
    consoleDemoPath,
  ];

  static String sanitizeDemoFileName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (!cleaned.toLowerCase().endsWith('.dem')) {
      cleaned = '$cleaned.dem';
    }
    if (cleaned == '.dem' || cleaned.trim().isEmpty) {
      cleaned = 'biobase_replay.dem';
    }
    return cleaned;
  }

  static String normalizeConsolePath(String path) => path.replaceAll('\\', '/');

  static Future<String?> findSteamExe() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\WOW6432Node\Valve\Steam',
        '/v',
        'InstallPath',
      ]);
      if (result.exitCode == 0) {
        final match = RegExp(
          r'REG_SZ\s+(.+)',
        ).firstMatch(result.stdout as String);
        if (match != null) {
          final exe = p.join(match.group(1)!.trim(), 'steam.exe');
          if (File(exe).existsSync()) return exe;
        }
      }
    } catch (_) {}

    for (final path in [
      r'C:\Program Files (x86)\Steam\steam.exe',
      r'C:\Program Files\Steam\steam.exe',
      r'D:\Steam\steam.exe',
      r'E:\Steam\steam.exe',
    ]) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> _closeRunningCs2(List<String> diagnostics) async {
    try {
      final taskCheck = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq cs2.exe',
        '/NH',
      ]);
      if ((taskCheck.stdout as String).contains('cs2.exe')) {
        diagnostics.add('Closing existing CS2 instance.');
        await Process.run('taskkill', ['/F', '/IM', 'cs2.exe']);
        await Future.delayed(const Duration(seconds: 3));
      }
    } catch (e) {
      diagnostics.add('Could not check/close existing CS2: $e');
    }
  }

  Future<void> _ensureSteamRunning(List<String> diagnostics) async {
    try {
      final steamCheck = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq steam.exe',
        '/NH',
      ]);
      if ((steamCheck.stdout as String).contains('steam.exe')) {
        diagnostics.add('Steam is already running.');
        return;
      }

      final steamExe = await findSteamExe();
      if (steamExe == null) {
        diagnostics.add('Steam is not running and steam.exe was not found.');
        return;
      }

      diagnostics.add('Starting Steam silently.');
      await Process.start(steamExe, [
        '-silent',
      ], mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(seconds: 8));
    } catch (e) {
      diagnostics.add('Could not start Steam: $e');
    }
  }
}
