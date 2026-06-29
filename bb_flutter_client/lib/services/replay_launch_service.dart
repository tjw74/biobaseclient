import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gsi_service.dart';

const int cs2SteamAppId = 730;
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
    final steamUrl = buildSteamRunUrl(demo.consolePath);
    final commandLine = buildSteamReplayCommandLine(demo.consolePath);

    if (Platform.isWindows) {
      await _closeRunningCs2(diagnostics);
      await _ensureSteamRunning(diagnostics);

      final steamExe = await findSteamExe();
      if (steamExe != null) {
        final args = buildSteamAppLaunchArgs(demo.consolePath);
        diagnostics.add(
          'Launching CS2 through steam.exe -applaunch with explicit replay args.',
        );
        diagnostics.add('Launch command: ${formatLaunchCommand(args)}');
        try {
          await Process.start(steamExe, args, mode: ProcessStartMode.detached);
          return ReplayLaunchResult(
            started: true,
            method: 'steam-applaunch-playdemo',
            diagnostics: diagnostics,
          );
        } catch (e) {
          diagnostics.add('Steam -applaunch failed: $e');
        }
      } else {
        diagnostics.add('Steam executable was not found; trying Steam URL.');
      }

      diagnostics.add(
        'Falling back to Steam URL with documented launch command line.',
      );
      diagnostics.add('Launch command: $commandLine');
      try {
        await openSteamRunUrl(steamUrl);
        return ReplayLaunchResult(
          started: true,
          method: 'steam-url-playdemo',
          diagnostics: diagnostics,
        );
      } catch (e) {
        diagnostics.add('Steam URL launch failed: $e');
      }
    } else if (Platform.isMacOS) {
      try {
        await openSteamRunUrl(steamUrl);
        diagnostics.add(
          'Opened CS2 through Steam URL with documented launch command line.',
        );
        diagnostics.add('Launch command: $commandLine');
        return ReplayLaunchResult(
          started: true,
          method: 'steam-url-playdemo',
          diagnostics: diagnostics,
        );
      } catch (e) {
        diagnostics.add('macOS Steam URL launch failed: $e');
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

  static String buildSteamReplayCommandLine(String consoleDemoPath) {
    return [
      '-novid',
      '-console',
      '-netconport',
      '$replayNetconPort',
      '+playdemo',
      quoteLaunchCommandArg(consoleDemoPath),
    ].join(' ');
  }

  static List<String> buildSteamAppLaunchArgs(String consoleDemoPath) => [
    '-applaunch',
    '$cs2SteamAppId',
    '-novid',
    '-console',
    '-netconport',
    '$replayNetconPort',
    '+playdemo',
    consoleDemoPath,
  ];

  static String formatLaunchCommand(List<String> args) {
    return args.map(quoteLaunchCommandArg).join(' ');
  }

  static String buildSteamRunUrl(String consoleDemoPath) {
    final commandLine = buildSteamReplayCommandLine(consoleDemoPath);
    final encoded = Uri.encodeComponent(commandLine).replaceAll('%2B', '+');
    return 'steam://run/$cs2SteamAppId//$encoded/';
  }

  static Future<void> openSteamRunUrl(String steamUrl) async {
    if (Platform.isWindows) {
      try {
        await Process.start('rundll32.exe', [
          'url.dll,FileProtocolHandler',
          steamUrl,
        ], mode: ProcessStartMode.detached);
        return;
      } catch (_) {
        final steamExe = await findSteamExe();
        if (steamExe == null) rethrow;
        await Process.start(steamExe, [
          steamUrl,
        ], mode: ProcessStartMode.detached);
        return;
      }
    }

    if (Platform.isMacOS) {
      await Process.start('open', [steamUrl], mode: ProcessStartMode.detached);
      return;
    }

    await Process.start('xdg-open', [
      steamUrl,
    ], mode: ProcessStartMode.detached);
  }

  static String quoteLaunchCommandArg(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (!RegExp(r'\s|"').hasMatch(normalized)) return normalized;
    final escaped = normalized.replaceAll('"', r'\"');
    return '"$escaped"';
  }

  static String buildPlaydemoCommand(String consoleDemoPath) {
    final escapedPath = escapeCfgString(consoleDemoPath);
    if (RegExp(r'\s').hasMatch(escapedPath)) {
      return 'playdemo "$escapedPath"';
    }
    return 'playdemo $escapedPath';
  }

  static String escapeCfgString(String value) {
    return value.replaceAll('\\', '/').replaceAll('"', r'\"');
  }

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
        diagnostics.add('Closing existing CS2 instance before replay launch.');
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
