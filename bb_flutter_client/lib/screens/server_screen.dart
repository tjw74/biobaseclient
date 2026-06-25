import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/server_service.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final ServerService _server = ServerService();

  ServerInstallState _installState = ServerInstallState.notInstalled;
  ServerRunState _runState = ServerRunState.unknown;
  ServerInfo? _info;
  final List<InstallProgress> _log = [];
  String? _errorMessage;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _checkState();
  }

  Future<void> _checkState() async {
    if (_server.isInstalled) {
      final info = _server.readServerInfo();
      final run = await _server.getRunState();
      if (mounted) {
        setState(() {
          _installState = ServerInstallState.installed;
          _info = info;
          _runState = run;
        });
      }
    }
  }

  Future<void> _startInstall() async {
    setState(() {
      _installState = ServerInstallState.installing;
      _log.clear();
      _errorMessage = null;
    });

    try {
      if (!_server.installerReady) {
        setState(() => _installState = ServerInstallState.downloading);
        await _server.downloadInstaller(onProgress: (received, total) {
          if (mounted) setState(() {});
        });
        if (mounted) setState(() => _installState = ServerInstallState.installing);
      }

      await for (final progress in _server.install()) {
        if (!mounted) return;
        setState(() => _log.add(progress));

        if (progress.status == 'error') {
          setState(() {
            _installState = ServerInstallState.error;
            _errorMessage = progress.message;
          });
          return;
        }

        if (progress.id == 'complete') {
          setState(() => _installState = ServerInstallState.installed);
          await _checkState();
          return;
        }

        if (progress.id == 'restart_required') {
          setState(() {
            _errorMessage = progress.message;
          });
          return;
        }
      }

      await _checkState();
    } catch (e) {
      if (mounted) {
        setState(() {
          _installState = ServerInstallState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _startServer() async {
    setState(() => _actionBusy = true);
    await _server.start();
    await _checkState();
    if (mounted) setState(() => _actionBusy = false);
  }

  Future<void> _stopServer() async {
    setState(() => _actionBusy = true);
    await _server.stop();
    await _checkState();
    if (mounted) setState(() => _actionBusy = false);
  }

  Future<void> _restartServer() async {
    setState(() => _actionBusy = true);
    await _server.restart();
    await _checkState();
    if (mounted) setState(() => _actionBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_installState) {
      ServerInstallState.notInstalled => _buildPreInstall(),
      ServerInstallState.downloading => _buildDownloading(),
      ServerInstallState.installing => _buildInstalling(),
      ServerInstallState.installed => _buildManagement(),
      ServerInstallState.error => _buildError(),
    };
  }

  // ── Pre-install ──

  Widget _buildPreInstall() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 40,
              color: BiobaseColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Run your own CS2 server',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Zero-lag practice on your local network. '
              'Server installs and runs automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: BiobaseColors.textTertiary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _ActionButton(
              label: 'Install Server',
              onTap: _startInstall,
              primary: true,
            ),
          ],
        ),
      ),
    );
  }

  // ── Downloading ──

  Widget _buildDownloading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: BiobaseColors.accent,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Downloading server installer...',
            style: TextStyle(
              fontSize: 13,
              color: BiobaseColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Installing ──

  Widget _buildInstalling() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: BiobaseColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Installing server',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BiobaseColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: BiobaseColors.border),
              ),
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (_, i) => _LogLine(entry: _log[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error ──

  Widget _buildError() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 36,
              color: BiobaseColors.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'Installation failed',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.text,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: BiobaseColors.textTertiary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _ActionButton(
              label: 'Retry',
              onTap: _startInstall,
              primary: true,
            ),
          ],
        ),
      ),
    );
  }

  // ── Management ──

  Widget _buildManagement() {
    final info = _info;
    final isRunning = _runState == ServerRunState.running;
    final isPartial = _runState == ServerRunState.partial;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning
                      ? BiobaseColors.live
                      : isPartial
                          ? BiobaseColors.warning
                          : BiobaseColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isRunning
                    ? 'Running'
                    : isPartial
                        ? 'Partially running'
                        : 'Stopped',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isRunning
                      ? BiobaseColors.live
                      : isPartial
                          ? BiobaseColors.warning
                          : BiobaseColors.textTertiary,
                ),
              ),
              const Spacer(),
              if (_actionBusy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: BiobaseColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Server info
          if (info != null) ...[
            _InfoSection(children: [
              _InfoRow('Server', info.serverName),
              _InfoRow('Game port', 'localhost:${info.gamePort}'),
              _InfoRow('Map', info.map),
              _InfoRow('Max players', '${info.maxPlayers}'),
            ]),
            const SizedBox(height: 12),
            _InfoSection(children: [
              _InfoRow('RCON password', info.rconPassword, copyable: true),
              _InfoRow(
                'Dashboard',
                'localhost:${info.dashboardPort}/admin',
                copyable: true,
              ),
              _InfoRow('Dashboard password', info.dashboardPassword,
                  copyable: true),
            ]),
            const SizedBox(height: 12),
            _InfoSection(children: [
              _InfoRow('Install dir', info.installDir),
            ]),
          ],

          const SizedBox(height: 20),

          // Controls
          Row(
            children: [
              if (!isRunning)
                _ActionButton(
                  label: 'Start',
                  onTap: _actionBusy ? null : _startServer,
                  primary: true,
                ),
              if (isRunning || isPartial) ...[
                _ActionButton(
                  label: 'Stop',
                  onTap: _actionBusy ? null : _stopServer,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'Restart',
                  onTap: _actionBusy ? null : _restartServer,
                ),
              ],
              const Spacer(),
              _ActionButton(
                label: 'Refresh',
                icon: Icons.refresh,
                onTap: _actionBusy ? null : _checkState,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──

class _LogLine extends StatelessWidget {
  final InstallProgress entry;
  const _LogLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final icon = switch (entry.status) {
      'start' => Icons.arrow_forward,
      'done' => Icons.check,
      'error' => Icons.close,
      _ => Icons.info_outline,
    };
    final color = switch (entry.status) {
      'done' => BiobaseColors.live,
      'error' => BiobaseColors.error,
      'start' => BiobaseColors.accent,
      _ => BiobaseColors.textTertiary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final List<Widget> children;
  const _InfoSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BiobaseColors.border),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _InfoRow(this.label, this.value, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: BiobaseColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: BiobaseColors.text,
              ),
            ),
          ),
          if (copyable)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: value)),
                child: const Icon(
                  Icons.copy,
                  size: 12,
                  color: BiobaseColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;

  const _ActionButton({
    required this.label,
    this.icon,
    this.onTap,
    this.primary = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: widget.primary
                ? (_hovered ? BiobaseColors.accent : BiobaseColors.accentDim)
                : (_hovered
                    ? BiobaseColors.surfaceHover
                    : BiobaseColors.surface),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.primary
                  ? BiobaseColors.accent
                  : BiobaseColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 12,
                  color: disabled
                      ? BiobaseColors.textTertiary
                      : widget.primary
                          ? BiobaseColors.text
                          : BiobaseColors.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: disabled
                      ? BiobaseColors.textTertiary
                      : widget.primary
                          ? BiobaseColors.text
                          : BiobaseColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
