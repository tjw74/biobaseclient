import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/shadow.dart';
import '../services/api_service.dart';
import '../services/shadow_service.dart';
import '../theme.dart';

enum _View { library, capture, captureForm, detail, attemptResult }

class ShadowScreen extends StatefulWidget {
  final ApiService api;
  final String mapName;
  final bool live;

  const ShadowScreen({
    super.key,
    required this.api,
    this.mapName = '',
    this.live = false,
  });

  @override
  State<ShadowScreen> createState() => _ShadowScreenState();
}

class _ShadowScreenState extends State<ShadowScreen> {
  late final ShadowService _shadow;
  _View _view = _View.library;
  List<ShadowMove> _moves = [];
  ShadowMove? _selectedMove;
  List<ShadowAttempt> _attempts = [];
  ShadowAttempt? _selectedAttempt;
  bool _loading = true;
  String? _error;

  final List<ShadowTick> _capturedTicks = [];
  StreamSubscription? _captureSub;
  Timer? _captureTimer;
  int _captureElapsed = 0;
  int _captureStartTick = -1;
  bool _isAttemptCapture = false;
  final _nameCtrl = TextEditingController();
  String _difficulty = 'medium';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _shadow = ShadowService(baseUrl: widget.api.baseUrl);
    _loadMoves();
  }

  @override
  void dispose() {
    _captureSub?.cancel();
    _captureTimer?.cancel();
    _nameCtrl.dispose();
    _shadow.dispose();
    super.dispose();
  }

  Future<void> _loadMoves() async {
    setState(() { _loading = true; _error = null; });
    try {
      _moves = await _shadow.listMoves();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _beginCapture({bool attempt = false}) {
    _capturedTicks.clear();
    _captureStartTick = -1;
    _captureElapsed = 0;
    _isAttemptCapture = attempt;
    _captureTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _captureElapsed++);
    });
    _captureSub = widget.api.movementStream.listen((m) {
      final t = m.tracked ?? m.samples.firstOrNull;
      if (t == null) return;
      if (_captureStartTick < 0) _captureStartTick = t.tick;
      _capturedTicks.add(ShadowTick(
        tickOffset: t.tick - _captureStartTick,
        x: t.pos.isNotEmpty ? t.pos[0] : 0,
        y: t.pos.length > 1 ? t.pos[1] : 0,
        z: t.pos.length > 2 ? t.pos[2] : 0,
        velX: t.velX, velY: t.velY, velZ: t.velZ,
        speed: t.speed, yaw: t.yaw, pitch: t.pitch,
        onGround: t.onGround, ducking: t.keys.crouch,
      ));
      if (mounted) setState(() {});
    });
    setState(() => _view = _View.capture);
  }

  void _stopCapture() {
    _captureSub?.cancel();
    _captureSub = null;
    _captureTimer?.cancel();
    _captureTimer = null;
    _nameCtrl.clear();
    _difficulty = 'medium';
    setState(() => _view = _View.captureForm);
  }

  Future<void> _saveCapture() async {
    if (_capturedTicks.isEmpty || _nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await _shadow.createMove(
        name: _nameCtrl.text.trim(),
        ticks: _capturedTicks,
        mapName: widget.mapName,
        difficulty: _difficulty,
      );
      await _loadMoves();
      if (mounted) setState(() { _view = _View.library; _saving = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _saving = false; });
    }
  }

  Future<void> _openDetail(ShadowMove move) async {
    setState(() => _loading = true);
    try {
      final full = await _shadow.getMove(move.id);
      final attempts = await _shadow.listAttempts(move.id);
      if (mounted) setState(() {
        _selectedMove = full;
        _attempts = attempts;
        _view = _View.detail;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _finishAttempt() async {
    _captureSub?.cancel();
    _captureSub = null;
    _captureTimer?.cancel();
    _captureTimer = null;
    if (_selectedMove == null || _capturedTicks.isEmpty) {
      setState(() => _view = _View.detail);
      return;
    }
    setState(() => _loading = true);
    try {
      final attempt = await _shadow.createAttempt(
        moveId: _selectedMove!.id,
        ticks: _capturedTicks,
      );
      if (mounted) setState(() {
        _selectedAttempt = attempt;
        _view = _View.attemptResult;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteMove(String id) async {
    await _shadow.deleteMove(id);
    await _loadMoves();
    if (mounted) setState(() => _view = _View.library);
  }

  void _back() {
    _captureSub?.cancel();
    _captureTimer?.cancel();
    setState(() {
      if (_view == _View.attemptResult) {
        _view = _View.detail;
        _selectedAttempt = null;
      } else {
        _view = _View.library;
        _selectedMove = null;
        _selectedAttempt = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(fontSize: 11, color: BiobaseColors.error)),
          const SizedBox(height: 8),
          TextButton(onPressed: () { _error = null; _loadMoves(); }, child: const Text('Retry', style: TextStyle(fontSize: 11))),
        ],
      ));
    }
    if (_loading && _view == _View.library) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: BiobaseColors.accent));
    }
    return switch (_view) {
      _View.library => _buildLibrary(),
      _View.capture => _buildCapture(),
      _View.captureForm => _buildCaptureForm(),
      _View.detail => _buildDetail(),
      _View.attemptResult => _buildAttemptResult(),
    };
  }

  // ── Library ──

  Widget _buildLibrary() => Column(
    children: [
      Row(children: [
        const Text('SHADOW LIBRARY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: BiobaseColors.accent)),
        const Spacer(),
        _PillBtn(label: 'CAPTURE', icon: Icons.fiber_manual_record, color: BiobaseColors.error, onTap: widget.live ? () => _beginCapture() : null),
      ]),
      const SizedBox(height: 12),
      if (_moves.isEmpty)
        Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.route, size: 40, color: BiobaseColors.textTertiary),
          const SizedBox(height: 10),
          const Text('No shadow moves', style: TextStyle(fontSize: 13, color: BiobaseColors.textSecondary)),
          const SizedBox(height: 4),
          const Text('Record a movement route to compare against later.', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
          if (widget.live) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => _beginCapture(),
              icon: const Icon(Icons.fiber_manual_record, size: 10),
              label: const Text('Start Capture', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: BiobaseColors.accent, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ])))
      else
        Expanded(child: ListView.separated(
          itemCount: _moves.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (_, i) {
            final m = _moves[i];
            return GestureDetector(
              onTap: () => _openDetail(m),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BiobaseColors.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: BiobaseColors.borderSubtle),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: BiobaseColors.text)),
                    const SizedBox(height: 3),
                    Row(children: [
                      if (m.mapName.isNotEmpty) ...[Text(m.mapName, style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)), const SizedBox(width: 8)],
                      Text(m.difficulty.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: _diffColor(m.difficulty))),
                      const SizedBox(width: 8),
                      Text('${m.durationSeconds.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
                    ]),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${m.attemptCount}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w300, color: BiobaseColors.textSecondary)),
                    const Text('attempts', style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary)),
                  ]),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 14, color: BiobaseColors.textTertiary),
                ]),
              ),
            );
          },
        )),
    ],
  );

  // ── Capture ──

  Widget _buildCapture() {
    final speed = _capturedTicks.isNotEmpty ? _capturedTicks.last.speed : 0.0;
    return Column(children: [
      Row(children: [
        GestureDetector(onTap: _back, child: const Icon(Icons.arrow_back, size: 16, color: BiobaseColors.textSecondary)),
        const SizedBox(width: 8),
        Text(
          _isAttemptCapture ? 'ATTEMPTING: ${_selectedMove?.name.toUpperCase() ?? ''}' : 'RECORDING SHADOW MOVE',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: BiobaseColors.error),
        ),
      ]),
      const Spacer(),
      const _PulsingDot(),
      const SizedBox(height: 16),
      Text(_fmtTime(_captureElapsed), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w200, color: BiobaseColors.text, letterSpacing: -2)),
      const SizedBox(height: 8),
      Text('${speed.toStringAsFixed(0)} u/s', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w300, color: BiobaseColors.textSecondary)),
      const SizedBox(height: 4),
      Text('${_capturedTicks.length} samples', style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
      if (_isAttemptCapture && _selectedMove != null && _selectedMove!.ticks.isNotEmpty) ...[
        const SizedBox(height: 20),
        SizedBox(height: 120, child: CustomPaint(size: const Size(double.infinity, 120), painter: _CompPathPainter(ref: _selectedMove!.ticks, attempt: _capturedTicks))),
      ],
      const Spacer(),
      SizedBox(width: 180, height: 44, child: ElevatedButton(
        onPressed: _isAttemptCapture ? _finishAttempt : _stopCapture,
        style: ElevatedButton.styleFrom(
          backgroundColor: BiobaseColors.error, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(_isAttemptCapture ? 'FINISH ATTEMPT' : 'STOP RECORDING', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      )),
      const SizedBox(height: 32),
    ]);
  }

  // ── Capture Form ──

  Widget _buildCaptureForm() => Column(children: [
    Row(children: [
      GestureDetector(onTap: _back, child: const Icon(Icons.arrow_back, size: 16, color: BiobaseColors.textSecondary)),
      const SizedBox(width: 8),
      const Text('SAVE SHADOW MOVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: BiobaseColors.accent)),
    ]),
    const SizedBox(height: 12),
    if (_capturedTicks.length >= 2)
      SizedBox(height: 140, child: CustomPaint(size: const Size(double.infinity, 140), painter: _SinglePathPainter(ticks: _capturedTicks))),
    const SizedBox(height: 10),
    Row(children: [
      Text('${_capturedTicks.length} samples', style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
      const SizedBox(width: 12),
      Text(_fmtTime(_captureElapsed), style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
      if (widget.mapName.isNotEmpty) ...[const SizedBox(width: 12), Text(widget.mapName, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary))],
    ]),
    const SizedBox(height: 14),
    TextField(
      controller: _nameCtrl,
      style: const TextStyle(fontSize: 13, color: BiobaseColors.text),
      decoration: InputDecoration(
        hintText: 'Move name',
        hintStyle: const TextStyle(color: BiobaseColors.textTertiary, fontSize: 13),
        filled: true, fillColor: BiobaseColors.surfaceRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: BiobaseColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: BiobaseColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: BiobaseColors.accent)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
    const SizedBox(height: 8),
    Row(children: [
      for (final d in ['easy', 'medium', 'hard'])
        Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(
          onTap: () => setState(() => _difficulty = d),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _difficulty == d ? BiobaseColors.accentDim : BiobaseColors.surfaceRaised,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: _difficulty == d ? BiobaseColors.accent : BiobaseColors.border),
            ),
            child: Text(d.toUpperCase(), style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5,
              color: _difficulty == d ? BiobaseColors.accent : BiobaseColors.textSecondary,
            )),
          ),
        )),
    ]),
    const Spacer(),
    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      TextButton(onPressed: _back, child: const Text('Discard', style: TextStyle(fontSize: 12, color: BiobaseColors.textSecondary))),
      const SizedBox(width: 8),
      ElevatedButton(
        onPressed: _saving ? null : _saveCapture,
        style: ElevatedButton.styleFrom(
          backgroundColor: BiobaseColors.accent, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
        child: Text(_saving ? 'Saving…' : 'Save', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    ]),
    const SizedBox(height: 12),
  ]);

  // ── Detail ──

  Widget _buildDetail() {
    final m = _selectedMove;
    if (m == null || _loading) return const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: BiobaseColors.accent));
    return ListView(padding: EdgeInsets.zero, children: [
      Row(children: [
        GestureDetector(onTap: _back, child: const Icon(Icons.arrow_back, size: 16, color: BiobaseColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(child: Text(m.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BiobaseColors.text), overflow: TextOverflow.ellipsis)),
        _PillBtn(label: 'DELETE', icon: Icons.delete_outline, color: BiobaseColors.error, onTap: () => _deleteMove(m.id)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 4, children: [
        if (m.mapName.isNotEmpty) _Chip(m.mapName, Icons.map_outlined),
        _Chip(m.difficulty.toUpperCase(), Icons.speed),
        _Chip('${m.durationSeconds.toStringAsFixed(1)}s', Icons.timer_outlined),
        _Chip('${m.ticks.length} ticks', Icons.timeline),
      ]),
      const SizedBox(height: 12),
      if (m.ticks.length >= 2) ...[
        Container(
          height: 200,
          decoration: BoxDecoration(color: BiobaseColors.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: BiobaseColors.border)),
          child: CustomPaint(size: const Size(double.infinity, 200), painter: _SinglePathPainter(ticks: m.ticks)),
        ),
        const SizedBox(height: 6),
        Container(
          height: 70,
          decoration: BoxDecoration(color: BiobaseColors.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: BiobaseColors.border)),
          child: CustomPaint(size: const Size(double.infinity, 70), painter: _SpeedPainter(ticks: m.ticks)),
        ),
      ],
      const SizedBox(height: 14),
      Row(children: [
        const Text('ATTEMPTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: BiobaseColors.accent)),
        const SizedBox(width: 6),
        Text('${_attempts.length}', style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
        const Spacer(),
        _PillBtn(label: 'ATTEMPT', icon: Icons.play_arrow, color: BiobaseColors.warning, onTap: widget.live ? () => _beginCapture(attempt: true) : null),
      ]),
      const SizedBox(height: 8),
      if (_attempts.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: BiobaseColors.surface, borderRadius: BorderRadius.circular(4)),
          child: const Center(child: Text('No attempts yet', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary))),
        )
      else
        for (final a in _attempts)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: GestureDetector(
            onTap: () async {
              setState(() => _loading = true);
              try {
                final full = await _shadow.getAttempt(a.id);
                if (mounted) setState(() { _selectedAttempt = full; _view = _View.attemptResult; _loading = false; });
              } catch (e) {
                if (mounted) setState(() { _error = e.toString(); _loading = false; });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: BiobaseColors.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: BiobaseColors.borderSubtle)),
              child: Row(children: [
                Text(a.scoreOverall.toStringAsFixed(0), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w300, color: _scoreClr(a.scoreOverall))),
                const SizedBox(width: 12),
                Expanded(child: Row(children: [
                  _MiniSc('PATH', a.scorePath), const SizedBox(width: 8),
                  _MiniSc('SPD', a.scoreSpeed), const SizedBox(width: 8),
                  _MiniSc('TIME', a.scoreTiming),
                ])),
                const Icon(Icons.chevron_right, size: 14, color: BiobaseColors.textTertiary),
              ]),
            ),
          )),
      const SizedBox(height: 16),
    ]);
  }

  // ── Attempt Result ──

  Widget _buildAttemptResult() {
    final a = _selectedAttempt;
    if (a == null) return const SizedBox.shrink();
    return ListView(padding: EdgeInsets.zero, children: [
      Row(children: [
        GestureDetector(onTap: _back, child: const Icon(Icons.arrow_back, size: 16, color: BiobaseColors.textSecondary)),
        const SizedBox(width: 8),
        const Text('ATTEMPT RESULT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: BiobaseColors.accent)),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _ScoreBox(label: 'OVERALL', score: a.scoreOverall, big: true)),
        const SizedBox(width: 6),
        Expanded(child: _ScoreBox(label: 'PATH', score: a.scorePath)),
        const SizedBox(width: 6),
        Expanded(child: _ScoreBox(label: 'SPEED', score: a.scoreSpeed)),
        const SizedBox(width: 6),
        Expanded(child: _ScoreBox(label: 'TIMING', score: a.scoreTiming)),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Container(width: 10, height: 2, color: BiobaseColors.accent),
        const SizedBox(width: 4),
        const Text('Reference', style: TextStyle(fontSize: 9, color: BiobaseColors.accent)),
        const SizedBox(width: 14),
        Container(width: 10, height: 2, color: BiobaseColors.warning),
        const SizedBox(width: 4),
        const Text('Your attempt', style: TextStyle(fontSize: 9, color: BiobaseColors.warning)),
      ]),
      const SizedBox(height: 6),
      if (a.refTicks.isNotEmpty || a.ticks.isNotEmpty) ...[
        Container(
          height: 220,
          decoration: BoxDecoration(color: BiobaseColors.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: BiobaseColors.border)),
          child: CustomPaint(size: const Size(double.infinity, 220), painter: _CompPathPainter(ref: a.refTicks, attempt: a.ticks)),
        ),
        const SizedBox(height: 6),
        Container(
          height: 90,
          decoration: BoxDecoration(color: BiobaseColors.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: BiobaseColors.border)),
          child: CustomPaint(size: const Size(double.infinity, 90), painter: _SpeedCompPainter(ref: a.refTicks, attempt: a.ticks)),
        ),
      ],
      const SizedBox(height: 16),
    ]);
  }

  static String _fmtTime(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

// ── Small widgets ──

Color _scoreClr(double s) => s >= 80 ? BiobaseColors.live : s >= 60 ? BiobaseColors.accent : s >= 40 ? BiobaseColors.warning : BiobaseColors.error;
Color _diffColor(String d) => d == 'easy' ? BiobaseColors.live : d == 'hard' ? BiobaseColors.error : BiobaseColors.warning;

class _PillBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _PillBtn({required this.label, required this.icon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: enabled ? color.withAlpha(30) : BiobaseColors.surfaceRaised,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: enabled ? color.withAlpha(80) : BiobaseColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 8, color: enabled ? color : BiobaseColors.textTertiary),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: enabled ? color : BiobaseColors.textTertiary)),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Chip(this.text, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: BiobaseColors.surfaceRaised, borderRadius: BorderRadius.circular(3)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: BiobaseColors.textTertiary),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 10, color: BiobaseColors.textSecondary)),
    ]),
  );
}

