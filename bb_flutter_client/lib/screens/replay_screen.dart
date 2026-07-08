import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../theme.dart';
import '../services/server_service.dart';
import '../services/moves_service.dart';
import '../services/hltv_service.dart';
import '../services/demo_parser.dart';
import '../services/gsi_service.dart';
import '../services/replay_launch_service.dart';
import '../services/native_demo_service.dart';
import '../services/netcon_service.dart';
import '../services/capture_service.dart';
import '../services/move_library_service.dart';
import '../services/demo_session.dart';
import '../services/cs2_plugin_service.dart';
import '../services/career_service.dart';
import '../services/boiler_service.dart';
import '../services/video_export_service.dart';
import '../services/actions_file_service.dart';
import '../widgets/range_scrubber.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  final ServerService _server = ServerService();
  final MovesService _moves = MovesService();
  final HltvService _hltv = HltvService();
  final ReplayLaunchService _launcher = ReplayLaunchService();
  final NativeDemoService _nativeDemos = NativeDemoService();

  List<DemoFile>? _demos;
  bool _loading = true;
  String? _demoPath;
  String? _demoName;
  double _playbackPosition = 0;
  double _playbackSpeed = 1.0;
  bool _playing = false;
  bool _copying = false;
  DemoInfo? _demoInfo;
  bool _parsingDemo = false;
  NativeDemo? _nativeDemo;
  List<NativeDemoLabel> _nativeLabels = const [];
  bool _nativeParsing = false;
  String? _nativeError;

  int _currentTick = 0;
  Timer? _tickTimer;

  // My matchmaking matches (Steam GC via boiler)
  bool _mmExpanded = false;
  List<MmMatch> _mmMatches = [];
  final Map<String, String> _mmLocalPaths = {};
  bool _mmLoading = false;
  String? _mmMessage;
  String? _mmDownloadingId;
  double _mmProgress = 0;

  // Move video export
  String? _exportStatus;

  // Pro demos state
  bool _proExpanded = false;
  List<HltvDemo> _proDemos = [];
  bool _proLoading = false;
  int? _downloadingDemoId;
  double _downloadProgress = 0;
  String? _proMessage;

  // CS2 live session state
  final NetconService _netcon = NetconService();
  final CaptureService _capture = CaptureService();
  final Cs2PluginService _plugin = Cs2PluginService.instance;
  StreamSubscription? _pluginSub;
  // Demo to start once a control channel is live (the -insecure dialog kills
  // the launch-cfg playdemo, so we re-issue it over plugin WS / netcon).
  // Plugin takes the absolute path; netcon takes the console-relative path.
  String? _pendingPlayDemo;
  String? _pendingPlayDemoConsole;
  DateTime? _coldLaunchAt;
  int _netconPlayAttempts = 0;
  bool _cs2Launching = false;
  String? _cs2LaunchError;
  bool _cs2Live = false;
  Timer? _captureRetry;
  bool _netconSynced = false;
  String? _selectedSteamId;

  // Move marking state — dual-handle range on the timeline
  bool _rangeMode = false;
  int? _rangeStart;
  int? _rangeEnd;
  int _rangeActiveHandle = 1; // 0 = left grip, 1 = right grip
  List<Move> _demoMoves = [];
  String? _editingMoveId;
  final TextEditingController _renameController = TextEditingController();

  // Move library (self-contained saved moves)
  final MoveLibraryService _library = MoveLibraryService();
  List<MoveClip> _libraryClips = const [];
  bool _isMoveReplay = false;
  bool _showDemoBrowser = false;

  @override
  void initState() {
    super.initState();
    _loadDemos();
    _libraryClips = _library.list();
    DemoSession.instance.addListener(_onSessionSignal);
    // The in-game plugin crashes CS2 when its DLL doesn't match the current
    // build (CopyNewEntity fatal error). Until we ship a version-matched
    // plugin, keep it uninstalled and use cfg + netcon playback (the path
    // that worked in v0.13–v0.17). The WS server still listens so a future
    // matched plugin can connect.
    _plugin.uninstall();
    _plugin.startServer();
    _pluginSub = _plugin.onConnectionChanged.listen((connected) async {
      if (connected) await _resolvePendingDemo();
      if (mounted) setState(() {});
    });
  }

  /// Starts the pending demo through whichever control channel is alive.
  /// The plugin WebSocket is preferred (acknowledged, survives the -insecure
  /// dialog); netcon is the fallback when the plugin can't load.
  Future<void> _resolvePendingDemo() async {
    final staged = _pendingPlayDemo;
    if (staged == null) return;
    if (_plugin.gameConnected) {
      final ok = await _plugin.playDemo(staged);
      if (ok) {
        _pendingPlayDemo = null;
        _pendingPlayDemoConsole = null;
        _netconSynced = false;
      }
    }
  }

  void _onSessionSignal() {
    final tick = DemoSession.instance.pendingSeekTick;
    if (tick == null || _nativeDemo == null || !mounted) return;
    DemoSession.instance.consumeSeek();
    _seekNativeTick(tick);
  }

  @override
  void dispose() {
    DemoSession.instance.removeListener(_onSessionSignal);
    _pluginSub?.cancel();
    _renameController.dispose();
    _tickTimer?.cancel();
    _seekDebounce?.cancel();
    _captureRetry?.cancel();
    _netcon.dispose();
    _capture.dispose();
    _nativeDemos.dispose();
    super.dispose();
  }

  void _endCs2Session() {
    _captureRetry?.cancel();
    _captureRetry = null;
    _netcon.disconnect();
    _capture.stop();
    _cs2Live = false;
    _netconSynced = false;
    _pendingPlayDemo = null;
    _pendingPlayDemoConsole = null;
    _coldLaunchAt = null;
    _netconPlayAttempts = 0;
  }

  void _resetReplayState() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _playbackPosition = 0;
    _playbackSpeed = 1.0;
    _playing = false;
    _currentTick = 0;
    _nativeDemo = null;
    _nativeLabels = const [];
    _nativeParsing = false;
    _nativeError = null;
    _cs2Launching = false;
    _cs2LaunchError = null;
    _selectedSteamId = null;
    _isMoveReplay = false;
    _showDemoBrowser = false;
    _endCs2Session();
  }

  Future<void> _playInCS2() async {
    final path = _demoPath;
    if (path == null) return;

    setState(() {
      _cs2Launching = true;
      _cs2LaunchError = null;
    });

    try {
      final target = await _launcher.prepareDemo(path);
      final staged = target.stagedPath ?? target.sourcePath;
      // Plain playback must not inherit a stale watch sequence.
      await ActionsFileService.deleteFor(staged);
      await GsiService.installConfig();

      if (_plugin.gameConnected) {
        // CS2 is already running with the plugin — instant playback.
        final ok = await _plugin.playDemo(staged);
        if (ok) {
          _beginCs2Session(alreadyRunning: true);
          return;
        }
      }
      // No -insecure dialog now, so the launch cfg's playdemo starts the
      // demo directly (the path that worked in v0.13–v0.17). netcon handles
      // control/sync once CS2 is up.
      await _launchCs2Cold();
      _beginCs2Session(alreadyRunning: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cs2Launching = false;
        _cs2LaunchError = '$e';
      });
    }
  }

  /// Kill any pluginless CS2 and launch fresh via Steam with our args
  /// (-insecure loads the plugin; +exec starts the staged demo).
  Future<void> _launchCs2Cold() async {
    if (Platform.isWindows) {
      try {
        final check = await Process.run(
          'tasklist', ['/FI', 'IMAGENAME eq cs2.exe', '/NH'],
        );
        if ((check.stdout as String).contains('cs2.exe')) {
          await Process.run('taskkill', ['/F', '/IM', 'cs2.exe']);
          await Future.delayed(const Duration(seconds: 3));
        }
      } catch (_) {}
    }

    final args = ReplayLaunchService.buildSteamAppLaunchArgs('');
    var launched = false;
    if (Platform.isWindows) {
      final steamExe = await ReplayLaunchService.findSteamExe();
      if (steamExe != null) {
        await Process.start(steamExe, args, mode: ProcessStartMode.detached);
        launched = true;
      }
    }
    if (!launched) {
      await ReplayLaunchService.openSteamRunUrl(
        ReplayLaunchService.buildSteamRunUrl(''),
      );
    }
  }

  void _beginCs2Session({required bool alreadyRunning}) {
    _netcon.startReconnect();
    if (alreadyRunning && _cs2Live) {
      // Capture already rolling — just re-sync the clock.
      _netconSynced = false;
      if (mounted) setState(() => _cs2Launching = false);
      _startCaptureHunt();
      return;
    }
    _startCaptureHunt();
    // _cs2Launching clears when the capture goes live (launch pad shows
    // progress) — see _startCaptureHunt.
  }

  /// Stages the current demo, writes a watch-sequence actions file, and
  /// plays it in CS2 (instant when the plugin is connected).
  Future<void> _playSequence(
    Future<String> Function(String stagedPath) writeActions,
  ) async {
    final path = _demoPath;
    final native = _nativeDemo;
    if (path == null || native == null || _isMoveReplay) return;
    setState(() {
      _cs2Launching = true;
      _cs2LaunchError = null;
    });
    try {
      final target = await _launcher.prepareDemo(path);
      final staged = target.stagedPath ?? target.sourcePath;
      await writeActions(staged);
      await GsiService.installConfig();
      if (_plugin.gameConnected) {
        final ok = await _plugin.playDemo(staged);
        if (ok) {
          _beginCs2Session(alreadyRunning: true);
          return;
        }
      }
      // Without the plugin the actions file can't execute, so this degrades
      // to plain playback (demo plays from the cfg). Kept for when a
      // version-matched plugin is re-enabled.
      await _launchCs2Cold();
      _beginCs2Session(alreadyRunning: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cs2Launching = false;
        _cs2LaunchError = '$e';
      });
    }
  }

  Future<void> _playMoveInCs2(Move move) async {
    final native = _nativeDemo;
    if (native == null || move.startTick == null || move.endTick == null) {
      return;
    }
    String? focusName;
    if (_selectedSteamId != null) focusName = _nameOfSteamid(_selectedSteamId!);
    await _playSequence(
      (staged) => ActionsFileService.writeMoveJump(
        stagedDemoPath: staged,
        demo: native,
        startTick: move.startTick!,
        endTick: move.endTick!,
        focusPlayerName: focusName,
      ),
    );
  }

  List<int> _reelTicks(String steamid, {required bool deaths}) {
    final native = _nativeDemo;
    if (native == null) return const [];
    return [
      for (final e in native.events)
        if (e.type == 'player_death' &&
            e.attackerSteamid != null &&
            e.victimSteamid != null &&
            e.attackerSteamid != e.victimSteamid &&
            e.weapon != 'world' &&
            (deaths ? e.victimSteamid == steamid : e.attackerSteamid == steamid))
          e.tick,
    ];
  }

  Future<void> _playReel(String steamid, String name,
      {required bool deaths}) async {
    final native = _nativeDemo;
    if (native == null) return;
    final ticks = _reelTicks(steamid, deaths: deaths);
    if (ticks.isEmpty) return;
    await _playSequence(
      (staged) => ActionsFileService.writeReel(
        stagedDemoPath: staged,
        demo: native,
        momentTicks: ticks,
        playerName: name,
      ),
    );
  }

  String _nameOfSteamid(String steamid) {
    final native = _nativeDemo;
    if (native == null) return steamid;
    for (final frame in native.frames) {
      for (final p in frame.players) {
        if (p.steamid == steamid && p.name.isNotEmpty) return p.name;
      }
    }
    return steamid;
  }

  /// Polls for the CS2 window until it can be captured, then aligns CS2
  /// playback with the in-app clock through netcon.
  void _startCaptureHunt() {
    _captureRetry?.cancel();
    var attempts = 0;
    _captureRetry = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_cs2Live) {
        attempts++;
        if (attempts > 90) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _cs2Launching = false;
              _cs2LaunchError = 'CS2 window not found — is the game running?';
            });
          }
          return;
        }
        try {
          final ok = await _capture.start();
          if (ok && mounted) {
            setState(() {
              _cs2Live = true;
              _cs2Launching = false;
            });
          }
        } catch (_) {}
        return;
      }
      // Start the demo once a channel is live. Plugin first (via its
      // connection listener); netcon is the fallback when the plugin can't
      // load, fired once after the -insecure dialog would be dismissed so we
      // don't restart the demo repeatedly.
      if (_pendingPlayDemo != null) {
        if (_plugin.gameConnected) {
          await _resolvePendingDemo();
        } else if (_netcon.connected && _coldLaunchAt != null) {
          // Fire a few times, 6s apart, so a slow -insecure dialog dismissal
          // still catches without spamming demo restarts.
          final elapsed = DateTime.now().difference(_coldLaunchAt!).inSeconds;
          final due = 11 + _netconPlayAttempts * 6;
          if (elapsed >= due) {
            await _netcon.playDemo(
              _pendingPlayDemoConsole ?? _pendingPlayDemo!,
            );
            _netconPlayAttempts++;
            _netconSynced = false;
            if (_netconPlayAttempts >= 3) {
              _pendingPlayDemo = null;
              _pendingPlayDemoConsole = null;
            }
          }
        }
        return; // wait for the demo to actually start before syncing
      }

      if (!_netconSynced && _netcon.connected) {
        // First contact: snap CS2 to the app clock. Every later control
        // action keeps the two locked.
        _netconSynced = true;
        await _syncCs2ToTick(_currentTick, resume: _playing);
      }
      // A minimized CS2 stops rendering and blanks the capture — keep it
      // restored (never focused) for as long as the session is live.
      await _capture.ensureVisible();
    });
  }

  Future<void> _syncCs2ToTick(int tick, {required bool resume}) async {
    final native = _nativeDemo;
    if (native == null) return;
    // Parser ticks are demo-file ticks, which is what demo_goto expects.
    final target = tick.clamp(native.startTick, native.endTick);
    await _netcon.gotoTick(target);
    await _netcon.setTimescale(_playbackSpeed);
    if (resume) {
      await _netcon.resumeDemo();
    } else {
      await _netcon.pauseDemo();
    }
  }

  void _selectPlayer(String steamid, String name) {
    setState(() {
      _selectedSteamId = _selectedSteamId == steamid ? null : steamid;
    });
    if (_selectedSteamId != null && _netcon.connected) {
      _netcon.send('spec_player "$name"');
    }
  }

  Future<void> _loadDemos() async {
    setState(() => _loading = true);
    final demos = await _server.listDemos();
    if (mounted)
      setState(() {
        _demos = demos;
        _loading = false;
      });
  }

  Future<void> _loadProDemos() async {
    setState(() {
      _proLoading = true;
      _proMessage = null;
    });
    try {
      final demos = await _hltv.fetchDemos();
      if (mounted)
        setState(() {
          _proDemos = demos;
          _proLoading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _proLoading = false;
          _proMessage = 'Could not connect to demo server';
        });
    }
  }

  Future<void> _downloadProDemo(HltvDemo demo) async {
    setState(() {
      _downloadingDemoId = demo.id;
      _downloadProgress = 0;
      _proMessage = null;
    });
    try {
      final path = await _hltv.downloadDemo(
        demo,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      demo.localPath = path;
      if (mounted)
        setState(() {
          _downloadingDemoId = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _downloadingDemoId = null;
          _proMessage = e.toString();
        });
    }
  }

  void _selectProDemo(HltvDemo demo) {
    if (demo.localPath == null) return;
    setState(() {
      _demoPath = demo.localPath;
      _demoName = demo.filename;
      _resetReplayState();
      _cancelRangeFields();
      _demoMoves = _moves.movesForDemo(demo.filename);
    });
    _parseDemo(demo.localPath!);
  }

  Future<void> _selectDemo(DemoFile demo) async {
    setState(() => _copying = true);
    final path = await _server.copyDemoToLocal(demo.name);
    if (mounted) {
      setState(() {
        _copying = false;
        if (path != null) {
          _demoPath = path;
          _demoName = demo.name;
          _resetReplayState();
          _cancelRangeFields();
          _demoMoves = _moves.movesForDemo(demo.name);
        }
      });
      if (path != null) _parseDemo(path);
    }
  }

  Future<void> _pickLocal() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dem'],
      dialogTitle: 'Open CS2 Demo',
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      setState(() {
        _demoPath = file.path;
        _demoName = result.files.single.name;
        _resetReplayState();
        _cancelRangeFields();
        _demoMoves = _moves.movesForDemo(result.files.single.name);
      });
      _parseDemo(file.path);
    }
  }

  Future<void> _parseDemo(String path) async {
    setState(() {
      _parsingDemo = true;
      _nativeParsing = true;
      _demoInfo = null;
      _nativeDemo = null;
      _nativeLabels = const [];
      _nativeError = null;
    });

    final info = await DemoParser.parse(path);
    if (mounted) {
      setState(() {
        _demoInfo = info;
        _parsingDemo = false;
      });
    }

    try {
      final native = await _nativeDemos.uploadAndLoad(File(path));
      final labels = await _nativeDemos.fetchLabels(native.demoId);
      if (!mounted) return;
      setState(() {
        _nativeDemo = native;
        _nativeLabels = labels;
        _nativeParsing = false;
        _nativeError = null;
        _currentTick = native.startTick;
        _playbackPosition = 0;
        _playing = true;
      });
      DemoSession.instance.setDemo(
        parsed: native,
        name: _demoName ?? path,
        path: path,
      );
      CareerService.instance.record(demo: native, demoName: _demoName ?? path);
      _startTickTracking();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nativeParsing = false;
        _nativeError = e.toString();
      });
    }
  }

  void _startTickTracking() {
    _tickTimer?.cancel();
    final native = _nativeDemo;
    if (native == null || native.frames.isEmpty) return;
    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_playing || !mounted) return;
      setState(() {
        _currentTick += (native.tickRateGuess * 0.2 * _playbackSpeed).round();
        if (_currentTick > native.endTick) {
          _currentTick = native.endTick;
          _playing = false;
          _tickTimer?.cancel();
        }
        _playbackPosition =
            ((_currentTick - native.startTick) / native.tickSpan).clamp(0.0, 1.0);
      });
    });
  }

  void _togglePlayback() {
    if (_playing) {
      _tickTimer?.cancel();
      if (_netcon.connected) _netcon.pauseDemo();
    } else {
      _startTickTracking();
      if (_netcon.connected) _netcon.resumeDemo();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  void _setSpeed(double speed) {
    if (_netcon.connected) _netcon.setTimescale(speed);
    if (mounted) setState(() => _playbackSpeed = speed);
  }

  void _seekNativeTick(int tick) {
    final native = _nativeDemo;
    if (native == null) return;
    final clamped = tick.clamp(native.startTick, native.endTick);
    setState(() {
      _currentTick = clamped;
      _playbackPosition = ((clamped - native.startTick) / native.tickSpan)
          .clamp(0.0, 1.0);
    });
    if (_netcon.connected) {
      // Debounce so slider drags send one seek, not hundreds.
      _seekDebounce?.cancel();
      _seekDebounce = Timer(const Duration(milliseconds: 250), () {
        _syncCs2ToTick(_currentTick, resume: _playing);
      });
    }
  }

  Timer? _seekDebounce;

  void _seekTo(double position) {
    final normalized = position.clamp(0.0, 1.0);
    final native = _nativeDemo;
    if (native != null && native.frames.isNotEmpty) {
      final tick = native.startTick + (native.tickSpan * normalized).round();
      if (mounted) _seekNativeTick(tick);
      return;
    }
    if (mounted) setState(() => _playbackPosition = normalized);
  }

  void _cancelRangeFields() {
    _rangeMode = false;
    _rangeStart = null;
    _rangeEnd = null;
    _rangeActiveHandle = 1;
  }

  /// Arm the range selector around the current playhead, or save when armed.
  void _onMarkTap() {
    if (_rangeMode) {
      _saveRange();
    } else {
      _armRange();
    }
  }

  void _armRange() {
    final native = _nativeDemo;
    if (native == null) return;
    final rate = native.tickRateGuess <= 0 ? 64 : native.tickRateGuess;
    final fiveSec = rate * 5;
    var start = _currentTick.clamp(native.startTick, native.endTick);
    var end = start + fiveSec;
    if (end > native.endTick) {
      end = native.endTick;
      start = (end - fiveSec).clamp(native.startTick, end - 1);
    }
    setState(() {
      _rangeMode = true;
      _rangeStart = start;
      _rangeEnd = end;
      _rangeActiveHandle = 1;
    });
  }

  void _updateRange(int start, int end, int handle) {
    final native = _nativeDemo;
    if (native == null) return;
    setState(() {
      _rangeStart = start;
      _rangeEnd = end;
      _rangeActiveHandle = handle;
    });
    // Follow the dragged grip so the render shows the exact frame.
    _seekNativeTick(handle == 0 ? start : end);
  }

  void _nudgeRange(int dTicks) {
    final a = _rangeStart, b = _rangeEnd;
    final native = _nativeDemo;
    if (!_rangeMode || a == null || b == null || native == null) return;
    if (_rangeActiveHandle == 0) {
      final tick = (a + dTicks).clamp(native.startTick, b - 1);
      _updateRange(tick, b, 0);
    } else {
      final tick = (b + dTicks).clamp(a + 1, native.endTick);
      _updateRange(a, tick, 1);
    }
  }

  void _saveRange() {
    final native = _nativeDemo;
    final a = _rangeStart, b = _rangeEnd;
    if (native == null || a == null || b == null || _demoName == null) {
      setState(_cancelRangeFields);
      return;
    }
    final startTick = a < b ? a : b;
    final endTick = a < b ? b : a;
    final span = native.tickSpan;
    final move = _moves.addMove(
      demoName: _demoName!,
      startPosition: ((startTick - native.startTick) / span).clamp(0.0, 1.0),
      endPosition: ((endTick - native.startTick) / span).clamp(0.0, 1.0),
      startTick: startTick,
      endTick: endTick,
    );
    try {
      _library.saveClip(
        demo: native,
        demoName: _demoName!,
        name: move.name,
        startTick: startTick,
        endTick: endTick,
      );
      _libraryClips = _library.list();
    } catch (_) {}
    setState(() {
      _cancelRangeFields();
      _demoMoves = _moves.movesForDemo(_demoName!);
    });
    _saveNativeLabel(move, startTick, endTick);
  }

  void _playMoveClip(MoveClip clip) {
    final demo = _library.loadClipDemo(clip);
    if (demo == null || demo.frames.isEmpty) return;
    setState(() {
      _demoPath = clip.filePath;
      _demoName = clip.name;
      _resetReplayState();
      _isMoveReplay = true;
      _cancelRangeFields();
      _demoMoves = const [];
      _nativeDemo = demo;
      _currentTick = demo.startTick;
      _playing = true;
    });
    DemoSession.instance.setDemo(
      parsed: demo,
      name: clip.name,
      path: clip.filePath,
    );
    _startTickTracking();
  }

  void _deleteClip(MoveClip clip) {
    _library.delete(clip);
    setState(() => _libraryClips = _library.list());
  }

  void _cancelMark() {
    setState(_cancelRangeFields);
  }

  // ── My matchmaking matches ──

  Future<void> _fetchMmMatches() async {
    setState(() {
      _mmLoading = true;
      _mmMessage = null;
    });
    try {
      final matches = await BoilerService.instance.fetchMatches();
      if (!mounted) return;
      setState(() {
        _mmMatches = matches;
        _mmLoading = false;
        _mmMessage = matches.isEmpty ? 'No recent matches' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mmLoading = false;
        _mmMessage = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _downloadMmDemo(MmMatch match) async {
    setState(() {
      _mmDownloadingId = match.matchId;
      _mmProgress = 0;
      _mmMessage = null;
    });
    try {
      final path = await BoilerService.instance.downloadDemo(
        match,
        onProgress: (v) {
          if (mounted) setState(() => _mmProgress = v);
        },
      );
      if (!mounted) return;
      setState(() {
        _mmLocalPaths[match.matchId] = path;
        _mmDownloadingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mmDownloadingId = null;
        _mmMessage = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _selectMmDemo(MmMatch match) {
    final path = _mmLocalPaths[match.matchId];
    if (path == null) {
      _downloadMmDemo(match);
      return;
    }
    setState(() {
      _demoPath = path;
      _demoName = match.fileName;
      _resetReplayState();
      _demoMoves = _moves.movesForDemo(match.fileName);
    });
    _parseDemo(path);
  }

  // ── Move video export ──

  Future<void> _exportMoveVideo(Move move) async {
    final native = _nativeDemo;
    final path = _demoPath;
    if (native == null ||
        path == null ||
        move.startTick == null ||
        move.endTick == null ||
        VideoExportService.instance.exporting) {
      return;
    }
    VideoExportService.instance.exporting = true;
    void status(String s) {
      if (mounted) setState(() => _exportStatus = s);
    }

    status('Preparing recording…');
    try {
      final target = await _launcher.prepareDemo(path);
      final staged = target.stagedPath ?? target.sourcePath;
      final safeName = move.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      String? focusName;
      if (_selectedSteamId != null) {
        focusName = _nameOfSteamid(_selectedSteamId!);
      }
      await VideoExportService.instance.writeRecordingActions(
        stagedDemoPath: staged,
        demo: native,
        startTick: move.startTick!,
        endTick: move.endTick!,
        sequenceName: safeName,
        focusPlayerName: focusName,
      );
      var playing = false;
      if (_plugin.gameConnected) {
        playing = await _plugin.playDemo(staged);
      }
      if (!playing) {
        await _launchCs2Cold();
      }
      status('Recording in CS2 — do not close the game…');
      final out = await VideoExportService.instance.collectAndEncode(
        outputName: safeName,
        onStatus: status,
      );
      status('Exported: $out');
    } catch (e) {
      status('Export failed: $e'.replaceFirst('Exception: ', ''));
    } finally {
      VideoExportService.instance.exporting = false;
    }
  }

  void _deleteMove(String id) {
    _moves.deleteMove(id);
    setState(() => _demoMoves = _moves.movesForDemo(_demoName!));
  }

  Future<void> _saveNativeLabel(Move move, int startTick, int endTick) async {
    final native = _nativeDemo;
    if (native == null) return;
    try {
      final saved = await _nativeDemos.createLabel(
        demoId: native.demoId,
        startTick: startTick,
        endTick: endTick,
        title: move.name,
        tags: const ['manual-review'],
      );
      if (!mounted) return;
      setState(() {
        _nativeLabels = [..._nativeLabels, saved]
          ..sort((a, b) => a.startTick.compareTo(b.startTick));
      });
    } catch (_) {
      // Local move labels still exist if the API label write fails.
    }
  }

  void _startRename(Move move) {
    _renameController.text = move.name;
    setState(() => _editingMoveId = move.id);
  }

  void _commitRename(String id) {
    final name = _renameController.text.trim();
    if (name.isNotEmpty) {
      _moves.renameMove(id, name);
    }
    setState(() {
      _editingMoveId = null;
      _demoMoves = _moves.movesForDemo(_demoName!);
    });
  }

  void _jumpToMove(Move move) {
    _seekTo(move.startPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _buildLeft()),
        const SizedBox(width: 12),
        Expanded(
          child: _RenderArea(
            demoPath: _demoPath,
            demoName: _demoName,
            demoInfo: _demoInfo,
            nativeDemo: _nativeDemo,
            nativeLabels: _nativeLabels,
            nativeParsing: _nativeParsing,
            nativeError: _nativeError,
            currentTick: _currentTick,
            onJumpToTick: _seekNativeTick,
            parsingDemo: _parsingDemo,
            playing: _playing,
            playbackSpeed: _playbackSpeed,
            moves: _demoMoves,
            playbackPosition: _playbackPosition,
            rangeMode: _rangeMode,
            rangeStart: _rangeStart,
            rangeEnd: _rangeEnd,
            onRangeChanged: _updateRange,
            onNudgeRange: _nudgeRange,
            onCancelMark: _cancelMark,
            onTogglePlayback: _togglePlayback,
            onSeek: _seekTo,
            onSetSpeed: _setSpeed,
            onPlayInCS2: _demoPath != null && !_cs2Launching && !_isMoveReplay
                ? _playInCS2
                : null,
            cs2Launching: _cs2Launching,
            cs2LaunchError: _cs2LaunchError,
            cs2Live: _cs2Live,
            captureTextureId: _capture.textureId,
            captureAspect: _capture.aspectRatio,
            selectedSteamId: _selectedSteamId,
            onSelectPlayer: _selectPlayer,
            onMark: _nativeDemo != null ? _onMarkTap : null,
            marking: _rangeMode,
          ),
        ),
      ],
    );
  }

  Widget _buildLeft() {
    final dashboard =
        _demoPath != null && _nativeDemo != null && !_showDemoBrowser;
    if (dashboard) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDashboardHeader(),
          const SizedBox(height: 8),
          _buildRoundPanel(),
          const SizedBox(height: 8),
          _buildTeamsPanel(),
          if (_selectedSteamId != null) ...[
            const SizedBox(height: 8),
            _buildPlayerCard(),
          ],
          const SizedBox(height: 8),
          _buildMovesSection(),
          const SizedBox(height: 8),
          _buildLiveEvents(),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (_demoPath != null && _nativeDemo != null) ...[
          _buildBackToDashboard(),
          const SizedBox(height: 8),
        ],
        _buildDemoList(),
        const SizedBox(height: 8),
        _buildMmPanel(),
        const SizedBox(height: 8),
        _buildHltvPanel(),
        const SizedBox(height: 8),
        _buildMoveLibraryPanel(),
        if (_demoPath != null && _nativeDemo == null) ...[
          const SizedBox(height: 8),
          _buildMovesSection(),
        ],
      ],
    );
  }

  // ── Playback dashboard ──

  List<_RenderedNativePlayer> _dashPlayers() {
    final native = _nativeDemo;
    if (native == null || native.frames.isEmpty) return const [];
    final tick = _currentTick
        .clamp(native.startTick, native.endTick)
        .toInt();
    final idx = _nativeFrameIndexAt(native.frames, tick);
    return _nativePlayersAt(native.frames, idx, tick);
  }

  int _dashRound() {
    final native = _nativeDemo;
    if (native == null) return 0;
    var round = 0;
    for (final e in native.events) {
      if (e.tick > _currentTick) break;
      if (e.type == 'round_start') round++;
    }
    return round;
  }

  int _dashRoundStartTick() {
    final native = _nativeDemo;
    if (native == null) return 0;
    var start = native.startTick;
    for (final e in native.events) {
      if (e.tick > _currentTick) break;
      if (e.type == 'round_start') start = e.tick;
    }
    return start;
  }

  int _dashDeaths(String steamid) {
    final native = _nativeDemo;
    if (native == null) return 0;
    var deaths = 0;
    bool? wasAlive;
    for (final frame in native.frames) {
      if (frame.tick > _currentTick) break;
      for (final p in frame.players) {
        if (p.steamid != steamid) continue;
        final alive = p.isAlive ?? ((p.health ?? 100) > 0);
        if (wasAlive == true && !alive) deaths++;
        wasAlive = alive;
        break;
      }
    }
    return deaths;
  }

  /// Current movement speed in units/s from the two frames around the tick.
  double _dashSpeed(String steamid) {
    final native = _nativeDemo;
    if (native == null || native.frames.length < 2) return 0;
    final tick = _currentTick
        .clamp(native.startTick, native.endTick)
        .toInt();
    final idx = _nativeFrameIndexAt(native.frames, tick);
    if (idx == 0) return 0;
    final a = native.frames[idx - 1];
    final b = native.frames[idx];
    final dt = b.timeSec - a.timeSec;
    if (dt <= 0) return 0;
    NativePlayerState? pa, pb;
    for (final p in a.players) {
      if (p.steamid == steamid) pa = p;
    }
    for (final p in b.players) {
      if (p.steamid == steamid) pb = p;
    }
    if (pa == null || pb == null) return 0;
    final dx = pb.x - pa.x;
    final dy = pb.y - pa.y;
    return math.sqrt(dx * dx + dy * dy) / dt;
  }

  /// Distance travelled this round, in units.
  double _dashRoundDistance(String steamid) {
    final native = _nativeDemo;
    if (native == null) return 0;
    final roundStart = _dashRoundStartTick();
    double distance = 0;
    double? lastX, lastY;
    for (final frame in native.frames) {
      if (frame.tick < roundStart) continue;
      if (frame.tick > _currentTick) break;
      for (final p in frame.players) {
        if (p.steamid != steamid) continue;
        if (lastX != null && lastY != null) {
          final dx = p.x - lastX;
          final dy = p.y - lastY;
          distance += math.sqrt(dx * dx + dy * dy);
        }
        lastX = p.x;
        lastY = p.y;
        break;
      }
    }
    return distance;
  }

  Widget _panel({required List<Widget> children, Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _panelTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: BiobaseColors.text,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildDashboardHeader() {
    return _panel(
      children: [
        Row(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _showDemoBrowser = true),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chevron_left,
                      size: 16,
                      color: BiobaseColors.textSecondary,
                    ),
                    Text(
                      'Demos',
                      style: TextStyle(
                        fontSize: 11,
                        color: BiobaseColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (_isMoveReplay)
              const Text(
                'MOVE REPLAY',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: BiobaseColors.accent,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _demoName ?? '',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: BiobaseColors.text,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildBackToDashboard() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _showDemoBrowser = false),
        child: _panel(
          children: [
            const Row(
              children: [
                Icon(Icons.chevron_left, size: 16, color: BiobaseColors.accent),
                Text(
                  'Back to playback',
                  style: TextStyle(fontSize: 11, color: BiobaseColors.accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundPanel() {
    final native = _nativeDemo;
    if (native == null) return const SizedBox.shrink();
    final round = _dashRound();
    final rate = native.tickRateGuess <= 0 ? 64 : native.tickRateGuess;
    final inRoundSec =
        ((_currentTick - _dashRoundStartTick()) / rate).floor().clamp(0, 599);
    final players = _dashPlayers();
    var tAlive = 0, ctAlive = 0;
    for (final p in players) {
      final alive = p.isAlive ?? ((p.health ?? 100) > 0);
      if (!alive) continue;
      if (_isCtTeam(p.team)) {
        ctAlive++;
      } else {
        tAlive++;
      }
    }
    return _panel(
      children: [
        Row(
          children: [
            Text(
              round > 0 ? 'ROUND $round' : 'WARMUP',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: BiobaseColors.text,
              ),
            ),
            const Spacer(),
            Text(
              '${inRoundSec ~/ 60}:${(inRoundSec % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: BiobaseColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '$tAlive',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: _teamColor('T'),
              ),
            ),
            const Text(
              ' v ',
              style: TextStyle(
                fontSize: 10,
                color: BiobaseColors.textTertiary,
              ),
            ),
            Text(
              '$ctAlive',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: _teamColor('CT'),
              ),
            ),
            const Spacer(),
            Text(
              _nativeDemo?.mapName ?? '',
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: BiobaseColors.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTeamsPanel() {
    final players = _dashPlayers();
    if (players.isEmpty) {
      return _panel(
        children: const [
          Text(
            'No player data at this tick',
            style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
          ),
        ],
      );
    }
    final t = players.where((p) => !_isCtTeam(p.team)).toList();
    final ct = players.where((p) => _isCtTeam(p.team)).toList();
    return _panel(
      children: [
        _panelTitle('Players'),
        const SizedBox(height: 8),
        for (final p in t) _dashPlayerRow(p),
        if (t.isNotEmpty && ct.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(
              height: 1,
              thickness: 1,
              color: BiobaseColors.border,
            ),
          ),
        for (final p in ct) _dashPlayerRow(p),
      ],
    );
  }

  Widget _dashPlayerRow(_RenderedNativePlayer p) {
    final selected = p.steamid == _selectedSteamId;
    final alive = p.isAlive ?? ((p.health ?? 100) > 0);
    final hp = (p.health ?? 100).clamp(0, 100).round();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _selectPlayer(p.steamid, p.name),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? BiobaseColors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: alive
                      ? _teamColor(p.team)
                      : BiobaseColors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: alive
                        ? (selected ? BiobaseColors.accent : BiobaseColors.text)
                        : BiobaseColors.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 46,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: alive ? hp / 100 : 0,
                    backgroundColor: BiobaseColors.surfaceRaised,
                    color: hp > 45 ? BiobaseColors.live : BiobaseColors.warning,
                  ),
                ),
              ),
              SizedBox(
                width: 26,
                child: Text(
                  alive ? '$hp' : '✕',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: alive
                        ? (hp > 45 ? BiobaseColors.live : BiobaseColors.warning)
                        : BiobaseColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard() {
    final steamid = _selectedSteamId;
    if (steamid == null) return const SizedBox.shrink();
    _RenderedNativePlayer? player;
    for (final p in _dashPlayers()) {
      if (p.steamid == steamid) player = p;
    }
    if (player == null) return const SizedBox.shrink();
    final playerName = player.name;
    final alive = player.isAlive ?? ((player.health ?? 100) > 0);
    final hp = (player.health ?? 100).clamp(0, 100).round();
    final speed = _dashSpeed(steamid);
    final distance = _dashRoundDistance(steamid);
    final deaths = _dashDeaths(steamid);
    return _panel(
      borderColor: BiobaseColors.accent.withAlpha(90),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                player.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BiobaseColors.text,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _isCtTeam(player.team) ? 'CT' : 'T',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _teamColor(player.team),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _dashStat(
              alive ? '$hp' : 'DEAD',
              'HP',
              color: alive
                  ? (hp > 45 ? BiobaseColors.live : BiobaseColors.warning)
                  : BiobaseColors.error,
            ),
            _dashStat('${speed.round()}', 'u/s'),
            _dashStat('$deaths', 'Deaths'),
            _dashStat(
              distance >= 1000
                  ? '${(distance / 1000).toStringAsFixed(1)}k'
                  : '${distance.round()}',
              'Dist rnd',
            ),
          ],
        ),
        if (!_isMoveReplay) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _reelButton(
                'Kills reel',
                Icons.local_fire_department_outlined,
                _reelTicks(steamid, deaths: false).isNotEmpty
                    ? () => _playReel(steamid, playerName, deaths: false)
                    : null,
              ),
              const SizedBox(width: 6),
              _reelButton(
                'Deaths reel',
                Icons.close_outlined,
                _reelTicks(steamid, deaths: true).isNotEmpty
                    ? () => _playReel(steamid, playerName, deaths: true)
                    : null,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _reelButton(String label, IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return Expanded(
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: BiobaseColors.surfaceRaised,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: BiobaseColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 11,
                  color: enabled
                      ? BiobaseColors.accent
                      : BiobaseColors.textTertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? BiobaseColors.text
                        : BiobaseColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashStat(String value, String label, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: color ?? BiobaseColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveEvents() {
    final native = _nativeDemo;
    if (native == null) return const SizedBox.shrink();
    final events = native.events
        .where((e) => e.tick <= _currentTick)
        .toList()
        .reversed
        .take(8)
        .toList();
    final rate = native.tickRateGuess <= 0 ? 64 : native.tickRateGuess;
    return _panel(
      children: [
        _panelTitle('Events'),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const Text(
            'No events yet',
            style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
          )
        else
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      _tickTimeLabel(e.tick, native.startTick, rate),
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                  ),
                  Text(
                    e.type.toUpperCase().replaceAll('_', ' '),
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: _dashEventColor(e.type),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  String _tickTimeLabel(int tick, int startTick, int rate) {
    final sec = ((tick - startTick) / rate).floor();
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  Color _dashEventColor(String type) {
    switch (type) {
      case 'kill':
      case 'player_death':
        return BiobaseColors.error;
      case 'round_start':
        return BiobaseColors.accent;
      case 'bomb_planted':
        return BiobaseColors.warning;
      case 'bomb_defused':
        return BiobaseColors.live;
      default:
        return BiobaseColors.textSecondary;
    }
  }

  // ── My matches (Steam matchmaking) ──

  Widget _buildMmPanel() {
    return _panel(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _mmExpanded = !_mmExpanded),
            child: Row(
              children: [
                const Text(
                  'My Matches',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BiobaseColors.text,
                  ),
                ),
                const Spacer(),
                if (_mmMatches.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${_mmMatches.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                  ),
                Icon(
                  _mmExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: BiobaseColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_mmExpanded) ...[
          const SizedBox(height: 10),
          if (_mmLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
              ),
            )
          else ...[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _fetchMmMatches,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: BiobaseColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: BiobaseColors.border),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_download_outlined,
                        size: 12,
                        color: BiobaseColors.accent,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Fetch from Steam',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: BiobaseColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Steam must be running · closes CS2 briefly',
              style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
          if (_mmMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _mmMessage!,
              style: const TextStyle(
                fontSize: 9,
                color: BiobaseColors.warning,
              ),
            ),
          ],
          if (_mmMatches.isNotEmpty) const SizedBox(height: 8),
          for (final m in _mmMatches.take(20)) _mmRow(m),
        ],
      ],
    );
  }

  Widget _mmRow(MmMatch m) {
    final local = _mmLocalPaths.containsKey(m.matchId);
    final downloading = _mmDownloadingId == m.matchId;
    final selected = local && _demoPath == _mmLocalPaths[m.matchId];
    final date = m.playedAt;
    final label = date != null
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : 'Match ${m.matchId.substring(0, 8)}…';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: downloading ? null : () => _selectMmDemo(m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? BiobaseColors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                local ? Icons.play_circle_outline : Icons.download_outlined,
                size: 12,
                color: selected
                    ? BiobaseColors.accent
                    : local
                    ? BiobaseColors.textSecondary
                    : BiobaseColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? BiobaseColors.accent : BiobaseColors.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (downloading)
                Text(
                  '${(_mmProgress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: BiobaseColors.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Move library ──

  Widget _buildMoveLibraryPanel() {
    return _panel(
      children: [
        _panelTitle(
          'Move Library',
          trailing: _libraryClips.isNotEmpty
              ? Text(
                  '${_libraryClips.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: BiobaseColors.textTertiary,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        if (_libraryClips.isEmpty)
          const Text(
            'Mark a move during playback to save it here',
            style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary),
          )
        else
          for (final clip in _libraryClips) _clipRow(clip),
      ],
    );
  }

  Widget _clipRow(MoveClip clip) {
    final selected = _isMoveReplay && _demoPath == clip.filePath;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _playMoveClip(clip),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? BiobaseColors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 12,
                color: selected
                    ? BiobaseColors.accent
                    : BiobaseColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clip.name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? BiobaseColors.accent
                            : BiobaseColors.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${clip.mapName} · ${clip.durationSec.toStringAsFixed(1)}s',
                      style: const TextStyle(
                        fontSize: 9,
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _deleteClip(clip),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: BiobaseColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Demo list ──

  Widget _buildDemoList() {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Demos',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                ),
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: BiobaseColors.textTertiary,
                  ),
                )
              else
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _loadDemos,
                    child: const Icon(
                      Icons.refresh,
                      size: 14,
                      color: BiobaseColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Loading demos...',
                  style: TextStyle(
                    fontSize: 11,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
              ),
            )
          else if (_demos == null || _demos!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'No demos recorded yet',
                      style: TextStyle(
                        fontSize: 11,
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Play a match to generate a demo',
                      style: TextStyle(
                        fontSize: 10,
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...(_demos!.map(
              (d) => _DemoRow(
                demo: d,
                selected: _demoName == d.name,
                onTap: _copying ? null : () => _selectDemo(d),
              ),
            )),
          const SizedBox(height: 10),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _pickLocal,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 12,
                    color: BiobaseColors.textTertiary,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Open file',
                    style: TextStyle(
                      fontSize: 10,
                      color: BiobaseColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pro demos panel ──

  Widget _buildHltvPanel() {
    final grouped = <String, List<HltvDemo>>{};
    for (final d in _proDemos) {
      grouped.putIfAbsent(d.matchId, () => []).add(d);
    }

    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                final expanding = !_proExpanded;
                setState(() => _proExpanded = expanding);
                if (expanding && _proDemos.isEmpty && !_proLoading) {
                  _loadProDemos();
                }
              },
              child: Row(
                children: [
                  const Text(
                    'Pro Demos',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BiobaseColors.text,
                    ),
                  ),
                  const Spacer(),
                  if (_proDemos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${_proDemos.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: BiobaseColors.textTertiary,
                        ),
                      ),
                    ),
                  Icon(
                    _proExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: BiobaseColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_proExpanded) ...[
            const SizedBox(height: 10),
            if (_proLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: BiobaseColors.textTertiary,
                    ),
                  ),
                ),
              )
            else if (_proDemos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    _proMessage ?? 'No demos available',
                    style: TextStyle(
                      fontSize: 11,
                      color: _proMessage != null
                          ? BiobaseColors.error
                          : BiobaseColors.textTertiary,
                    ),
                  ),
                ),
              )
            else
              ...grouped.entries.map((entry) {
                final demos = entry.value;
                final first = demos.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Text(
                        '${first.team1} vs ${first.team2}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: BiobaseColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (first.event.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          first.event,
                          style: const TextStyle(
                            fontSize: 9,
                            color: BiobaseColors.textTertiary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ...demos.map(
                      (d) => _ProDemoRow(
                        demo: d,
                        selected: _demoName == d.filename,
                        downloading: _downloadingDemoId == d.id,
                        downloadProgress: _downloadingDemoId == d.id
                            ? _downloadProgress
                            : 0,
                        onTap: d.localPath != null
                            ? () => _selectProDemo(d)
                            : () => _downloadProDemo(d),
                      ),
                    ),
                  ],
                );
              }),
            if (_proMessage != null && _proDemos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _proMessage!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: BiobaseColors.error,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Moves ──

  Widget _buildMovesSection() {
    final hasDemo = _demoPath != null;
    final marking = _rangeMode;

    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: marking
              ? BiobaseColors.warning.withAlpha(60)
              : BiobaseColors.border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Moves',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                ),
              ),
              const Spacer(),
              if (_demoMoves.isNotEmpty)
                Text(
                  '${_demoMoves.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Mark button
          if (hasDemo) ...[
            Row(
              children: [
                Expanded(
                  child: _MarkButton(
                    marking: marking,
                    onTap: _onMarkTap,
                    startTime: marking && _rangeStart != null && _nativeDemo != null
                        ? _tickTimeLabel(
                            _rangeStart!,
                            _nativeDemo!.startTick,
                            _nativeDemo!.tickRateGuess <= 0
                                ? 64
                                : _nativeDemo!.tickRateGuess,
                          )
                        : null,
                  ),
                ),
                if (marking) ...[
                  const SizedBox(width: 6),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _cancelMark,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: BiobaseColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: BiobaseColors.border),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 10,
                            color: BiobaseColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Moves list
          if (!hasDemo)
            const Text(
              'Load a demo to mark moves',
              style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
            )
          else if (_demoMoves.isEmpty && !marking)
            const Text(
              'No moves marked yet',
              style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
            )
          else
            ...(_demoMoves.map(
              (m) => _MoveRow(
                move: m,
                editing: _editingMoveId == m.id,
                renameController: _renameController,
                formatTime: _formatTime,
                onTap: () => _jumpToMove(m),
                onRename: () => _startRename(m),
                onCommitRename: () => _commitRename(m.id),
                onDelete: () => _deleteMove(m.id),
                onPlayCs2:
                    !_isMoveReplay && m.startTick != null && m.endTick != null
                    ? () => _playMoveInCs2(m)
                    : null,
                onExport:
                    !_isMoveReplay && m.startTick != null && m.endTick != null
                    ? () => _exportMoveVideo(m)
                    : null,
              ),
            )),
          if (_exportStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              _exportStatus!,
              style: const TextStyle(
                fontSize: 9,
                color: BiobaseColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Shared helpers ──

  String _formatTime(double t) {
    final totalSecs = _demoInfo?.playbackTime ?? 45 * 60;
    final elapsed = (t * totalSecs).toInt();
    final mins = elapsed ~/ 60;
    final secs = elapsed % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

// ── Mark button ──

class _MarkButton extends StatefulWidget {
  final bool marking;
  final VoidCallback onTap;
  final String? startTime;

  const _MarkButton({
    required this.marking,
    required this.onTap,
    this.startTime,
  });

  @override
  State<_MarkButton> createState() => _MarkButtonState();
}

class _MarkButtonState extends State<_MarkButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final marking = widget.marking;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: marking
                ? (_hovered
                      ? BiobaseColors.warning
                      : BiobaseColors.warning.withAlpha(200))
                : (_hovered
                      ? BiobaseColors.accentDim
                      : BiobaseColors.surfaceRaised),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: marking ? BiobaseColors.warning : BiobaseColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                marking ? Icons.flag : Icons.flag_outlined,
                size: 12,
                color: marking ? BiobaseColors.bg : BiobaseColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                marking ? 'Mark End' : 'Mark Start',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: marking
                      ? BiobaseColors.bg
                      : BiobaseColors.textSecondary,
                ),
              ),
              if (marking && widget.startTime != null) ...[
                const SizedBox(width: 8),
                Text(
                  'from ${widget.startTime}',
                  style: TextStyle(
                    fontSize: 9,
                    color: BiobaseColors.bg.withAlpha(180),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Move row ──

class _MoveRow extends StatefulWidget {
  final Move move;
  final bool editing;
  final TextEditingController renameController;
  final String Function(double) formatTime;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onCommitRename;
  final VoidCallback onDelete;
  final VoidCallback? onPlayCs2;
  final VoidCallback? onExport;

  const _MoveRow({
    required this.move,
    required this.editing,
    required this.renameController,
    required this.formatTime,
    required this.onTap,
    required this.onRename,
    required this.onCommitRename,
    required this.onDelete,
    this.onPlayCs2,
    this.onExport,
  });

  @override
  State<_MoveRow> createState() => _MoveRowState();
}

class _MoveRowState extends State<_MoveRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.move;
    final timeRange =
        '${widget.formatTime(m.startPosition)} → ${widget.formatTime(m.endPosition)}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? BiobaseColors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: BiobaseColors.live,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.editing)
                      SizedBox(
                        height: 18,
                        child: TextField(
                          controller: widget.renameController,
                          autofocus: true,
                          style: const TextStyle(
                            fontSize: 11,
                            color: BiobaseColors.text,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => widget.onCommitRename(),
                        ),
                      )
                    else
                      Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: BiobaseColors.text,
                        ),
                      ),
                    const SizedBox(height: 1),
                    Text(
                      timeRange,
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hovered && !widget.editing) ...[
                if (widget.onPlayCs2 != null) ...[
                  GestureDetector(
                    onTap: widget.onPlayCs2,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.videogame_asset_outlined,
                        size: 11,
                        color: BiobaseColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                if (widget.onExport != null) ...[
                  GestureDetector(
                    onTap: widget.onExport,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.movie_outlined,
                        size: 11,
                        color: BiobaseColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                GestureDetector(
                  onTap: widget.onRename,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 11,
                      color: BiobaseColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: BiobaseColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Demo row ──

class _DemoRow extends StatefulWidget {
  final DemoFile demo;
  final bool selected;
  final VoidCallback? onTap;

  const _DemoRow({required this.demo, required this.selected, this.onTap});

  @override
  State<_DemoRow> createState() => _DemoRowState();
}

class _DemoRowState extends State<_DemoRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.demo;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: widget.selected
                ? BiobaseColors.accentDim
                : _hovered
                ? BiobaseColors.surfaceHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.videocam_outlined,
                size: 12,
                color: widget.selected
                    ? BiobaseColors.accent
                    : BiobaseColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.selected
                            ? BiobaseColors.accent
                            : BiobaseColors.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${_formatSize(d.sizeBytes)}  ·  ${_formatDate(d.modified)}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }
}

// ── Pro Demo row ──

class _ProDemoRow extends StatefulWidget {
  final HltvDemo demo;
  final bool selected;
  final bool downloading;
  final double downloadProgress;
  final VoidCallback onTap;

  const _ProDemoRow({
    required this.demo,
    required this.selected,
    required this.downloading,
    required this.downloadProgress,
    required this.onTap,
  });

  @override
  State<_ProDemoRow> createState() => _ProDemoRowState();
}

class _ProDemoRowState extends State<_ProDemoRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.demo;
    final local = d.localPath != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.downloading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: widget.selected
                ? BiobaseColors.accentDim
                : _hovered
                ? BiobaseColors.surfaceHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                local ? Icons.play_circle_outline : Icons.download_outlined,
                size: 12,
                color: widget.selected
                    ? BiobaseColors.accent
                    : local
                    ? BiobaseColors.textSecondary
                    : BiobaseColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.displayName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.selected
                            ? BiobaseColors.accent
                            : BiobaseColors.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatSize(d.sizeBytes),
                      style: const TextStyle(
                        fontSize: 9,
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.downloading)
                SizedBox(
                  width: 24,
                  child: Text(
                    '${(widget.downloadProgress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: BiobaseColors.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

// ── Render Area (right) ──

class _RenderArea extends StatelessWidget {
  final String? demoPath;
  final String? demoName;
  final DemoInfo? demoInfo;
  final NativeDemo? nativeDemo;
  final List<NativeDemoLabel> nativeLabels;
  final bool nativeParsing;
  final String? nativeError;
  final int currentTick;
  final ValueChanged<int> onJumpToTick;
  final bool parsingDemo;
  final bool playing;
  final double playbackSpeed;
  final List<Move> moves;
  final double playbackPosition;
  final bool rangeMode;
  final int? rangeStart;
  final int? rangeEnd;
  final void Function(int start, int end, int handle)? onRangeChanged;
  final ValueChanged<int>? onNudgeRange;
  final VoidCallback? onCancelMark;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSetSpeed;
  final VoidCallback? onPlayInCS2;
  final bool cs2Launching;
  final String? cs2LaunchError;
  final bool cs2Live;
  final int? captureTextureId;
  final double captureAspect;
  final String? selectedSteamId;
  final void Function(String steamid, String name)? onSelectPlayer;
  final VoidCallback? onMark;
  final bool marking;

  const _RenderArea({
    required this.demoPath,
    required this.demoName,
    required this.demoInfo,
    required this.nativeDemo,
    required this.nativeLabels,
    required this.nativeParsing,
    required this.nativeError,
    required this.currentTick,
    required this.onJumpToTick,
    required this.parsingDemo,
    required this.playing,
    required this.playbackSpeed,
    required this.moves,
    required this.playbackPosition,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onSetSpeed,
    this.rangeMode = false,
    this.rangeStart,
    this.rangeEnd,
    this.onRangeChanged,
    this.onNudgeRange,
    this.onCancelMark,
    this.onPlayInCS2,
    this.cs2Launching = false,
    this.cs2LaunchError,
    this.cs2Live = false,
    this.captureTextureId,
    this.captureAspect = 16 / 9,
    this.selectedSteamId,
    this.onSelectPlayer,
    this.onMark,
    this.marking = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      child: demoPath == null ? _emptyState() : _loadedState(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_outlined,
            size: 48,
            color: BiobaseColors.textTertiary.withAlpha(80),
          ),
          const SizedBox(height: 12),
          const Text(
            'No demo selected',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: BiobaseColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select a demo from the list to start replay',
            style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _loadedState() {
    final info = demoInfo;
    final hasNativePlayback =
        nativeDemo != null && nativeDemo!.frames.isNotEmpty;

    if (hasNativePlayback) {
      return _NativeDemoViewer(
        demo: nativeDemo!,
        labels: nativeLabels,
        moves: moves,
        currentTick: currentTick,
        playing: playing,
        playbackSpeed: playbackSpeed,
        playbackPosition: playbackPosition,
        rangeMode: rangeMode,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        onRangeChanged: onRangeChanged,
        onNudgeRange: onNudgeRange,
        onCancelMark: onCancelMark,
        onJumpToTick: onJumpToTick,
        onTogglePlayback: onTogglePlayback,
        onSeek: onSeek,
        onSetSpeed: onSetSpeed,
        onPlayInCS2: onPlayInCS2,
        cs2Launching: cs2Launching,
        cs2LaunchError: cs2LaunchError,
        cs2Live: cs2Live,
        captureTextureId: captureTextureId,
        captureAspect: captureAspect,
        selectedSteamId: selectedSteamId,
        onSelectPlayer: onSelectPlayer,
        onMark: onMark,
        marking: marking,
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: _loadedBody(info, false)),
      ],
    );
  }

  Widget _loadedBody(DemoInfo? info, bool hasNativePlayback) {
    if (nativeParsing || parsingDemo) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BiobaseColors.textTertiary,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Parsing demo...',
              style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
            ),
          ],
        ),
      );
    }
    if (info == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 48,
              color: BiobaseColors.textTertiary.withAlpha(60),
            ),
            const SizedBox(height: 12),
            Text(
              demoName ?? '',
              style: const TextStyle(
                fontSize: 12,
                color: BiobaseColors.textSecondary,
              ),
            ),
            if (nativeError != null) ...[
              const SizedBox(height: 12),
              _issueBox('Native parser unavailable: $nativeError'),
            ],
          ],
        ),
      );
    }
    return Center(child: _demoInfoDisplay(info));
  }

  Widget _demoInfoDisplay(DemoInfo info) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            info.mapDisplay.toUpperCase(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: BiobaseColors.text,
            ),
          ),
          if (info.serverName != null) ...[
            const SizedBox(height: 6),
            Text(
              info.serverName!,
              style: const TextStyle(
                fontSize: 12,
                color: BiobaseColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _statBlock(info.durationDisplay, 'Duration'),
              _divider(),
              _statBlock(info.sizeDisplay, 'Size'),
              _divider(),
              _statBlock(info.tickrateDisplay, 'Tickrate'),
            ],
          ),
          const SizedBox(height: 6),
          if (info.mapName != null)
            Text(
              info.mapName!,
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: BiobaseColors.textTertiary,
              ),
            ),
          const SizedBox(height: 24),
          _nativeReplayInfo(),
          if (nativeError != null) ...[
            const SizedBox(height: 12),
            _issueBox('Native parser unavailable: $nativeError'),
          ],
          const SizedBox(height: 10),
          Text(
            demoName ?? '',
            style: const TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: BiobaseColors.textTertiary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _nativeReplayInfo() {
    if (nativeParsing || parsingDemo) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: BiobaseColors.accent,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Parsing demo for replay...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: BiobaseColors.textSecondary,
            ),
          ),
        ],
      );
    }
    if (nativeError != null) {
      return _issueBox('Could not parse demo: $nativeError');
    }
    return const SizedBox.shrink();
  }

  Widget _statBlock(String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: BiobaseColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 28, color: BiobaseColors.border);
  }

  Widget _issueBox(String issue) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BiobaseColors.warning.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BiobaseColors.warning.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: BiobaseColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              issue,
              style: const TextStyle(
                fontSize: 10,
                height: 1.35,
                color: BiobaseColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _NativeDemoViewer extends StatefulWidget {
  final NativeDemo demo;
  final List<NativeDemoLabel> labels;
  final List<Move> moves;
  final int currentTick;
  final bool playing;
  final double playbackSpeed;
  final double playbackPosition;
  final bool rangeMode;
  final int? rangeStart;
  final int? rangeEnd;
  final void Function(int start, int end, int handle)? onRangeChanged;
  final ValueChanged<int>? onNudgeRange;
  final VoidCallback? onCancelMark;
  final ValueChanged<int> onJumpToTick;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSetSpeed;
  final VoidCallback? onPlayInCS2;
  final bool cs2Launching;
  final String? cs2LaunchError;
  final bool cs2Live;
  final int? captureTextureId;
  final double captureAspect;
  final String? selectedSteamId;
  final void Function(String steamid, String name)? onSelectPlayer;
  final VoidCallback? onMark;
  final bool marking;

  const _NativeDemoViewer({
    required this.demo,
    required this.labels,
    required this.moves,
    required this.currentTick,
    required this.playing,
    required this.playbackSpeed,
    required this.playbackPosition,
    required this.onJumpToTick,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onSetSpeed,
    this.rangeMode = false,
    this.rangeStart,
    this.rangeEnd,
    this.onRangeChanged,
    this.onNudgeRange,
    this.onCancelMark,
    this.onPlayInCS2,
    this.cs2Launching = false,
    this.cs2LaunchError,
    this.cs2Live = false,
    this.captureTextureId,
    this.captureAspect = 16 / 9,
    this.selectedSteamId,
    this.onSelectPlayer,
    this.onMark,
    this.marking = false,
  });

  @override
  State<_NativeDemoViewer> createState() => _NativeDemoViewerState();
}

class _NativeDemoViewerState extends State<_NativeDemoViewer> {
  final bool _controlsVisible = true;
  bool _hovering = false;
  static const _speeds = [0.25, 0.5, 1.0, 2.0, 4.0];

  String _timeLabel(int tick) {
    final rate = widget.demo.tickRateGuess <= 0 ? 64 : widget.demo.tickRateGuess;
    final elapsed = tick < widget.demo.startTick ? 0 : tick - widget.demo.startTick;
    final totalSec = (elapsed / rate).floor();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _totalTimeLabel() {
    final rate = widget.demo.tickRateGuess <= 0 ? 64 : widget.demo.tickRateGuess;
    final totalSec = (widget.demo.tickSpan / rate).floor();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  List<NativeDemoEvent> _recentEvents() {
    final tick = widget.currentTick;
    final windowTicks = widget.demo.tickRateGuess * 8;
    return widget.demo.events
        .where((e) => e.tick <= tick && e.tick >= tick - windowTicks)
        .toList()
      ..sort((a, b) => b.tick.compareTo(a.tick));
  }

  int _currentRound() {
    final tick = widget.currentTick;
    var round = 0;
    for (final e in widget.demo.events) {
      if (e.tick > tick) break;
      if (e.type == 'round_start') round++;
    }
    return round;
  }

  bool get _live => widget.cs2Live && widget.captureTextureId != null;

  /// Pre-render view: match overview + the one action that matters.
  Widget _launchPad() {
    final demo = widget.demo;
    final rate = demo.tickRateGuess <= 0 ? 64 : demo.tickRateGuess;
    final durationSec = (demo.tickSpan / rate).floor();
    final rounds =
        demo.events.where((e) => e.type == 'round_start').length;

    var players = _playersNow();
    if (players.isEmpty) {
      for (final frame in demo.frames.take(80)) {
        if (frame.players.isNotEmpty) {
          players = frame.players
              .map(_RenderedNativePlayer.fromState)
              .toList();
          break;
        }
      }
    }
    final t = players.where((p) => !_isCtTeam(p.team)).toList();
    final ct = players.where((p) => _isCtTeam(p.team)).toList();

    return Container(
      color: BiobaseColors.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                demo.mapName.toUpperCase(),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: BiobaseColors.text,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _padStat(
                    '${durationSec ~/ 60}:${(durationSec % 60).toString().padLeft(2, '0')}',
                    'Duration',
                  ),
                  _padDivider(),
                  _padStat(rounds > 0 ? '$rounds' : '—', 'Rounds'),
                  _padDivider(),
                  _padStat('${players.length}', 'Players'),
                ],
              ),
              if (t.isNotEmpty || ct.isNotEmpty) ...[
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _padRoster(t, alignEnd: false)),
                    const SizedBox(width: 28),
                    Expanded(child: _padRoster(ct, alignEnd: true)),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              if (widget.cs2Launching)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: BiobaseColors.accent,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Starting CS2 render…',
                      style: TextStyle(
                        fontSize: 11,
                        color: BiobaseColors.accent,
                      ),
                    ),
                  ],
                )
              else if (widget.onPlayInCS2 != null)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onPlayInCS2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: BiobaseColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Play in CS2',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.cs2LaunchError == null &&
                  (widget.cs2Launching || widget.onPlayInCS2 != null)) ...[
                const SizedBox(height: 10),
                const Text(
                  'The game render appears here',
                  style: TextStyle(
                    fontSize: 10,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _padStat(String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: BiobaseColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _padDivider() =>
      Container(width: 1, height: 26, color: BiobaseColors.border);

  Widget _padRoster(List<_RenderedNativePlayer> players,
      {required bool alignEnd}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (final p in players)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!alignEnd) ...[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _teamColor(p.team),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  _shortName(p.name),
                  style: const TextStyle(
                    fontSize: 11,
                    color: BiobaseColors.textSecondary,
                  ),
                ),
                if (alignEnd) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _teamColor(p.team),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  List<_RenderedNativePlayer> _playersNow() {
    final tick = widget.currentTick
        .clamp(widget.demo.startTick, widget.demo.endTick)
        .toInt();
    final idx = _nativeFrameIndexAt(widget.demo.frames, tick);
    return _nativePlayersAt(widget.demo.frames, idx, tick);
  }


  Widget _playerRail() {
    final players = _playersNow();
    if (players.isEmpty) return const SizedBox.shrink();
    final ct = players.where((p) => _isCtTeam(p.team)).toList();
    final t = players.where((p) => !_isCtTeam(p.team)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final p in t) _playerChip(p)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [for (final p in ct) _playerChip(p)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _playerChip(_RenderedNativePlayer p) {
    final isSelected = p.steamid == widget.selectedSteamId;
    final alive = p.isAlive ?? ((p.health ?? 100) > 0);
    final teamColor = _teamColor(p.team);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onSelectPlayer?.call(p.steamid, p.name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: BiobaseColors.bg.withAlpha(isSelected ? 235 : 190),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? BiobaseColors.accent : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: alive ? teamColor : BiobaseColors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _shortName(p.name),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: alive
                      ? BiobaseColors.text
                      : BiobaseColors.textTertiary,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                alive ? '${(p.health ?? 100).round()}' : '✕',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: alive
                      ? ((p.health ?? 100) > 45
                            ? BiobaseColors.live
                            : BiobaseColors.warning)
                      : BiobaseColors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final tick = widget.currentTick.clamp(widget.demo.startTick, widget.demo.endTick).toInt();
    final progress = ((tick - widget.demo.startTick) / widget.demo.tickSpan).clamp(0.0, 1.0);
    final recentEvents = _recentEvents();
    final round = _currentRound();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          switch (event.logicalKey.keyLabel) {
            case ' ':
              widget.onTogglePlayback();
              return KeyEventResult.handled;
            case 'Arrow Left':
              if (widget.rangeMode) {
                widget.onNudgeRange?.call(
                  HardwareKeyboard.instance.isShiftPressed
                      ? -(widget.demo.tickRateGuess ~/ 2)
                      : -1,
                );
                return KeyEventResult.handled;
              }
              final newTick = (tick - widget.demo.tickRateGuess * 5)
                  .clamp(widget.demo.startTick, widget.demo.endTick);
              widget.onJumpToTick(newTick);
              return KeyEventResult.handled;
            case 'Arrow Right':
              if (widget.rangeMode) {
                widget.onNudgeRange?.call(
                  HardwareKeyboard.instance.isShiftPressed
                      ? widget.demo.tickRateGuess ~/ 2
                      : 1,
                );
                return KeyEventResult.handled;
              }
              final newTick = (tick + widget.demo.tickRateGuess * 5)
                  .clamp(widget.demo.startTick, widget.demo.endTick);
              widget.onJumpToTick(newTick);
              return KeyEventResult.handled;
            case 'M':
            case 'm':
              widget.onMark?.call();
              return KeyEventResult.handled;
            case 'Escape':
              if (widget.rangeMode) {
                widget.onCancelMark?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            case 'Enter':
              if (widget.rangeMode) {
                widget.onMark?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            // Main layer: live CS2 render when capturing, launch pad otherwise
            if (_live)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: widget.captureAspect,
                        child: Texture(textureId: widget.captureTextureId!),
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(child: _launchPad()),

            // Live mode: player rail
            if (_live)
              Positioned(
                top: 34,
                left: 14,
                right: 14,
                child: _playerRail(),
              ),

            // Top-left: map + round
            Positioned(
              top: 10,
              left: 14,
              child: Row(
                children: [
                  Text(
                    widget.demo.mapName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: BiobaseColors.text,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  if (round > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: BiobaseColors.bg.withAlpha(180),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'R$round',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: BiobaseColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Top-right: event feed
            if (recentEvents.isNotEmpty)
              Positioned(
                top: 10,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final e in recentEvents.take(4))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: BiobaseColors.bg.withAlpha(190),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _eventLabel(e),
                            style: TextStyle(
                              fontSize: 9,
                              fontFamily: 'monospace',
                              color: _eventColor(e),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // CS2 launch error
            if (widget.cs2LaunchError != null)
              Positioned(
                top: 10,
                left: 14,
                right: 14,
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: BiobaseColors.errorDim,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: BiobaseColors.error.withAlpha(60)),
                    ),
                    child: Text(
                      widget.cs2LaunchError!,
                      style: const TextStyle(fontSize: 10, color: BiobaseColors.error),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),


            // Bottom controls bar
            if (_controlsVisible || _hovering || !widget.playing)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _controlsBar(tick, progress),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controlsBar(int tick, double progress) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            BiobaseColors.bg.withAlpha(220),
            BiobaseColors.bg.withAlpha(240),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 24, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scrubber — dual-handle range selector while marking
            RangeScrubber(
              progress: progress.toDouble(),
              demoStartTick: widget.demo.startTick,
              demoEndTick: widget.demo.endTick,
              tickRate: widget.demo.tickRateGuess,
              moveRanges: [
                for (final move in widget.moves)
                  (move.startPosition, move.endPosition),
              ],
              onSeek: widget.onSeek,
              rangeMode: widget.rangeMode,
              rangeStart: widget.rangeStart,
              rangeEnd: widget.rangeEnd,
              onRangeChanged: widget.onRangeChanged,
            ),
            const SizedBox(height: 4),
            // Controls row
            Row(
              children: [
                // Play in CS2 button
                if (widget.onPlayInCS2 != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _cs2LaunchBtn(),
                  ),
                // Mark move button (M)
                if (widget.onMark != null) ...[
                  Padding(
                    padding: EdgeInsets.only(
                      right: widget.marking ? 4 : 10,
                    ),
                    child: _markBtn(),
                  ),
                  if (widget.marking)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _iconBtn(
                        Icons.close_rounded,
                        () => widget.onCancelMark?.call(),
                        size: 14,
                      ),
                    ),
                ],
                // Play/Pause
                _iconBtn(
                  widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  widget.onTogglePlayback,
                  size: 22,
                ),
                const SizedBox(width: 2),
                _iconBtn(Icons.replay_5_rounded, () {
                  final newTick = (tick - widget.demo.tickRateGuess * 5)
                      .clamp(widget.demo.startTick, widget.demo.endTick);
                  widget.onJumpToTick(newTick);
                }),
                _iconBtn(Icons.forward_5_rounded, () {
                  final newTick = (tick + widget.demo.tickRateGuess * 5)
                      .clamp(widget.demo.startTick, widget.demo.endTick);
                  widget.onJumpToTick(newTick);
                }),
                const SizedBox(width: 8),
                Text(
                  '${_timeLabel(tick)} / ${_totalTimeLabel()}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: BiobaseColors.textSecondary,
                  ),
                ),
                const Spacer(),
                for (final s in _speeds)
                  _speedChip(s),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {double size = 16}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: BiobaseColors.text),
        ),
      ),
    );
  }

  Widget _speedChip(double speed) {
    final active = widget.playbackSpeed == speed;
    final label = speed == 0.25 ? '.25' :
                  speed == 0.5 ? '.5' :
                  speed == 4.0 ? '4' :
                  speed.toStringAsFixed(speed.truncateToDouble() == speed ? 0 : 1);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onSetSpeed(speed),
        child: Container(
          margin: const EdgeInsets.only(left: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: active ? BiobaseColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: active ? BiobaseColors.accent : BiobaseColors.border,
            ),
          ),
          child: Text(
            '${label}x',
            style: TextStyle(
              fontSize: 9,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              fontFamily: 'monospace',
              color: active ? Colors.white : BiobaseColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _markBtn() {
    final marking = widget.marking;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onMark,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: marking
                ? BiobaseColors.warning.withAlpha(30)
                : BiobaseColors.surfaceRaised,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: marking ? BiobaseColors.warning : BiobaseColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                marking ? Icons.check_rounded : Icons.flag_outlined,
                size: 12,
                color: marking
                    ? BiobaseColors.warning
                    : BiobaseColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                marking ? 'Save move' : 'Mark move',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: marking ? FontWeight.w600 : FontWeight.w400,
                  color: marking
                      ? BiobaseColors.warning
                      : BiobaseColors.textSecondary,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'M',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'monospace',
                  color: BiobaseColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cs2LaunchBtn() {
    if (widget.cs2Live) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: BiobaseColors.live.withAlpha(26),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: BiobaseColors.live.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: BiobaseColors.live,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'CS2 LIVE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.live,
              ),
            ),
          ],
        ),
      );
    }
    if (widget.cs2Launching) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: BiobaseColors.accent.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: BiobaseColors.accent.withAlpha(60)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5, color: BiobaseColors.accent,
              ),
            ),
            SizedBox(width: 6),
            Text('Launching...', style: TextStyle(fontSize: 10, color: BiobaseColors.accent)),
          ],
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPlayInCS2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: BiobaseColors.accent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videogame_asset_rounded, size: 13, color: Colors.white),
              SizedBox(width: 5),
              Text(
                'Play in CS2',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _eventLabel(NativeDemoEvent e) {
    switch (e.type) {
      case 'kill': return 'KILL';
      case 'round_start': return 'ROUND START';
      case 'round_end': return 'ROUND END';
      case 'bomb_planted': return 'BOMB PLANTED';
      case 'bomb_defused': return 'BOMB DEFUSED';
      default: return e.type.toUpperCase().replaceAll('_', ' ');
    }
  }

  Color _eventColor(NativeDemoEvent e) {
    switch (e.type) {
      case 'kill': return BiobaseColors.error;
      case 'round_start': return BiobaseColors.accent;
      case 'round_end': return BiobaseColors.textSecondary;
      case 'bomb_planted': return BiobaseColors.warning;
      case 'bomb_defused': return BiobaseColors.live;
      default: return BiobaseColors.textTertiary;
    }
  }
}


class _RenderedNativePlayer {
  final String steamid;
  final String name;
  final String team;
  final double x;
  final double y;
  final double? yaw;
  final double? health;
  final bool? isAlive;

  const _RenderedNativePlayer({
    required this.steamid,
    required this.name,
    required this.team,
    required this.x,
    required this.y,
    this.yaw,
    this.health,
    this.isAlive,
  });

  factory _RenderedNativePlayer.fromState(NativePlayerState state) {
    return _RenderedNativePlayer(
      steamid: state.steamid,
      name: state.name,
      team: state.team,
      x: state.x,
      y: state.y,
      yaw: state.yaw,
      health: state.health,
      isAlive: state.isAlive,
    );
  }
}


int _nativeFrameIndexAt(List<NativeDemoFrame> frames, int tick) {
  if (frames.length <= 1) return 0;
  var lo = 0;
  var hi = frames.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (frames[mid].tick <= tick) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

List<_RenderedNativePlayer> _nativePlayersAt(
  List<NativeDemoFrame> frames,
  int leftIndex,
  int tick,
) {
  if (frames.isEmpty) return const [];
  final rightIndex = math.min(leftIndex + 1, frames.length - 1);
  final left = frames[leftIndex];
  final right = frames[rightIndex];
  final leftPlayers = {for (final p in left.players) p.steamid: p};
  final rightPlayers = {for (final p in right.players) p.steamid: p};
  final ids = <String>{...leftPlayers.keys, ...rightPlayers.keys};
  final denom = right.tick - left.tick;
  final t = denom == 0
      ? 0.0
      : ((tick - left.tick) / denom).clamp(0.0, 1.0).toDouble();

  final result = <_RenderedNativePlayer>[];
  for (final id in ids) {
    final a = leftPlayers[id];
    final b = rightPlayers[id];
    if (a == null && b != null) {
      result.add(_RenderedNativePlayer.fromState(b));
      continue;
    }
    if (b == null && a != null) {
      result.add(_RenderedNativePlayer.fromState(a));
      continue;
    }
    if (a == null || b == null) continue;
    result.add(
      _RenderedNativePlayer(
        steamid: id,
        name: b.name.isNotEmpty ? b.name : a.name,
        team: b.team != 'UNKNOWN' ? b.team : a.team,
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
        yaw: b.yaw ?? a.yaw,
        health: b.health ?? a.health,
        isAlive: b.isAlive ?? a.isAlive,
      ),
    );
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
}

Color _teamColor(String team) {
  final upper = team.toUpperCase();
  if (upper.contains('CT') || upper.contains('COUNTER')) {
    return const Color(0xFF60A5FA);
  }
  if (upper == 'T' || upper.contains('TERRORIST')) {
    return const Color(0xFFF59E0B);
  }
  return BiobaseColors.textTertiary;
}

bool _isCtTeam(String team) {
  final upper = team.toUpperCase();
  return upper.contains('CT') || upper.contains('COUNTER');
}

String _shortName(String name) {
  final trimmed = name.trim();
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 13)}…';
}


