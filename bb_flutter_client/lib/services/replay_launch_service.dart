import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gsi_service.dart';

const int cs2SteamAppId = 730;
const int replayNetconPort = 2121;
const String replayExecConfigBase = 'biobase_replay';
const String replayExecConfigName = '$replayExecConfigBase.cfg';
const String replayAutoexecBegin = '// BEGIN BIOBASE REPLAY BOOTSTRAP';
const String replayAutoexecEnd = '// END BIOBASE REPLAY BOOTSTRAP';
const List<String> replaySteamLaunchOptionTokens = [
  '-console',
  '-condebug',
  '-netconport',
  '2121',
  '+exec',
  replayExecConfigBase,
];

class ReplayDemoTarget {
  final String sourcePath;
  final String consolePath;
  final String? stagedPath;
  final String? replayConfigPath;
  final String? autoexecPath;
  final bool staged;
  final bool replayConfigInstalled;
  final bool autoexecPatched;

  const ReplayDemoTarget({
    required this.sourcePath,
    required this.consolePath,
    required this.stagedPath,
    required this.replayConfigPath,
    required this.autoexecPath,
    required this.staged,
    required this.replayConfigInstalled,
    required this.autoexecPatched,
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
  Timer? _bootstrapCleanupTimer;

  Future<ReplayDemoTarget> prepareDemo(String sourcePath) async {
    final source = File(sourcePath);
    final absoluteSource = source.absolute.path;
    final csgoDir = await GsiService.findCs2GameCsgoPath();
    final cfgPath = await GsiService.findCs2CfgPath();

    ReplayBootstrapInstall bootstrap = const ReplayBootstrapInstall.none();

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
        bootstrap = await installReplayBootstrap(cfgPath, consolePath);

        return ReplayDemoTarget(
          sourcePath: absoluteSource,
          stagedPath: stagedPath,
          replayConfigPath: bootstrap.replayConfigPath,
          autoexecPath: bootstrap.autoexecPath,
          staged: true,
          replayConfigInstalled: bootstrap.replayConfigInstalled,
          autoexecPatched: bootstrap.autoexecPatched,
          consolePath: consolePath,
        );
      } catch (_) {
        // Fall through to absolute-path playback. Some Steam library folders
        // are not writable from a normal user account.
      }
    }

    final consolePath = normalizeConsolePath(absoluteSource);
    bootstrap = await installReplayBootstrap(cfgPath, consolePath);
    return ReplayDemoTarget(
      sourcePath: absoluteSource,
      stagedPath: null,
      replayConfigPath: bootstrap.replayConfigPath,
      autoexecPath: bootstrap.autoexecPath,
      staged: false,
      replayConfigInstalled: bootstrap.replayConfigInstalled,
      autoexecPatched: bootstrap.autoexecPatched,
      consolePath: consolePath,
    );
  }

