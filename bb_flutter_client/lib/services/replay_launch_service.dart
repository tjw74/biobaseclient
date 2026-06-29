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

    final commands = buildConsoleFallbackCommands(demo.consolePath);
    final script = buildWindowsConsoleInjectionScript(commands);
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 15));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static List<String> buildDirectLaunchArgs(String consoleDemoPath) => [
    '-steam',
    '-novid',
    '-console',
    '-dev',
    '-condebug',
    '-windowed',
    '-noborder',
    '-netconport',
    '$replayNetconPort',
    '+con_enable',
    '1',
    '+bind',
    '`',
    'toggleconsole',
    '+bind',
    'F8',
    'toggleconsole',
    '+toggleconsole',
    '+exec',
    replayExecConfigName,
    '+playdemo',
    consoleDemoPath,
  ];

  static List<String> buildSteamLaunchArgs(String consoleDemoPath) => [
    '-applaunch',
    '730',
    '-console',
    '-dev',
    '-netconport',
    '$replayNetconPort',
    '+con_enable',
    '1',
    '+bind',
    '`',
    'toggleconsole',
    '+bind',
    'F8',
    'toggleconsole',
    '+toggleconsole',
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
    return [
      '// Generated by BioBase. Safe to overwrite.',
      'con_enable "1"',
      'bind "`" "toggleconsole"',
      'bind "F8" "toggleconsole"',
      'echo "BioBase replay bootstrap"',
      buildPlaydemoCommand(consoleDemoPath),
      'demo_resume',
      '',
    ].join('\r\n');
  }

  static List<String> buildConsoleFallbackCommands(String consoleDemoPath) => [
    'exec ${replayExecConfigName.replaceAll('.cfg', '')}',
    buildPlaydemoCommand(consoleDemoPath),
  ];

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

  static String buildWindowsConsoleInjectionScript(List<String> commands) {
    final commandText = commands.join('\r\n');
    final psCommandText = commandText.replaceAll("'@", "' + '@' + '");
    return '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BioBaseInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public UInt32 type;
    public INPUTUNION U;
  }
  [StructLayout(LayoutKind.Explicit)]
  public struct INPUTUNION {
    [FieldOffset(0)] public KEYBDINPUT ki;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public UInt16 wVk;
    public UInt16 wScan;
    public UInt32 dwFlags;
    public UInt32 time;
    public IntPtr dwExtraInfo;
  }
  [DllImport("user32.dll", SetLastError=true)]
  public static extern UInt32 SendInput(UInt32 nInputs, INPUT[] pInputs, Int32 cbSize);
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern UInt32 MapVirtualKey(UInt32 uCode, UInt32 uMapType);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern short VkKeyScan(char ch);
  public const UInt32 INPUT_KEYBOARD = 1;
  public const UInt32 KEYEVENTF_KEYUP = 0x0002;
  public const UInt32 KEYEVENTF_SCANCODE = 0x0008;
  public const UInt16 VK_BACK = 0x08;
  public const UInt16 VK_RETURN = 0x0D;
  public const UInt16 VK_SHIFT = 0x10;
  public const UInt16 VK_CONTROL = 0x11;
  public const UInt16 VK_MENU = 0x12;
  public const UInt16 VK_A = 0x41;
  public const UInt16 VK_V = 0x56;
  public const UInt16 VK_F8 = 0x77;
  public const UInt16 VK_OEM_3 = 0xC0;
  public static void Key(UInt16 vk, bool up) {
    UInt16 scan = (UInt16)MapVirtualKey(vk, 0);
    INPUT[] inputs = new INPUT[1];
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].U.ki.wVk = 0;
    inputs[0].U.ki.wScan = scan;
    inputs[0].U.ki.dwFlags = KEYEVENTF_SCANCODE | (up ? KEYEVENTF_KEYUP : 0);
    SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Press(UInt16 vk) {
    Key(vk, false);
    Key(vk, true);
  }
  public static void CtrlV() {
    Key(VK_CONTROL, false);
    Press(VK_V);
    Key(VK_CONTROL, true);
  }
  public static void CtrlA() {
    Key(VK_CONTROL, false);
    Press(VK_A);
    Key(VK_CONTROL, true);
  }
  public static void ForceForeground(IntPtr hWnd) {
    if (IsIconic(hWnd)) { ShowWindowAsync(hWnd, 9); }
    ShowWindowAsync(hWnd, 5);
    BringWindowToTop(hWnd);
    Key(VK_MENU, false);
    SetForegroundWindow(hWnd);
    Key(VK_MENU, true);
    SetForegroundWindow(hWnd);
  }
  public static void Text(string text) {
    foreach (char c in text) {
      short key = VkKeyScan(c);
      if (key == -1) { continue; }
      UInt16 vk = (UInt16)(key & 0xff);
      UInt16 mods = (UInt16)((key >> 8) & 0xff);
      if ((mods & 1) != 0) { Key(VK_SHIFT, false); }
      if ((mods & 2) != 0) { Key(VK_CONTROL, false); }
      if ((mods & 4) != 0) { Key(VK_MENU, false); }
      Press(vk);
      if ((mods & 4) != 0) { Key(VK_MENU, true); }
      if ((mods & 2) != 0) { Key(VK_CONTROL, true); }
      if ((mods & 1) != 0) { Key(VK_SHIFT, true); }
    }
  }
}
"@
\$commandsText = @'
$psCommandText
'@
\$commands = \$commandsText -split "``r?``n" | Where-Object { \$_.Trim().Length -gt 0 }
\$proc = Get-Process cs2 -ErrorAction SilentlyContinue | Where-Object { \$_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not \$proc) { exit 2 }
[BioBaseInput]::ForceForeground(\$proc.MainWindowHandle)
Start-Sleep -Milliseconds 900
function Send-BioBaseReplayCommands {
  foreach (\$command in \$commands) {
    [BioBaseInput]::CtrlA()
    Start-Sleep -Milliseconds 60
    [BioBaseInput]::Press([BioBaseInput]::VK_BACK)
    Start-Sleep -Milliseconds 80
    Set-Clipboard -Value \$command
    [BioBaseInput]::CtrlV()
    Start-Sleep -Milliseconds 140
    [BioBaseInput]::Press([BioBaseInput]::VK_RETURN)
    Start-Sleep -Milliseconds 650
    [BioBaseInput]::CtrlA()
    Start-Sleep -Milliseconds 60
    [BioBaseInput]::Press([BioBaseInput]::VK_BACK)
    Start-Sleep -Milliseconds 80
    [BioBaseInput]::Text(\$command)
    Start-Sleep -Milliseconds 120
    [BioBaseInput]::Press([BioBaseInput]::VK_RETURN)
    Start-Sleep -Milliseconds 850
  }
}
Send-BioBaseReplayCommands
[BioBaseInput]::Press([BioBaseInput]::VK_OEM_3)
Start-Sleep -Milliseconds 900
Send-BioBaseReplayCommands
[BioBaseInput]::Press([BioBaseInput]::VK_OEM_3)
Start-Sleep -Milliseconds 500
[BioBaseInput]::Press([BioBaseInput]::VK_F8)
Start-Sleep -Milliseconds 900
Send-BioBaseReplayCommands
''';
  }

  @Deprecated(
    'Use buildWindowsConsoleInjectionScript; kept for test/backcompat.',
  )
  static String buildWindowsConsolePasteScript(List<String> commands) {
    return buildWindowsConsoleInjectionScript(commands);
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