class _ScoreBox extends StatelessWidget {
  final String label;
  final double score;
  final bool big;
  const _ScoreBox({required this.label, required this.score, this.big = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(vertical: big ? 14 : 8, horizontal: 6),
    decoration: BoxDecoration(
      color: BiobaseColors.surface,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: _scoreClr(score).withAlpha(50)),
    ),
    child: Column(children: [
      Text(score.toStringAsFixed(0), style: TextStyle(fontSize: big ? 28 : 18, fontWeight: FontWeight.w300, color: _scoreClr(score))),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: BiobaseColors.textTertiary)),
    ]),
  );
}

class _MiniSc extends StatelessWidget {
  final String label;
  final double val;
  const _MiniSc(this.label, this.val);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text(label, style: const TextStyle(fontSize: 9, color: BiobaseColors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
    const SizedBox(width: 3),
    Text(val.toStringAsFixed(0), style: TextStyle(fontSize: 11, color: _scoreClr(val))),
  ]);
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: 20 + _c.value * 10,
      height: 20 + _c.value * 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: BiobaseColors.error.withAlpha((200 - _c.value * 80).toInt())),
    ),
  );
}

// ── Path painters ──

class _Bounds {
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;

  void add(double x, double y) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  double get dx => maxX - minX;
  double get dy => maxY - minY;
  bool get valid => dx > 0.5 || dy > 0.5;

