import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme.dart';

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  String? _demoPath;
  String? _demoName;
  int? _demoSize;
  double _playbackPosition = 0;
  double _playbackSpeed = 1.0;
  bool _playing = false;

  Future<void> _pickDemo() async {
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
        // Left: controls + stats
        SizedBox(
          width: 320,
          child: _StatsPanel(
            demoPath: _demoPath,
            demoName: _demoName,
            demoSize: _demoSize,
            position: _playbackPosition,
            speed: _playbackSpeed,
            playing: _playing,
            onPickDemo: _pickDemo,
            onPlay: () => setState(() => _playing = !_playing),
            onPositionChanged: (v) => setState(() => _playbackPosition = v),
            onSpeedChanged: (v) => setState(() => _playbackSpeed = v),
          ),
        ),
        const SizedBox(width: 12),
        // Right: demo render area
        Expanded(child: _RenderArea(demoPath: _demoPath, demoName: _demoName)),
      ],
    );
  }
}

// ── Stats Panel (left) ──

class _StatsPanel extends StatelessWidget {
  final String? demoPath;
  final String? demoName;
  final int? demoSize;
  final double position;
  final double speed;
  final bool playing;
  final VoidCallback onPickDemo;
  final VoidCallback onPlay;
  final ValueChanged<double> onPositionChanged;
  final ValueChanged<double> onSpeedChanged;

  const _StatsPanel({
    required this.demoPath,
    required this.demoName,
    required this.demoSize,
    required this.position,
    required this.speed,
    required this.playing,
    required this.onPickDemo,
    required this.onPlay,
    required this.onPositionChanged,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // File picker
        Container(
          decoration: BoxDecoration(
            color: BiobaseColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BiobaseColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Demo File', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
              const SizedBox(height: 8),
              if (demoName != null) ...[
                Text(demoName!, style: const TextStyle(fontSize: 11, color: BiobaseColors.text), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_formatSize(demoSize ?? 0), style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onPickDemo,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: BiobaseColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(demoPath == null ? 'Open .dem File' : 'Change File',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Playback controls
        Container(
          decoration: BoxDecoration(
            color: BiobaseColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BiobaseColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Playback', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
              const SizedBox(height: 10),
              // Timeline
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
                  value: position,
                  onChanged: demoPath != null ? onPositionChanged : null,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(_formatTime(position), style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: BiobaseColors.textTertiary)),
                  const Spacer(),
                  Text(_formatTime(1.0), style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: BiobaseColors.textTertiary)),
                ],
              ),
              const SizedBox(height: 10),
              // Controls row
              Row(
                children: [
                  _controlBtn(Icons.skip_previous, () => onPositionChanged(0)),
                  const SizedBox(width: 4),
                  _controlBtn(playing ? Icons.pause : Icons.play_arrow, onPlay, primary: true),
                  const SizedBox(width: 4),
                  _controlBtn(Icons.skip_next, () => onPositionChanged(1)),
                  const Spacer(),
                  // Speed selector
                  ...([0.25, 0.5, 1.0, 2.0].map((s) => Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: _speedBtn(s, speed == s, () => onSpeedChanged(s)),
                  ))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Round stats
        Container(
          decoration: BoxDecoration(
            color: BiobaseColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BiobaseColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Round Stats', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
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
        ),
        const SizedBox(height: 8),
        // Events log
        Container(
          decoration: BoxDecoration(
            color: BiobaseColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BiobaseColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Events', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
              const SizedBox(height: 10),
              if (demoPath == null)
                const Text('Load a demo to see events', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary))
              else
                const Text('Demo parsing in progress', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BiobaseColors.text, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback onTap, {bool primary = false}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: demoPath != null ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primary ? BiobaseColors.accent : BiobaseColors.surfaceRaised,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: demoPath != null ? Colors.white : BiobaseColors.textTertiary),
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
          child: Text('${s}x', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
            color: active ? BiobaseColors.accent : BiobaseColors.textTertiary)),
        ),
      ),
    );
  }

  String _formatTime(double t) {
    final mins = (t * 45).toInt();
    final secs = ((t * 45 * 60) % 60).toInt();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
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
          Icon(Icons.videocam_outlined, size: 48, color: BiobaseColors.textTertiary.withAlpha(80)),
          const SizedBox(height: 12),
          const Text('No demo loaded', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BiobaseColors.textTertiary)),
          const SizedBox(height: 4),
          const Text('Open a .dem file to start replay', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
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
              Icon(Icons.play_circle_outline, size: 64, color: BiobaseColors.accent.withAlpha(60)),
              const SizedBox(height: 12),
              Text(demoName ?? '', style: const TextStyle(fontSize: 12, color: BiobaseColors.textSecondary)),
              const SizedBox(height: 4),
              const Text('Demo render engine loading', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
            ],
          ),
        ),
        // Minimap placeholder (top-right)
        Positioned(
          top: 12, right: 12,
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              color: BiobaseColors.bg.withAlpha(180),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: BiobaseColors.border),
            ),
            child: const Center(
              child: Text('Minimap', style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary)),
            ),
          ),
        ),
        // Round indicator (top-left)
        Positioned(
          top: 12, left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: BiobaseColors.bg.withAlpha(180),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Round 1 / —', style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
          ),
        ),
      ],
    );
  }
}
