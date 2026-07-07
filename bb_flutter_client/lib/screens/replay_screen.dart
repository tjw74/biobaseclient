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
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCVideoRenderer, RTCVideoView, RTCVideoViewObjectFit;

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
  bool _cs2Launching = false;
  String? _cs2LaunchError;
  bool _cs2Live = false;
  Timer? _captureRetry;
  bool _netconSynced = false;
  String? _selectedSteamId;

  // Move marking state
  double? _moveStart;
  List<Move> _demoMoves = [];
  String? _editingMoveId;
  final TextEditingController _renameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDemos();
  }

  @override
  void dispose() {
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
    _endCs2Session();
  }

  Future<void> _playInCS2() async {
    final path = _demoPath;
    if (path == null) return;

    _endCs2Session();
    setState(() {
      _cs2Launching = true;
      _cs2LaunchError = null;
    });

    try {
      await _launcher.prepareDemo(path);
      await GsiService.installConfig();

      // Close CS2 if running — Steam ignores launch args for already-running games
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

      _netcon.startReconnect();
      _startCaptureHunt();
      if (!mounted) return;
      setState(() => _cs2Launching = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cs2Launching = false;
        _cs2LaunchError = '$e';
      });
    }
  }

  /// Polls for the CS2 window until it can be captured, then aligns CS2
  /// playback with the in-app clock through netcon.
  void _startCaptureHunt() {
    _captureRetry?.cancel();
    var attempts = 0;
    _captureRetry = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts > 90) {
        timer.cancel();
        return;
      }
      if (!_cs2Live) {
        try {
          final ok = await _capture.start();
          if (ok && mounted) setState(() => _cs2Live = true);
        } catch (_) {}
      }
      if (_cs2Live && !_netconSynced && _netcon.connected) {
        // First contact: snap CS2 to the app clock. Every later control
        // action keeps the two locked.
        _netconSynced = true;
        await _syncCs2ToTick(_currentTick, resume: _playing);
      }
      if (_cs2Live && _netconSynced) timer.cancel();
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
      _moveStart = null;
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
          _moveStart = null;
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
        _moveStart = null;
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

  void _onMarkTap() {
    if (_moveStart == null) {
      setState(() => _moveStart = _playbackPosition);
    } else {
      final start = _moveStart!;
      final end = _playbackPosition;
      if ((end - start).abs() < 0.001) {
        setState(() => _moveStart = null);
        return;
      }
      final s = start < end ? start : end;
      final e = start < end ? end : start;
      final native = _nativeDemo;
      final totalTicks = native?.tickSpan ?? _demoInfo?.playbackTicks;
      final startTick = totalTicks != null
          ? ((native?.startTick ?? 0) + s * totalTicks).round()
          : null;
      final endTick = totalTicks != null
          ? ((native?.startTick ?? 0) + e * totalTicks).round()
          : null;
      final move = _moves.addMove(
        demoName: _demoName!,
        startPosition: s,
        endPosition: e,
        startTick: startTick,
        endTick: endTick,
      );
      setState(() {
        _moveStart = null;
        _demoMoves = _moves.movesForDemo(_demoName!);
      });
      if (native != null && startTick != null && endTick != null) {
        _saveNativeLabel(move, startTick, endTick);
      }
    }
  }

  void _cancelMark() {
    setState(() => _moveStart = null);
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
            moveStart: _moveStart,
            onTogglePlayback: _togglePlayback,
            onSeek: _seekTo,
            onSetSpeed: _setSpeed,
            onPlayInCS2: _demoPath != null && !_cs2Launching ? _playInCS2 : null,
            cs2Launching: _cs2Launching,
            cs2LaunchError: _cs2LaunchError,
            cs2Live: _cs2Live,
            captureRenderer: _capture.active ? _capture.renderer : null,
            selectedSteamId: _selectedSteamId,
            onSelectPlayer: _selectPlayer,
          ),
        ),
      ],
    );
  }

  Widget _buildLeft() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildDemoList(),
        const SizedBox(height: 8),
        _buildHltvPanel(),
        const SizedBox(height: 8),
        _buildPlayback(),
        const SizedBox(height: 8),
        _buildMovesSection(),
        const SizedBox(height: 8),
        _buildStats(),
        const SizedBox(height: 8),
        _buildEvents(),
      ],
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

  // ── Playback ──

  Widget _buildPlayback() {
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
          const Text(
            'Playback',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.text,
            ),
          ),
          const SizedBox(height: 10),
          _buildTimeline(),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _formatTime(_playbackPosition),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: BiobaseColors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                _demoInfo?.durationDisplay ?? _formatTime(1.0),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: BiobaseColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _controlBtn(Icons.skip_previous, () => _seekTo(0)),
              const SizedBox(width: 4),
              _controlBtn(
                _playing ? Icons.pause : Icons.play_arrow,
                _togglePlayback,
                primary: true,
              ),
              const SizedBox(width: 4),
              _controlBtn(Icons.skip_next, () => _seekTo(1)),
              const Spacer(),
              ...([0.25, 0.5, 1.0, 2.0].map(
                (s) => Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: _speedBtn(s, _playbackSpeed == s, () => _setSpeed(s)),
                ),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: BiobaseColors.accent,
                inactiveTrackColor: BiobaseColors.surfaceRaised,
                thumbColor: BiobaseColors.accent,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: _playbackPosition.clamp(0.0, 1.0),
                onChanged: _demoPath != null ? (v) => _seekTo(v) : null,
              ),
            ),
            // Move range markers on the track
            for (final move in _demoMoves)
              Positioned(
                left: 12 + move.startPosition * (constraints.maxWidth - 24),
                top: 6,
                child: Container(
                  width:
                      (move.endPosition - move.startPosition) *
                      (constraints.maxWidth - 24),
                  height: 3,
                  decoration: BoxDecoration(
                    color: BiobaseColors.live.withAlpha(140),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            // Active mark-start indicator
            if (_moveStart != null)
              Positioned(
                left: 12 + _moveStart! * (constraints.maxWidth - 24) - 1,
                top: 2,
                child: Container(
                  width: 2,
                  height: 11,
                  color: BiobaseColors.warning,
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Moves ──

  Widget _buildMovesSection() {
    final hasDemo = _demoPath != null;
    final marking = _moveStart != null;

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
                    startTime: marking ? _formatTime(_moveStart!) : null,
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
              ),
            )),
        ],
      ),
    );
  }

  // ── Stats ──

  Widget _buildStats() {
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
          const Text(
            'Round Stats',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.text,
            ),
          ),
          const SizedBox(height: 10),
          _statRow('Kills', '—'),
          _statRow('Deaths', '—'),
          _statRow('Assists', '—'),
          _statRow('ADR', '—'),
          _statRow('HLTV Rating', '—'),
          _statRow('HS %', '—'),
          _statRow('Flash Assists', '—'),
          _statRow('Utility Damage', '—'),
        ],
      ),
    );
  }

  // ── Events ──

  Widget _buildEvents() {
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
          const Text(
            'Events',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.text,
            ),
          ),
          const SizedBox(height: 10),
          if (_demoPath == null)
            const Text(
              'Select a demo to see events',
              style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
            )
          else
            const Text(
              'Demo parsing in progress',
              style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
            ),
        ],
      ),
    );
  }

  // ── Shared helpers ──

  Widget _controlBtn(
    IconData icon,
    VoidCallback onTap, {
    bool primary = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _demoPath != null ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primary ? BiobaseColors.accent : BiobaseColors.surfaceRaised,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: _demoPath != null
                ? Colors.white
                : BiobaseColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _speedBtn(double s, bool active, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: active ? BiobaseColors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${s}x',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: active ? BiobaseColors.accent : BiobaseColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: BiobaseColors.textTertiary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.text,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

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

  const _MoveRow({
    required this.move,
    required this.editing,
    required this.renameController,
    required this.formatTime,
    required this.onTap,
    required this.onRename,
    required this.onCommitRename,
    required this.onDelete,
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
  final double? moveStart;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSetSpeed;
  final VoidCallback? onPlayInCS2;
  final bool cs2Launching;
  final String? cs2LaunchError;
  final bool cs2Live;
  final RTCVideoRenderer? captureRenderer;
  final String? selectedSteamId;
  final void Function(String steamid, String name)? onSelectPlayer;

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
    this.moveStart,
    this.onPlayInCS2,
    this.cs2Launching = false,
    this.cs2LaunchError,
    this.cs2Live = false,
    this.captureRenderer,
    this.selectedSteamId,
    this.onSelectPlayer,
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
        moveStart: moveStart,
        onJumpToTick: onJumpToTick,
        onTogglePlayback: onTogglePlayback,
        onSeek: onSeek,
        onSetSpeed: onSetSpeed,
        onPlayInCS2: onPlayInCS2,
        cs2Launching: cs2Launching,
        cs2LaunchError: cs2LaunchError,
        cs2Live: cs2Live,
        captureRenderer: captureRenderer,
        selectedSteamId: selectedSteamId,
        onSelectPlayer: onSelectPlayer,
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: _loadedBody(info, false)),
        if (moveStart != null)
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: BiobaseColors.warning.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: BiobaseColors.warning.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: BiobaseColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Marking move...',
                    style: TextStyle(
                      fontSize: 10,
                      color: BiobaseColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
  final double? moveStart;
  final ValueChanged<int> onJumpToTick;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSetSpeed;
  final VoidCallback? onPlayInCS2;
  final bool cs2Launching;
  final String? cs2LaunchError;
  final bool cs2Live;
  final RTCVideoRenderer? captureRenderer;
  final String? selectedSteamId;
  final void Function(String steamid, String name)? onSelectPlayer;

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
    this.moveStart,
    this.onPlayInCS2,
    this.cs2Launching = false,
    this.cs2LaunchError,
    this.cs2Live = false,
    this.captureRenderer,
    this.selectedSteamId,
    this.onSelectPlayer,
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

  bool get _live => widget.cs2Live && widget.captureRenderer != null;

  List<_RenderedNativePlayer> _playersNow() {
    final tick = widget.currentTick
        .clamp(widget.demo.startTick, widget.demo.endTick)
        .toInt();
    final idx = _nativeFrameIndexAt(widget.demo.frames, tick);
    return _nativePlayersAt(widget.demo.frames, idx, tick);
  }

  int _deathsUpTo(String steamid) {
    final tick = widget.currentTick;
    var deaths = 0;
    bool? wasAlive;
    for (final frame in widget.demo.frames) {
      if (frame.tick > tick) break;
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

  Widget _playerRail() {
    final players = _playersNow();
    if (players.isEmpty) return const SizedBox.shrink();
    final ct = players.where((p) => _isCtTeam(p.team)).toList();
    final t = players.where((p) => !_isCtTeam(p.team)).toList();
    _RenderedNativePlayer? selected;
    for (final p in players) {
      if (p.steamid == widget.selectedSteamId) selected = p;
    }

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
        if (selected != null) ...[
          const SizedBox(height: 6),
          _selectedStats(selected),
        ],
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

  Widget _selectedStats(_RenderedNativePlayer p) {
    final alive = p.isAlive ?? ((p.health ?? 100) > 0);
    final hp = (p.health ?? 100).clamp(0, 100).round();
    final deaths = _deathsUpTo(p.steamid);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BiobaseColors.bg.withAlpha(225),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: BiobaseColors.accent.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: BiobaseColors.text,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isCtTeam(p.team) ? 'CT' : 'T',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _teamColor(p.team),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 60,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: hp / 100,
                backgroundColor: BiobaseColors.surfaceRaised,
                color: hp > 45 ? BiobaseColors.live : BiobaseColors.warning,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            alive ? '$hp HP' : 'DEAD',
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: alive
                  ? (hp > 45 ? BiobaseColors.live : BiobaseColors.warning)
                  : BiobaseColors.error,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Deaths $deaths',
            style: const TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: BiobaseColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.visibility_outlined,
            size: 10,
            color: BiobaseColors.textTertiary,
          ),
          const SizedBox(width: 3),
          const Text(
            'POV in CS2',
            style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
          ),
        ],
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
              final newTick = (tick - widget.demo.tickRateGuess * 5)
                  .clamp(widget.demo.startTick, widget.demo.endTick);
              widget.onJumpToTick(newTick);
              return KeyEventResult.handled;
            case 'Arrow Right':
              final newTick = (tick + widget.demo.tickRateGuess * 5)
                  .clamp(widget.demo.startTick, widget.demo.endTick);
              widget.onJumpToTick(newTick);
              return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            // Main layer: live CS2 render when capturing, tactical map otherwise
            if (_live)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.black,
                    child: RTCVideoView(
                      widget.captureRenderer!,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: _NativeDemoPainter(
                      demo: widget.demo,
                      currentTick: tick,
                      moves: widget.moves,
                      playbackPosition: widget.playbackPosition,
                      selectedSteamId: widget.selectedSteamId,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),

            // Live mode: tactical minimap bottom-right
            if (_live)
              Positioned(
                right: 12,
                bottom: 72,
                width: 280,
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Opacity(
                    opacity: 0.92,
                    child: CustomPaint(
                      painter: _NativeDemoPainter(
                        demo: widget.demo,
                        currentTick: tick,
                        moves: widget.moves,
                        playbackPosition: widget.playbackPosition,
                        selectedSteamId: widget.selectedSteamId,
                        minimap: true,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),

            // Live mode: player rail + selected stats
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

            // Move marking indicator
            if (widget.moveStart != null)
              Positioned(
                top: 10,
                left: 14,
                right: 14,
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: BiobaseColors.warning.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: BiobaseColors.warning.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                            color: BiobaseColors.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Marking move...',
                          style: TextStyle(fontSize: 10, color: BiobaseColors.warning),
                        ),
                      ],
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
            // Scrubber
            SizedBox(
              height: 16,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          activeTrackColor: BiobaseColors.accent,
                          inactiveTrackColor: BiobaseColors.surfaceRaised.withAlpha(180),
                          thumbColor: BiobaseColors.accent,
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: progress.toDouble(),
                          onChanged: (v) => widget.onSeek(v),
                        ),
                      ),
                      // Move range markers
                      for (final move in widget.moves)
                        Positioned(
                          left: 12 + move.startPosition * (constraints.maxWidth - 24),
                          top: 6,
                          child: Container(
                            width: (move.endPosition - move.startPosition) *
                                (constraints.maxWidth - 24),
                            height: 4,
                            decoration: BoxDecoration(
                              color: BiobaseColors.live.withAlpha(140),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      // Move start indicator
                      if (widget.moveStart != null)
                        Positioned(
                          left: 12 + widget.moveStart! * (constraints.maxWidth - 24) - 1,
                          top: 3,
                          child: Container(
                            width: 2,
                            height: 10,
                            color: BiobaseColors.warning,
                          ),
                        ),
                    ],
                  );
                },
              ),
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

class _NativeDemoPainter extends CustomPainter {
  final NativeDemo demo;
  final int currentTick;
  final List<Move> moves;
  final double playbackPosition;
  final String? selectedSteamId;
  final bool minimap;

  _NativeDemoPainter({
    required this.demo,
    required this.currentTick,
    required this.moves,
    required this.playbackPosition,
    this.selectedSteamId,
    this.minimap = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || demo.frames.isEmpty) return;

    final bgPaint = Paint()..color = BiobaseColors.bg;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final inset = minimap ? 8.0 : 18.0;
    final bounds = _DemoBounds.fromFrames(demo.frames);
    final plot = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final scale = math.min(
      plot.width / bounds.width,
      plot.height / bounds.height,
    );
    final scaledWidth = bounds.width * scale;
    final scaledHeight = bounds.height * scale;
    final origin = Offset(
      plot.left + (plot.width - scaledWidth) / 2,
      plot.top + (plot.height - scaledHeight) / 2,
    );

    Offset toScreen(double x, double y) {
      return Offset(
        origin.dx + (x - bounds.minX) * scale,
        origin.dy + scaledHeight - (y - bounds.minY) * scale,
      );
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = BiobaseColors.borderHover;
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot, const Radius.circular(8)),
      borderPaint,
    );

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = BiobaseColors.borderSubtle;
    for (var i = 1; i < 6; i++) {
      final dx = plot.left + plot.width * i / 6;
      final dy = plot.top + plot.height * i / 6;
      canvas.drawLine(Offset(dx, plot.top), Offset(dx, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, dy), Offset(plot.right, dy), gridPaint);
    }

    if (!minimap) {
      _drawText(
        canvas,
        demo.mapName,
        Offset(plot.left + 12, plot.top + 10),
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: BiobaseColors.textSecondary,
        ),
      );
    }

    final dotRadius = minimap ? 3.5 : 6.5;
    final frameIndex = _nativeFrameIndexAt(demo.frames, currentTick);
    final players = _nativePlayersAt(demo.frames, frameIndex, currentTick);
    if (!minimap) _drawPlayerTrails(canvas, toScreen, frameIndex, players);

    for (final p in players) {
      final pos = toScreen(p.x, p.y);
      final teamColor = _teamColor(p.team);
      final alive = p.isAlive ?? ((p.health ?? 100) > 0);
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = alive ? teamColor : BiobaseColors.textTertiary.withAlpha(120);
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.black.withAlpha(130);
      canvas.drawCircle(pos, dotRadius + 1, ringPaint);
      canvas.drawCircle(pos, dotRadius, dotPaint);

      if (p.steamid == selectedSteamId) {
        final selPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = minimap ? 1.4 : 2
          ..color = BiobaseColors.accent;
        canvas.drawCircle(pos, dotRadius + (minimap ? 3 : 6), selPaint);
      }

      if (!minimap) {
        final hp = p.health ?? 100;
        final healthPct = math.max(0.0, math.min(100.0, hp)) / 100.0;
        final healthPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = healthPct > 0.45
              ? BiobaseColors.live
              : BiobaseColors.warning;
        canvas.drawArc(
          Rect.fromCircle(center: pos, radius: 10.5),
          -math.pi / 2,
          math.pi * 2 * healthPct,
          false,
          healthPaint,
        );
      }

      if (p.yaw != null) {
        final radians = (p.yaw! - 90) * math.pi / 180.0;
        final end =
            pos +
            Offset(math.cos(radians), math.sin(radians)) *
                (minimap ? 7.0 : 14.0);
        final aimPaint = Paint()
          ..strokeWidth = minimap ? 1.0 : 1.6
          ..strokeCap = StrokeCap.round
          ..color = teamColor.withAlpha(alive ? 220 : 110);
        canvas.drawLine(pos, end, aimPaint);
      }

      if (!minimap) {
        _drawText(
          canvas,
          _shortName(p.name),
          pos + const Offset(10, -16),
          TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: alive ? BiobaseColors.text : BiobaseColors.textTertiary,
            shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
          ),
          maxWidth: 84,
        );
      }
    }

    if (players.isEmpty) {
      _drawText(
        canvas,
        'No player positions at this tick',
        Offset(plot.center.dx - 86, plot.center.dy - 8),
        const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
        maxWidth: 180,
      );
    }
  }

  void _drawPlayerTrails(
    Canvas canvas,
    Offset Function(double x, double y) toScreen,
    int frameIndex,
    List<_RenderedNativePlayer> currentPlayers,
  ) {
    if (frameIndex <= 0 || currentPlayers.isEmpty) return;
    final currentIds = currentPlayers.map((p) => p.steamid).toSet();
    final start = math.max(0, frameIndex - 18);
    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final id in currentIds) {
      final path = Path();
      var started = false;
      for (var i = start; i <= frameIndex; i++) {
        NativePlayerState? player;
        for (final candidate in demo.frames[i].players) {
          if (candidate.steamid == id) {
            player = candidate;
            break;
          }
        }
        if (player == null) continue;
        final point = toScreen(player.x, player.y);
        if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      final team = currentPlayers.firstWhere((p) => p.steamid == id).team;
      trailPaint.color = _teamColor(team).withAlpha(85);
      canvas.drawPath(path, trailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NativeDemoPainter oldDelegate) {
    return oldDelegate.demo != demo ||
        oldDelegate.currentTick != currentTick ||
        oldDelegate.moves != moves ||
        oldDelegate.playbackPosition != playbackPosition ||
        oldDelegate.selectedSteamId != selectedSteamId ||
        oldDelegate.minimap != minimap;
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

class _DemoBounds {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  const _DemoBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  double get width => math.max(1.0, maxX - minX);
  double get height => math.max(1.0, maxY - minY);

  static _DemoBounds fromFrames(List<NativeDemoFrame> frames) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final frame in frames) {
      for (final player in frame.players) {
        minX = math.min(minX, player.x);
        maxX = math.max(maxX, player.x);
        minY = math.min(minY, player.y);
        maxY = math.max(maxY, player.y);
      }
    }
    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      return const _DemoBounds(
        minX: -1000,
        maxX: 1000,
        minY: -1000,
        maxY: 1000,
      );
    }
    const padding = 350.0;
    return _DemoBounds(
      minX: minX - padding,
      maxX: maxX + padding,
      minY: minY - padding,
      maxY: maxY + padding,
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

void _drawText(
  Canvas canvas,
  String text,
  Offset offset,
  TextStyle style, {
  double maxWidth = 160,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, offset);
}