  Offset map(double x, double y, double scale, double ox, double oy) => Offset(ox + (x - minX) * scale, oy + (y - minY) * scale);

  (double scale, double ox, double oy) fit(double w, double h, double pad) {
    final fw = w - pad * 2;
    final fh = h - pad * 2;
    final sx = fw / (dx == 0 ? 1 : dx);
    final sy = fh / (dy == 0 ? 1 : dy);
    final s = math.min(sx, sy);
    return (s, pad + (fw - dx * s) / 2, pad + (fh - dy * s) / 2);
  }
}

void _drawPathLine(Canvas c, List<ShadowTick> ticks, Color color, double width, _Bounds b, double scale, double ox, double oy) {
  if (ticks.length < 2) return;
  final path = Path()..moveTo(b.map(ticks.first.x, ticks.first.y, scale, ox, oy).dx, b.map(ticks.first.x, ticks.first.y, scale, ox, oy).dy);
  for (var i = 1; i < ticks.length; i++) {
    final p = b.map(ticks[i].x, ticks[i].y, scale, ox, oy);
    path.lineTo(p.dx, p.dy);
  }
  c.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = width..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
}

class _SinglePathPainter extends CustomPainter {
  final List<ShadowTick> ticks;
  const _SinglePathPainter({required this.ticks});