  Future<ReplayLaunchResult> launchForReplay(ReplayDemoTarget demo) async {
    final diagnostics = <String>[
      demo.replayConfigInstalled
          ? 'Replay cfg installed at ${demo.replayConfigPath}'
          : 'Replay cfg was not installed; using launch args only.',
      demo.autoexecPatched
          ? 'Autoexec bootstrap is installed at ${demo.autoexecPath}'
          : 'Autoexec bootstrap was not installed.',
    ];
    final steamUrl = buildSteamRunUrl(demo.consolePath);
    final commandLine = buildSteamReplayCommandLine(demo.consolePath);

    if (Platform.isWindows) {
      await _closeRunningCs2(diagnostics);
      await _installSteamReplayLaunchOptions(diagnostics);

      final steamExe = await findSteamExe();
      if (steamExe != null) {
        final args = buildSteamAppLaunchArgs(demo.consolePath);
        diagnostics.add(
          'Launching Steam and CS2 in one documented -applaunch call with replay cfg bootstrap.',
        );
        diagnostics.add('Launch command: ${formatLaunchCommand(args)}');
        try {
          await Process.start(steamExe, args, mode: ProcessStartMode.detached);
          _scheduleReplayBootstrapCleanup(demo, diagnostics);
          return ReplayLaunchResult(
            started: true,
            method: 'steam-applaunch-cfg-bootstrap',
            diagnostics: diagnostics,
          );
        } catch (e) {
          diagnostics.add('Steam -applaunch failed: $e');
        }
      } else {
        diagnostics.add('Steam executable was not found; trying Steam URL.');
      }

      diagnostics.add('Falling back to Steam URL launch with replay cfg.');
      diagnostics.add('Launch command: $commandLine');
      try {
        await openSteamRunUrl(steamUrl);
        _scheduleReplayBootstrapCleanup(demo, diagnostics);
        return ReplayLaunchResult(
          started: true,
          method: 'steam-url-cfg-bootstrap',
          diagnostics: diagnostics,
        );
      } catch (e) {
        diagnostics.add('Steam URL launch failed: $e');
      }
    } else if (Platform.isMacOS) {
      try {
        await openSteamRunUrl(steamUrl);
        diagnostics.add('Opened CS2 through Steam URL with replay cfg launch.');
        diagnostics.add('Launch command: $commandLine');
        _scheduleReplayBootstrapCleanup(demo, diagnostics);
        return ReplayLaunchResult(
          started: true,
          method: 'steam-url-cfg-bootstrap',
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

  static Future<ReplayBootstrapInstall> installReplayBootstrap(
    String? cfgPath,
    String consoleDemoPath,
  ) async {
    if (cfgPath == null) return const ReplayBootstrapInstall.none();

    final replayConfigPath = p.join(cfgPath, replayExecConfigName);
    final autoexecPath = p.join(cfgPath, 'autoexec.cfg');
    var replayConfigInstalled = false;
    var autoexecPatched = false;

    try {
      final replayConfig = File(replayConfigPath);
      final parent = replayConfig.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await replayConfig.writeAsString(buildReplayExecConfig(consoleDemoPath));
      replayConfigInstalled = true;
    } catch (_) {}

    try {
      final autoexec = File(autoexecPath);
      final existing = await autoexec.exists()
          ? await autoexec.readAsString()
          : '';
      await autoexec.writeAsString(patchAutoexecContent(existing));
      autoexecPatched = true;
    } catch (_) {}

    return ReplayBootstrapInstall(
      replayConfigPath: replayConfigPath,
      autoexecPath: autoexecPath,
      replayConfigInstalled: replayConfigInstalled,
      autoexecPatched: autoexecPatched,
    );
  }

  static String buildReplayExecConfig(String consoleDemoPath) {
    return [
      '// Generated by BioBase for the next Replay launch. Safe to overwrite.',
      'con_enable "1"',
      'echo "BioBase Replay bootstrap: launching demo"',
      'disconnect',
      buildPlaydemoCommand(consoleDemoPath),
      'demo_timescale 1',
      'demo_resume',
      'demoui',
      '',
    ].join('\r\n');
  }

  static String buildReplayNoopConfig() {
    return [
      '// Generated by BioBase. No pending Replay launch.',
      'echo "BioBase Replay bootstrap: no pending demo"',
      '',
    ].join('\r\n');
  }

  static String buildAutoexecBootstrapBlock() {
    return [
      replayAutoexecBegin,
      'exec $replayExecConfigBase',
      replayAutoexecEnd,
    ].join('\r\n');
  }

  static String patchAutoexecContent(String existing) {
    final normalized = existing.replaceAll('\r\n', '\n');
    final block = buildAutoexecBootstrapBlock().replaceAll('\r\n', '\n');
    final pattern = RegExp(
      '^${RegExp.escape(replayAutoexecBegin)}\n.*?^${RegExp.escape(replayAutoexecEnd)}\n?',
      multiLine: true,
      dotAll: true,
    );
    final patched = pattern.hasMatch(normalized)
        ? normalized.replaceFirst(pattern, '$block\n')
        : [
            normalized.trimRight(),
            '',
            block,
            '',
          ].where((part) => part.isNotEmpty).join('\n');
    return '${patched.trimRight()}\r\n';
  }

  static String buildSteamReplayCommandLine(String _) {
    return [
      '-novid',
      '-console',
      '-condebug',
      '-netconport',
      '$replayNetconPort',
      '+exec',
      replayExecConfigBase,
    ].join(' ');
  }

  static List<String> buildSteamAppLaunchArgs(String _) => [
    '-applaunch',
    '$cs2SteamAppId',
    '-novid',
    '-console',
    '-condebug',
    '-netconport',
    '$replayNetconPort',
    '+exec',
    replayExecConfigBase,
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
    return 'playdemo "$escapedPath"';
  }

  static String escapeCfgString(String value) {
    return value.replaceAll('\\', '/').replaceAll('"', r'\"');
  }

  static String buildPersistentSteamLaunchOptions(String existing) {
    var updated = existing.trim();
    updated = updated.replaceAll(
      RegExp(r'(^|\s)-netconport\s+\S+', caseSensitive: false),
      ' ',
    );

    for (final token in ['-console', '-condebug']) {
      if (!_launchOptionsContainToken(updated, token)) {
        updated = '$updated $token'.trim();
      }
    }

    updated = '$updated -netconport $replayNetconPort'.trim();
    if (!RegExp(
      r'(^|\s)\+exec\s+biobase_replay(?:\.cfg)?(?=\s|$)',
      caseSensitive: false,
    ).hasMatch(updated)) {
      updated = '$updated +exec $replayExecConfigBase'.trim();
    }

    return updated.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _launchOptionsContainToken(String options, String token) {
    return RegExp(
      '(^|\\s)${RegExp.escape(token)}(?=\\s|\$)',
      caseSensitive: false,
    ).hasMatch(options);
  }

  static String? patchSteamAppLaunchOptionsContent(String content) {
    final app730 = RegExp(r'"730"\s*\{').firstMatch(content);
    if (app730 == null) return null;

    final blockStart = app730.end;
    var depth = 1;
    var blockEnd = blockStart;
    for (var i = blockStart; i < content.length && depth > 0; i++) {
      if (content[i] == '{') depth++;
      if (content[i] == '}') depth--;
      if (depth == 0) blockEnd = i;
    }
    if (depth != 0) return null;

    final block = content.substring(blockStart, blockEnd);
    final launchMatch = RegExp(
      r'"LaunchOptions"\s+"((?:\\.|[^"\\])*)"',
    ).firstMatch(block);
    final encodedOptions = _encodeVdfString(
      buildPersistentSteamLaunchOptions(
        launchMatch == null ? '' : _decodeVdfString(launchMatch.group(1)!),
      ),
    );

    if (launchMatch != null) {
      final absStart = blockStart + launchMatch.start;
      final absEnd = blockStart + launchMatch.end;
      return '${content.substring(0, absStart)}"LaunchOptions"\t\t"$encodedOptions"${content.substring(absEnd)}';
    }

    final insertion = '\n\t\t\t\t\t"LaunchOptions"\t\t"$encodedOptions"';
    return content.substring(0, blockEnd) +
        insertion +
        content.substring(blockEnd);
  }

  static String _decodeVdfString(String value) {
    return value.replaceAll('\\\\', '\\').replaceAll(r'\"', '"');
  }

  static String _encodeVdfString(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', r'\"');
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

    final steamPath = await GsiService.findSteamPath();
    if (steamPath != null) {
      final exe = p.join(steamPath, 'steam.exe');
      if (File(exe).existsSync()) return exe;
    }

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

  void _scheduleReplayBootstrapCleanup(
    ReplayDemoTarget demo,
    List<String> diagnostics,
  ) {
    if (!demo.replayConfigInstalled || demo.replayConfigPath == null) return;
    _bootstrapCleanupTimer?.cancel();
    _bootstrapCleanupTimer = Timer(const Duration(minutes: 4), () async {
      try {
        await File(
          demo.replayConfigPath!,
        ).writeAsString(buildReplayNoopConfig());
      } catch (_) {}
    });
    diagnostics.add('Replay cfg cleanup scheduled after launch window.');
  }

  Future<void> _installSteamReplayLaunchOptions(
    List<String> diagnostics,
  ) async {
    final steamPath = await GsiService.findSteamPath();
    if (steamPath == null) {
      diagnostics.add(
        'Steam path was not found; skipping persistent LaunchOptions patch.',
      );
      return;
    }

    final userdata = Directory(p.join(steamPath, 'userdata'));
    if (!userdata.existsSync()) {
      diagnostics.add(
        'Steam userdata was not found; skipping persistent LaunchOptions patch.',
      );
      return;
    }

    await _closeRunningSteam(diagnostics);

    var filesSeen = 0;
    var filesReady = 0;
    var filesChanged = 0;
    for (final dir in userdata.listSync().whereType<Directory>()) {
      final vdf = File(p.join(dir.path, 'config', 'localconfig.vdf'));
      if (!vdf.existsSync()) continue;
      filesSeen += 1;
      try {
        final content = await vdf.readAsString();
        final patched = patchSteamAppLaunchOptionsContent(content);
        if (patched == null) continue;
        filesReady += 1;
        if (patched != content) {
          await vdf.writeAsString(patched);
          filesChanged += 1;
        }
      } catch (e) {
        diagnostics.add('Could not patch ${vdf.path}: $e');
      }
    }

    if (filesReady == 0) {
      diagnostics.add(
        'No Steam CS2 LaunchOptions block was found in $filesSeen localconfig file(s).',
      );
      return;
    }

    diagnostics.add(
      filesChanged > 0
          ? 'Patched Steam CS2 LaunchOptions in $filesChanged/$filesReady account config(s).'
          : 'Steam CS2 LaunchOptions already contained BioBase replay options in $filesReady account config(s).',
    );
  }

  Future<void> _closeRunningSteam(List<String> diagnostics) async {
    try {
      final steamCheck = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq steam.exe',
        '/NH',
      ]);
      if (!(steamCheck.stdout as String).contains('steam.exe')) return;

      diagnostics.add(
        'Closing Steam so CS2 LaunchOptions can be patched safely.',
      );
      await Process.run('taskkill', ['/IM', 'steam.exe']);
      await Future.delayed(const Duration(seconds: 5));

      final checkAgain = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq steam.exe',
        '/NH',
      ]);
      if ((checkAgain.stdout as String).contains('steam.exe')) {
        diagnostics.add(
          'Steam was still running; forcing Steam shutdown for LaunchOptions patch.',
        );
        await Process.run('taskkill', ['/F', '/T', '/IM', 'steam.exe']);
        await Future.delayed(const Duration(seconds: 3));
      }
    } catch (e) {
      diagnostics.add('Could not close Steam before LaunchOptions patch: $e');
    }
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

}

class ReplayBootstrapInstall {
  final String? replayConfigPath;
  final String? autoexecPath;
  final bool replayConfigInstalled;
  final bool autoexecPatched;

  const ReplayBootstrapInstall({
    required this.replayConfigPath,
    required this.autoexecPath,
    required this.replayConfigInstalled,
    required this.autoexecPatched,
  });

  const ReplayBootstrapInstall.none()
    : replayConfigPath = null,
      autoexecPath = null,
      replayConfigInstalled = false,
      autoexecPatched = false;
}
