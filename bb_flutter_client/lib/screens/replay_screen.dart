import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme.dart';
import '../services/server_service.dart';
import '../services/moves_service.dart';
import '../services/hltv_service.dart';
import '../services/demo_parser.dart';
import '../services/netcon_service.dart';
import '../services/gsi_service.dart';
import '../services/replay_launch_service.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  final ServerService _server = ServerService();
  final MovesService _moves = MovesService();
  final HltvService _hltv = HltvService();
  final NetconService _netcon = NetconService();
  final GsiService _gsi = GsiService();
  final ReplayLaunchService _replayLauncher = ReplayLaunchService();

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

  // CS2 integration state
  bool _cs2Connected = false;
  bool _cs2Connecting = false;
  bool _replayLaunched = false;
  String _connectStatus = 'Waiting for connection';
  GsiState? _gsiState;
  StreamSubscription<GsiState>? _gsiSub;
  StreamSubscription? _netconSub;
  int _currentTick = 0;
  Timer? _tickTimer;
  String? _replayIssue;
  List<String> _replayDiagnostics = const [];

  // Pro demos state
  bool _proExpanded = false;
  List<HltvDemo> _proDemos = [];
  bool _proLoading = false;
  int? _downloadingDemoId;
  double _downloadProgress = 0;
  String? _proMessage;

  // Move marking state
  double? _moveStart;
  List<Move> _demoMoves = [];
  String? _editingMoveId;
  final TextEditingController _renameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDemos();
    _gsiSub = _gsi.stateStream.listen((state) {
      if (mounted) setState(() => _gsiState = state);
    });
  }

  @override
  void dispose() {
    _renameController.dispose();
    _gsiSub?.cancel();
    _netconSub?.cancel();
    _tickTimer?.cancel();
    _netcon.dispose();
    _gsi.dispose();
    super.dispose();
  }

  void _resetReplayState() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _netconSub?.cancel();
    _netconSub = null;
    _netcon.disconnect();
    _playbackPosition = 0;
    _playbackSpeed = 1.0;
    _playing = false;
    _cs2Connected = false;
    _cs2Connecting = false;
    _replayLaunched = false;
    _currentTick = 0;
    _connectStatus = 'Waiting for connection';
    _replayIssue = null;
    _replayDiagnostics = const [];
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
      _demoInfo = null;
    });
    final info = await DemoParser.parse(path);
    if (mounted)
      setState(() {
        _demoInfo = info;
        _parsingDemo = false;
      });
  }

  Future<void> _watchInCS2() async {
    final sourcePath = _demoPath;
    if (sourcePath == null) return;

    _tickTimer?.cancel();
    _netconSub?.cancel();
    _netconSub = null;
    _netcon.stopReconnect();

    if (mounted) {
      setState(() {
        _cs2Connecting = true;
        _cs2Connected = false;
        _replayLaunched = false;
        _playing = false;
        _currentTick = 0;
        _playbackPosition = 0;
        _connectStatus = 'Preparing demo...';
        _replayIssue = null;
        _replayDiagnostics = const [];
      });
    }

    ReplayDemoTarget target;
    try {
      target = await _replayLauncher.prepareDemo(sourcePath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cs2Connecting = false;
        _replayIssue = 'Could not prepare demo for CS2: $e';
      });
      return;
    }

    final diagnostics = <String>[
      target.staged
          ? 'Demo staged at ${target.stagedPath}'
          : 'Using absolute demo path ${target.consolePath}',
      'Replay command: ${ReplayLaunchService.buildPlaydemoCommand(target.consolePath)}',
    ];

    if (mounted) {
      setState(() {
        _connectStatus = 'Installing GSI config...';
        _replayDiagnostics = diagnostics;
      });
    }

    final gsiInstalled = await GsiService.installConfig();
    final gsiStarted = await _gsi.start();
    diagnostics.add(
      gsiInstalled ? 'GSI config installed.' : 'GSI config path was not found.',
    );
    diagnostics.add(
      gsiStarted ? 'GSI receiver listening.' : 'GSI receiver could not start.',
    );

    if (!mounted) return;
    setState(() {
      _connectStatus = 'Checking CS2 control socket...';
      _replayDiagnostics = List.of(diagnostics);
    });

    if (await _netcon.connect()) {
      diagnostics.add('Netcon was already available.');
      if (mounted) setState(() => _replayDiagnostics = List.of(diagnostics));
      await _startDemoOverNetcon(target);
      return;
    }

    if (mounted) {
      setState(() {
        _connectStatus = 'Launching CS2 replay...';
        _replayDiagnostics = List.of(diagnostics);
      });
    }

    final launch = await _replayLauncher.launchForReplay(target);
    diagnostics.addAll(launch.diagnostics);
    if (!mounted) return;
    setState(() {
      _replayDiagnostics = List.of(diagnostics);
      _connectStatus = launch.started
          ? 'Waiting for CS2 control socket...'
          : 'Could not launch CS2';
    });

    if (!launch.started) {
      setState(() {
        _cs2Connecting = false;
        _replayIssue = diagnostics.isEmpty
            ? 'CS2 could not be launched.'
            : diagnostics.last;
      });
      return;
    }

    final connected = await _waitForNetcon(
      timeout: const Duration(seconds: 45),
    );
    if (!mounted) return;
    if (connected) {
      diagnostics.add('Netcon connected after launch.');
      setState(() => _replayDiagnostics = List.of(diagnostics));
      await _startDemoOverNetcon(target);
      return;
    }

    diagnostics.add(
      'Netcon did not open; CS2 was launched after patching Steam LaunchOptions and replay cfg bootstrap.',
    );
    setState(() {
      _cs2Connecting = false;
      _cs2Connected = false;
      _replayLaunched = true;
      _playing = true;
      _connectStatus = 'Replay launched in CS2';
      _replayDiagnostics = List.of(diagnostics);
      _replayIssue =
          'BioBase patched Steam LaunchOptions and staged the replay cfg, but CS2 still did not open Netcon. If the demo is not playing, Steam did not apply the patched LaunchOptions on this launch.';
    });
    _startBackgroundNetconReconnect(target);
  }

  Future<void> _startDemoOverNetcon(ReplayDemoTarget target) async {
    if (!mounted) return;
    setState(() {
      _cs2Connecting = true;
      _connectStatus = 'Starting demo in CS2...';
      _replayIssue = null;
    });

    final sent = await _netcon.playDemo(target.consolePath);
    if (!sent) {
      if (!mounted) return;
      setState(() {
        _cs2Connecting = false;
        _cs2Connected = false;
        _replayIssue =
            'Connected to CS2, but the playdemo command could not be sent.';
      });
      _startBackgroundNetconReconnect(target);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 350));
    await _netcon.resumeDemo();
    await _netcon.setTimescale(_playbackSpeed);

    if (!mounted) return;
    setState(() {
      _cs2Connected = true;
      _cs2Connecting = false;
      _replayLaunched = true;
      _playing = true;
      _connectStatus = 'Playing demo in CS2';
    });
    _startTickTracking();
  }

  Future<bool> _waitForNetcon({
    Duration timeout = const Duration(seconds: 75),
  }) async {
    final started = DateTime.now();
    var attempt = 0;
    while (DateTime.now().difference(started) < timeout) {
      attempt += 1;
      if (await _netcon.connect()) return true;
      if (!mounted) return false;
      final elapsed = DateTime.now().difference(started).inSeconds;
      setState(() {
        _connectStatus = 'Waiting for CS2 control socket... ${elapsed}s';
      });
      await Future.delayed(Duration(seconds: attempt < 5 ? 2 : 3));
    }
    return false;
  }

  void _startBackgroundNetconReconnect(ReplayDemoTarget target) {
    _netconSub?.cancel();
    _netconSub = Stream.periodic(const Duration(seconds: 3)).listen((_) async {
      final connected = _netcon.connected || await _netcon.connect();
      if (!connected || !mounted) return;
      _netconSub?.cancel();
      await _startDemoOverNetcon(target);
    });
  }

  void _startTickTracking() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_playing || _demoInfo == null) return;
      final totalTicks = _demoInfo!.playbackTicks ?? 0;
      if (totalTicks <= 0) return;
      if (mounted) {
        setState(() {
          _currentTick += (64 * 0.2 * _playbackSpeed).round();
          if (_currentTick > totalTicks) _currentTick = totalTicks;
          _playbackPosition = _currentTick / totalTicks;
        });
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (!_cs2Connected) return;
    if (_playing) {
      await _netcon.pauseDemo();
      _tickTimer?.cancel();
    } else {
      await _netcon.resumeDemo();
      _startTickTracking();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  Future<void> _setSpeed(double speed) async {
    if (!_cs2Connected) return;
    await _netcon.setTimescale(speed);
    if (mounted) setState(() => _playbackSpeed = speed);
  }

  Future<void> _seekTo(double position) async {
    if (!_cs2Connected || _demoInfo == null) return;
    final totalTicks = _demoInfo!.playbackTicks ?? 0;
    if (totalTicks <= 0) return;
    final tick = (position * totalTicks).round();
    await _netcon.gotoTick(tick);
    if (mounted)
      setState(() {
        _currentTick = tick;
        _playbackPosition = position;
      });
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
      final totalTicks = _demoInfo?.playbackTicks;
      final startTick = totalTicks != null ? (s * totalTicks).round() : null;
      final endTick = totalTicks != null ? (e * totalTicks).round() : null;
      _moves.addMove(
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
    }
  }

  void _cancelMark() {
    setState(() => _moveStart = null);
  }

  void _deleteMove(String id) {
    _moves.deleteMove(id);
    setState(() => _demoMoves = _moves.movesForDemo(_demoName!));
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
    if (_cs2Connected) {
      _seekTo(move.startPosition);
    } else {
      setState(() => _playbackPosition = move.startPosition);
    }
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
            parsingDemo: _parsingDemo,
            cs2Connected: _cs2Connected,
            cs2Connecting: _cs2Connecting,
            replayLaunched: _replayLaunched,
            connectStatus: _connectStatus,
            replayIssue: _replayIssue,
            replayDiagnostics: _replayDiagnostics,
            gsiState: _gsiState,
            playing: _playing,
            moves: _demoMoves,
            playbackPosition: _playbackPosition,
            moveStart: _moveStart,
            onWatchInCS2: _watchInCS2,
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
                onChanged: _demoPath != null
                    ? (v) {
                        setState(() => _playbackPosition = v);
                        if (_cs2Connected) _seekTo(v);
                      }
                    : null,
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
  final bool parsingDemo;
  final bool cs2Connected;
  final bool cs2Connecting;
  final bool replayLaunched;
  final String connectStatus;
  final String? replayIssue;
  final List<String> replayDiagnostics;
  final GsiState? gsiState;
  final bool playing;
  final List<Move> moves;
  final double playbackPosition;
  final double? moveStart;
  final VoidCallback onWatchInCS2;

  const _RenderArea({
    required this.demoPath,
    required this.demoName,
    required this.demoInfo,
    required this.parsingDemo,
    required this.cs2Connected,
    required this.cs2Connecting,
    required this.replayLaunched,
    required this.connectStatus,
    required this.replayIssue,
    required this.replayDiagnostics,
    required this.gsiState,
    required this.playing,
    required this.moves,
    required this.playbackPosition,
    required this.onWatchInCS2,
    this.moveStart,
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

    return Stack(
      children: [
        Center(
          child: parsingDemo
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BiobaseColors.textTertiary,
                  ),
                )
              : info == null
              ? Column(
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
                  ],
                )
              : _demoInfoDisplay(info),
        ),
        // Connection status badge
        if (demoInfo != null)
          Positioned(top: 12, right: 12, child: _connectionBadge()),
        // GSI round info
        if (cs2Connected && gsiState != null && gsiState!.round > 0)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: BiobaseColors.bg.withAlpha(200),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Round ${gsiState!.round}',
                style: const TextStyle(
                  fontSize: 10,
                  color: BiobaseColors.textSecondary,
                ),
              ),
            ),
          ),
        // Move marking indicator
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

  Widget _connectionBadge() {
    if (cs2Connected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BiobaseColors.liveDim,
          borderRadius: BorderRadius.circular(4),
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
            Text(
              playing ? 'Playing in CS2' : 'Paused',
              style: const TextStyle(fontSize: 10, color: BiobaseColors.live),
            ),
          ],
        ),
      );
    }
    if (cs2Connecting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BiobaseColors.accentDim,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: BiobaseColors.accent,
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Connecting...',
              style: TextStyle(fontSize: 10, color: BiobaseColors.accent),
            ),
          ],
        ),
      );
    }
    if (replayLaunched) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BiobaseColors.accentDim,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              size: 12,
              color: BiobaseColors.accent,
            ),
            SizedBox(width: 6),
            Text(
              'Launched',
              style: TextStyle(fontSize: 10, color: BiobaseColors.accent),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
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
          if (cs2Connecting)
            _launchingInfo()
          else if (cs2Connected)
            _connectedInfo()
          else if (replayLaunched)
            _launchedInfo()
          else
            _WatchButton(onTap: onWatchInCS2),
          if (replayIssue != null) ...[
            const SizedBox(height: 12),
            _issueBox(replayIssue!),
          ],
          if (replayDiagnostics.isNotEmpty) ...[
            const SizedBox(height: 10),
            _diagnosticsBox(),
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

  Widget _launchingInfo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: BiobaseColors.accent,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          connectStatus,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: BiobaseColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _launchedInfo() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: BiobaseColors.accent,
            ),
            SizedBox(width: 8),
            Text(
              'Replay launched in CS2',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: BiobaseColors.accent,
              ),
            ),
          ],
        ),
        SizedBox(height: 6),
        Text(
          'BioBase is waiting for controls to attach.',
          style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary),
        ),
      ],
    );
  }

  Widget _connectedInfo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: playing
                    ? BiobaseColors.live
                    : BiobaseColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              playing ? 'Playing in CS2' : 'Paused',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: playing
                    ? BiobaseColors.live
                    : BiobaseColors.textSecondary,
              ),
            ),
          ],
        ),
        if (gsiState != null && gsiState!.mapPhase.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            gsiState!.mapPhase,
            style: const TextStyle(
              fontSize: 10,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ],
    );
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

  Widget _diagnosticsBox() {
    const maxDiagnosticLines = 10;
    final lines = replayDiagnostics.length <= maxDiagnosticLines
        ? replayDiagnostics
        : replayDiagnostics.sublist(
            replayDiagnostics.length - maxDiagnosticLines,
          );
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BiobaseColors.bg.withAlpha(130),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BiobaseColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Replay diagnostics',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.8,
              color: BiobaseColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $line',
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.25,
                  color: BiobaseColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WatchButton extends StatefulWidget {
  final VoidCallback onTap;
  const _WatchButton({required this.onTap});

  @override
  State<_WatchButton> createState() => _WatchButtonState();
}

class _WatchButtonState extends State<_WatchButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? BiobaseColors.accent : BiobaseColors.accentDim,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hovered
                  ? BiobaseColors.accent
                  : BiobaseColors.accent.withAlpha(60),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 18,
                color: _hovered ? Colors.white : BiobaseColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Watch in CS2',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _hovered ? Colors.white : BiobaseColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