  @override
  void paint(Canvas canvas, Size size) {
    if (ticks.length < 2) return;
    final b = _Bounds();
    for (final t in ticks) b.add(t.x, t.y);
    if (!b.valid) return;
    final (scale, ox, oy) = b.fit(size.width, size.height, 16);
    _drawPathLine(canvas, ticks, BiobaseColors.accent, 2, b, scale, ox, oy);
    final start = b.map(ticks.first.x, ticks.first.y, scale, ox, oy);
    final end = b.map(ticks.last.x, ticks.last.y, scale, ox, oy);
    canvas.drawCircle(start, 4, Paint()..color = BiobaseColors.live);
    canvas.drawRect(Rect.fromCenter(center: end, width: 6, height: 6), Paint()..color = BiobaseColors.error);
  }

  @override
  bool shouldRepaint(covariant _SinglePathPainter old) => ticks.length != old.ticks.length;
}

class _CompPathPainter extends CustomPainter {
  final List<ShadowTick> ref;
  final List<ShadowTick> attempt;
  const _CompPathPainter({required this.ref, required this.attempt});

  @override
  void paint(Canvas canvas, Size size) {
    final b = _Bounds();
    for (final t in ref) b.add(t.x, t.y);
    for (final t in attempt) b.add(t.x, t.y);
    if (!b.valid) return;
    final (scale, ox, oy) = b.fit(size.width, size.height, 16);
    _drawPathLine(canvas, ref, BiobaseColors.accent, 2, b, scale, ox, oy);
    _drawPathLine(canvas, attempt, BiobaseColors.warning, 2, b, scale, ox, oy);
    if (ref.isNotEmpty) {
      canvas.drawCircle(b.map(ref.first.x, ref.first.y, scale, ox, oy), 3, Paint()..color = BiobaseColors.live);
    }
  }

