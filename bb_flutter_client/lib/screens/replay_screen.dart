import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme.dart';
import '../services/server_service.dart';
import '../services/moves_service.dart';
import '../services/hltv_service.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  final ServerService _server = ServerService();
  final MovesService _moves = MovesService();
  final HltvService _hltv = HltvService();

  List<DemoFile>? _demos;
  bool _loading = true;
  String? _demoPath;
  String? _demoName;
  int? _demoSize;
  double _playbackPosition = 0;
  double _playbackSpeed = 1.0;
  bool _playing = false;
  bool _copying = false;

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
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  Future<void> _loadDemos() async {
    setState(() => _loading = true);
    final demos = await _server.listDemos();
    if (mounted) setState(() { _demos = demos; _loading = false; });
  }

  Future<void> _loadProDemos() async {
    setState(() { _proLoading = true; _proMessage = null; });
    try {
      final demos = await _hltv.fetchDemos();
      if (mounted) setState(() { _proDemos = demos; _proLoading = false; });
    } catch (e) {
      if (mounted) setState(() {
        _proLoading = false;
        _proMessage = 'Could not connect to demo server';
      });
    }
  }

  Future<void> _downloadProDemo(HltvDemo demo) async {
    setState(() { _downloadingDemoId = demo.id; _downloadProgress = 0; _proMessage = null; });
    try {
      final path = await _hltv.downloadDemo(demo, onProgress: (progress) {
        if (mounted) setState(() => _downloadProgress = progress);
      });
      demo.localPath = path;
      if (mounted) setState(() { _downloadingDemoId = null; });
    } catch (e) {
      if (mounted) setState(() {
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
      _demoSize = demo.sizeBytes;
      _playbackPosition = 0;
      _playing = false;
      _moveStart = null;
      _demoMoves = _moves.movesForDemo(demo.filename);
    });
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
          _demoSize = demo.sizeBytes;
          _playbackPosition = 0;
          _playing = false;
          _moveStart = null;
          _demoMoves = _moves.movesForDemo(demo.name);
        }
      });
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
        _demoSize = result.files.single.size;
        _playbackPosition = 0;
        _playing = false;
        _moveStart = null;
        _demoMoves = _moves.movesForDemo(result.files.single.name);
      });
    }
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
      _moves.addMove(demoName: _demoName!, startPosition: s, endPosition: e);
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
    setState(() => _playbackPosition = move.startPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: _buildLeft(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RenderArea(
            demoPath: _demoPath,
            demoName: _demoName,
            moves: _demoMoves,
            playbackPosition: _playbackPosition,
            moveStart: _moveStart,
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
              const Text('Demos',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BiobaseColors.text)),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: BiobaseColors.textTertiary),
                )
              else
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _loadDemos,
                    child: const Icon(Icons.refresh,
                        size: 14, color: BiobaseColors.textTertiary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('Loading demos...',
                    style: TextStyle(
                        fontSize: 11, color: BiobaseColors.textTertiary)),
              ),
            )
          else if (_demos == null || _demos!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(children: [
                  Text('No demos recorded yet',
                      style: TextStyle(
                          fontSize: 11, color: BiobaseColors.textTertiary)),
                  SizedBox(height: 4),
                  Text('Play a match to generate a demo',
                      style: TextStyle(
                          fontSize: 10, color: BiobaseColors.textTertiary)),
                ]),
              ),
            )
          else
            ...(_demos!.map((d) => _DemoRow(
                  demo: d,
                  selected: _demoName == d.name,
                  onTap: _copying ? null : () => _selectDemo(d),
                ))),
          const SizedBox(height: 10),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _pickLocal,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open,
                      size: 12, color: BiobaseColors.textTertiary),
                  SizedBox(width: 4),
                  Text('Open file',
                      style: TextStyle(
                          fontSize: 10, color: BiobaseColors.textTertiary)),
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
                  const Text('Pro Demos',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BiobaseColors.text)),
                  const Spacer(),
                  if (_proDemos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('${_proDemos.length}',
                          style: const TextStyle(
                              fontSize: 10, color: BiobaseColors.textTertiary)),
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
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: BiobaseColors.textTertiary),
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
                            color: BiobaseColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (first.event.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(first.event,
                            style: const TextStyle(
                                fontSize: 9, color: BiobaseColors.textTertiary),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ...demos.map((d) => _ProDemoRow(
                          demo: d,
                          selected: _demoName == d.filename,
                          downloading: _downloadingDemoId == d.id,
                          downloadProgress: _downloadingDemoId == d.id
                              ? _downloadProgress : 0,
                          onTap: d.localPath != null
                              ? () => _selectProDemo(d)
                              : () => _downloadProDemo(d),
                        )),
                  ],
                );
              }),
            if (_proMessage != null && _proDemos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_proMessage!,
                    style: const TextStyle(
                        fontSize: 10, color: BiobaseColors.error)),
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
          const Text('Playback',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text)),
          const SizedBox(height: 10),
          _buildTimeline(),
          const SizedBox(height: 4),
          Row(children: [
            Text(_formatTime(_playbackPosition),
                style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: BiobaseColors.textTertiary)),
            const Spacer(),
            Text(_formatTime(1.0),
                style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: BiobaseColors.textTertiary)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _controlBtn(Icons.skip_previous,
                () => setState(() => _playbackPosition = 0)),
            const SizedBox(width: 4),
            _controlBtn(
                _playing ? Icons.pause : Icons.play_arrow,
                () => setState(() => _playing = !_playing),
                primary: true),
            const SizedBox(width: 4),
            _controlBtn(Icons.skip_next,
                () => setState(() => _playbackPosition = 1)),
            const Spacer(),
            ...([0.25, 0.5, 1.0, 2.0].map((s) => Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: _speedBtn(s, _playbackSpeed == s,
                      () => setState(() => _playbackSpeed = s)),
                ))),
          ]),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return LayoutBuilder(builder: (context, constraints) {
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
              value: _playbackPosition,
              onChanged: _demoPath != null
                  ? (v) => setState(() => _playbackPosition = v)
                  : null,
            ),
          ),
          // Move range markers on the track
          for (final move in _demoMoves)
            Positioned(
              left: 12 + move.startPosition * (constraints.maxWidth - 24),
              top: 6,
              child: Container(
                width: (move.endPosition - move.startPosition) *
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
    });
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
          color: marking ? BiobaseColors.warning.withAlpha(60) : BiobaseColors.border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Moves',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BiobaseColors.text)),
            const Spacer(),
            if (_demoMoves.isNotEmpty)
              Text('${_demoMoves.length}',
                  style: const TextStyle(
                      fontSize: 10, color: BiobaseColors.textTertiary)),
          ]),
          const SizedBox(height: 10),

          // Mark button
          if (hasDemo) ...[
            Row(children: [
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
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: BiobaseColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: BiobaseColors.border),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 10,
                              color: BiobaseColors.textTertiary)),
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
          ],

          // Moves list
          if (!hasDemo)
            const Text('Load a demo to mark moves',
                style: TextStyle(
                    fontSize: 11, color: BiobaseColors.textTertiary))
          else if (_demoMoves.isEmpty && !marking)
            const Text('No moves marked yet',
                style: TextStyle(
                    fontSize: 11, color: BiobaseColors.textTertiary))
          else
            ...(_demoMoves.map((m) => _MoveRow(
                  move: m,
                  editing: _editingMoveId == m.id,
                  renameController: _renameController,
                  formatTime: _formatTime,
                  onTap: () => _jumpToMove(m),
                  onRename: () => _startRename(m),
                  onCommitRename: () => _commitRename(m.id),
                  onDelete: () => _deleteMove(m.id),
                ))),
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
          const Text('Round Stats',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text)),
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
          const Text('Events',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text)),
          const SizedBox(height: 10),
          if (_demoPath == null)
            const Text('Select a demo to see events',
                style: TextStyle(
                    fontSize: 11, color: BiobaseColors.textTertiary))
          else
            const Text('Demo parsing in progress',
                style: TextStyle(
                    fontSize: 11, color: BiobaseColors.textTertiary)),
        ],
      ),
    );
  }

  // ── Shared helpers ──

  Widget _controlBtn(IconData icon, VoidCallback onTap,
      {bool primary = false}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _demoPath != null ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color:
                primary ? BiobaseColors.accent : BiobaseColors.surfaceRaised,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon,
              size: 16,
              color: _demoPath != null
                  ? Colors.white
                  : BiobaseColors.textTertiary),
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
          child: Text('${s}x',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: active
                      ? BiobaseColors.accent
                      : BiobaseColors.textTertiary)),
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
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: BiobaseColors.textTertiary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  String _formatTime(double t) {
    final mins = (t * 45).toInt();
    final secs = ((t * 45 * 60) % 60).toInt();
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
                ? (_hovered ? BiobaseColors.warning : BiobaseColors.warning.withAlpha(200))
                : (_hovered ? BiobaseColors.accentDim : BiobaseColors.surfaceRaised),
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
                  color: marking ? BiobaseColors.bg : BiobaseColors.textSecondary,
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
                              fontSize: 11, color: BiobaseColors.text),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => widget.onCommitRename(),
                        ),
                      )
                    else
                      Text(m.name,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: BiobaseColors.text)),
                    const SizedBox(height: 1),
                    Text(timeRange,
                        style: const TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            color: BiobaseColors.textTertiary)),
                  ],
                ),
              ),
              if (_hovered && !widget.editing) ...[
                GestureDetector(
                  onTap: widget.onRename,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.edit_outlined,
                        size: 11, color: BiobaseColors.textTertiary),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        size: 11, color: BiobaseColors.textTertiary),
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

  const _DemoRow({
    required this.demo,
    required this.selected,
    this.onTap,
  });

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
              Icon(Icons.videocam_outlined,
                  size: 12,
                  color: widget.selected
                      ? BiobaseColors.accent
                      : BiobaseColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: widget.selected
                                ? BiobaseColors.accent
                                : BiobaseColors.text),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(
                        '${_formatSize(d.sizeBytes)}  ·  ${_formatDate(d.modified)}',
                        style: const TextStyle(
                            fontSize: 9, color: BiobaseColors.textTertiary)),
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
                    Text(d.displayName,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: widget.selected
                                ? BiobaseColors.accent
                                : BiobaseColors.text),
                        overflow: TextOverflow.ellipsis),
                    Text(_formatSize(d.sizeBytes),
                        style: const TextStyle(
                            fontSize: 9, color: BiobaseColors.textTertiary)),
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
                        color: BiobaseColors.accent),
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
  final List<Move> moves;
  final double playbackPosition;
  final double? moveStart;

  const _RenderArea({
    required this.demoPath,
    required this.demoName,
    required this.moves,
    required this.playbackPosition,
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
          Icon(Icons.videocam_outlined,
              size: 48, color: BiobaseColors.textTertiary.withAlpha(80)),
          const SizedBox(height: 12),
          const Text('No demo selected',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: BiobaseColors.textTertiary)),
          const SizedBox(height: 4),
          const Text('Select a demo from the list to start replay',
              style: TextStyle(
                  fontSize: 11, color: BiobaseColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _loadedState() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_outline,
                  size: 64, color: BiobaseColors.accent.withAlpha(60)),
              const SizedBox(height: 12),
              Text(demoName ?? '',
                  style: const TextStyle(
                      fontSize: 12, color: BiobaseColors.textSecondary)),
              const SizedBox(height: 4),
              const Text('Demo render engine loading',
                  style: TextStyle(
                      fontSize: 11, color: BiobaseColors.textTertiary)),
            ],
          ),
        ),
        // Minimap placeholder
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              color: BiobaseColors.bg.withAlpha(180),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: BiobaseColors.border),
            ),
            child: const Center(
              child: Text('Minimap',
                  style: TextStyle(
                      fontSize: 9, color: BiobaseColors.textTertiary)),
            ),
          ),
        ),
        // Round indicator
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: BiobaseColors.bg.withAlpha(180),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Round 1 / —',
                style: TextStyle(
                    fontSize: 10, color: BiobaseColors.textTertiary)),
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
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: BiobaseColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Marking move...',
                      style: TextStyle(
                          fontSize: 10, color: BiobaseColors.warning)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
