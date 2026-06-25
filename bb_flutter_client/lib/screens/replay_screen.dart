import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme.dart';
import '../services/server_service.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  final ServerService _server = ServerService();

  List<DemoFile>? _demos;
  bool _loading = true;
  String? _demoPath;
  String? _demoName;
  int? _demoSize;
  double _playbackPosition = 0;
  double _playbackSpeed = 1.0;
  bool _playing = false;
  bool _copying = false;

  @override
  void initState() {
    super.initState();
    _loadDemos();
  }

  Future<void> _loadDemos() async {
    setState(() => _loading = true);
    final demos = await _server.listDemos();
    if (mounted) setState(() { _demos = demos; _loading = false; });
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
      });
    }
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
        Expanded(child: _RenderArea(demoPath: _demoPath, demoName: _demoName)),
      ],
    );
  }

  Widget _buildLeft() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Demo list
        _buildDemoList(),
        const SizedBox(height: 8),
        // Playback controls
        _buildPlayback(),
        const SizedBox(height: 8),
        // Round stats
        _buildStats(),
        const SizedBox(height: 8),
        // Events
        _buildEvents(),
      ],
    );
  }

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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    const Text('No demos recorded yet',
                        style: TextStyle(
                            fontSize: 11, color: BiobaseColors.textTertiary)),
                    const SizedBox(height: 4),
                    const Text('Play a match to generate a demo',
                        style: TextStyle(
                            fontSize: 10, color: BiobaseColors.textTertiary)),
                  ],
                ),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 12, color: BiobaseColors.textTertiary),
                  const SizedBox(width: 4),
                  const Text('Open local file',
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
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: BiobaseColors.accent,
              inactiveTrackColor: BiobaseColors.surfaceRaised,
              thumbColor: BiobaseColors.accent,
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: _playbackPosition,
              onChanged: _demoPath != null
                  ? (v) => setState(() => _playbackPosition = v)
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
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
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
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
                    child: _speedBtn(
                        s,
                        _playbackSpeed == s,
                        () => setState(() => _playbackSpeed = s)),
                  ))),
            ],
          ),
        ],
      ),
    );
  }

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
                        fontWeight:
                            widget.selected ? FontWeight.w600 : FontWeight.w400,
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

// ── Render Area (right) ──

class _RenderArea extends StatelessWidget {
  final String? demoPath;
  final String? demoName;

  const _RenderArea({required this.demoPath, required this.demoName});

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
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            width: 120,
            height: 120,
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
      ],
    );
  }
}
