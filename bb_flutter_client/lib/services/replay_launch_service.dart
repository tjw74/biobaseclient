import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gsi_service.dart';

const int replayNetconPort = 2121;
const String replayExecConfigName = 'biobase_replay.cfg';

class ReplayDemoTarget {
  final String sourcePath;
  final String consolePath;
  final String? stagedPath;
  final String? execConfigPath;
  final bool staged;
  final bool execConfigInstalled;

  const ReplayDemoTarget({
    required this.sourcePath,
    required this.consolePath,
    required this.stagedPath,
    required this.execConfigPath,
    required this.staged,
    required this.execConfigInstalled,
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
    final cfgPath = await GsiService.findCs2CfgPath();

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

        final consolePath = 'biobase_replays/$safeName';
        final execConfigPath = cfgPath == null
            ? null
            : p.join(cfgPath, replayExecConfigName);
        final execInstalled = execConfigPath == null
            ? false
            : await writeReplayExecConfig(execConfigPath, consolePath);

        return ReplayDemoTarget(
          sourcePath: absoluteSource,
          stagedPath: stagedPath,
          execConfigPath: execConfigPath,
          staged: true,
          execConfigInstalled: execInstalled,
          consolePath: consolePath,
        );
      } catch (_) {
        // Fall through to absolute-path playback. Some Steam library folders
        // are not writable from a normal user account.
      }
    }

    final consolePath = normalizeConsolePath(absoluteSource);
    final execConfigPath = cfgPath == null
        ? null
        : p.join(cfgPath, replayExecConfigName);
    final execInstalled = execConfigPath == null
        ? false
        : await writeReplayExecConfig(execConfigPath, consolePath);

    return ReplayDemoTarget(
      sourcePath: absoluteSource,
      stagedPath: null,
      execConfigPath: execConfigPath,
      staged: false,
      execConfigInstalled: execInstalled,
      consolePath: consolePath,
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
        diagnostics.add('Launching CS2 directly with Netcon + replay cfg.');
        try {
          await Process.start(
            cs2Exe,
            args,
            mode: ProcessStartMode.detached,
            workingDirectory: File(cs2Exe).parent.path,
          );
          return ReplayLaunchResult(
            started: true,
            method: 'direct-cs2-cfg',
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
        diagnostics.add('Falling back to Steam replay cfg launch.');
        try {
          await Process.start(steamExe, args, mode: ProcessStartMode.detached);
          return ReplayLaunchResult(
            started: true,
            method: 'steam-replay-cfg',
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

  Future<bool> sendPlaydemoConsoleFallback(ReplayDemoTarget demo) async {
    if (!Platform.isWindows) return false;

    final command = buildPlaydemoCommand(demo.consolePath);
    final script = buildWindowsConsolePasteScript(command);
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 12));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static List<String> buildDirectLaunchArgs(String consoleDemoPath) => [
    '-steam',
    '-novid',
    '-console',
    '-condebug',
    '-windowed',
    '-noborder',
    '-netconport',
    '$replayNetconPort',
    '+exec',
    replayExecConfigName,
    '+playdemo',
    consoleDemoPath,
  ];

  static List<String> buildSteamLaunchArgs(String consoleDemoPath) => [
    '-applaunch',
    '730',
    '-console',
    '-netconport',
    '$replayNetconPort',
    '+exec',
    replayExecConfigName,
    '+playdemo',
    consoleDemoPath,
  ];

  static Future<bool> writeReplayExecConfig(
    String configPath,
    String consoleDemoPath,
  ) async {
    try {
      final file = File(configPath);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsString(buildReplayExecConfig(consoleDemoPath));
      return true;
    } catch (_) {
      return false;
    }
  }

  static String buildReplayExecConfig(String consoleDemoPath) {
    final escapedPath = escapeCfgString(consoleDemoPath);
    return [
      '// Generated by BioBase. Safe to overwrite.',
      'con_enable "1"',
      'echo "BioBase replay bootstrap"',
      'playdemo "$escapedPath"',
      'demo_resume',
      '',
    ].join('\r\n');
  }

  static String buildPlaydemoCommand(String consoleDemoPath) {
    return 'playdemo "${escapeCfgString(consoleDemoPath)}"';
  }

  static String escapeCfgString(String value) {
    return value.replaceAll('\\', '/').replaceAll('"', r'\"');
  }

  static String buildWindowsConsolePasteScript(String command) {
    final psCommand = command.replaceAll("'", "''");
    return '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BioBaseWin32 {
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@
\$proc = Get-Process cs2 -ErrorAction SilentlyContinue | Where-Object { \$_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not \$proc) { exit 2 }
[BioBaseWin32]::ShowWindowAsync(\$proc.MainWindowHandle, 9) | Out-Null
Start-Sleep -Milliseconds 350
[BioBaseWin32]::SetForegroundWindow(\$proc.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 350
Set-Clipboard -Value '$psCommand'
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait("``")
Start-Sleep -Milliseconds 250
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
''';
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