  @override
  bool shouldRepaint(covariant _CompPathPainter old) => ref.length != old.ref.length || attempt.length != old.attempt.length;
}

class _SpeedPainter extends CustomPainter {
  final List<ShadowTick> ticks;
  const _SpeedPainter({required this.ticks});

  @override
  void paint(Canvas canvas, Size size) {
    if (ticks.length < 2) return;
    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    double maxS = 0;
    for (final t in ticks) { if (t.speed > maxS) maxS = t.speed; }
    if (maxS < 1) return;
    final path = Path();
    for (var i = 0; i < ticks.length; i++) {
      final x = pad + (i / (ticks.length - 1)) * w;
      final y = pad + h - (ticks[i].speed / maxS) * h;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = BiobaseColors.accent..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(pad, pad + h - (250 / maxS).clamp(0, 1) * h), Offset(pad + w, pad + h - (250 / maxS).clamp(0, 1) * h),
      Paint()..color = BiobaseColors.live.withAlpha(40)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _SpeedPainter old) => ticks.length != old.ticks.length;
}

class _SpeedCompPainter extends CustomPainter {
  final List<ShadowTick> ref;
  final List<ShadowTick> attempt;
  const _SpeedCompPainter({required this.ref, required this.attempt});

  @override
  void paint(Canvas canvas, Size size) {
    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    double maxS = 0;
    for (final t in ref) { if (t.speed > maxS) maxS = t.speed; }
    for (final t in attempt) { if (t.speed > maxS) maxS = t.speed; }
    if (maxS < 1) return;

    void drawLine(List<ShadowTick> data, Color color) {
      if (data.length < 2) return;
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final x = pad + (i / (data.length - 1)) * w;
        final y = pad + h - (data[i].speed / maxS) * h;
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round);
    }

    drawLine(ref, BiobaseColors.accent);
    drawLine(attempt, BiobaseColors.warning);
  }

  @override
  bool shouldRepaint(covariant _SpeedCompPainter old) => ref.length != old.ref.length || attempt.length != old.attempt.length;
}
