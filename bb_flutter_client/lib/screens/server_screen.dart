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
  GameStatus? _gameStatus;
  ServerCapabilities? _caps;
  final List<InstallProgress> _log = [];
  String? _errorMessage;
  bool _actionBusy = false;
  Timer? _pollTimer;

  final _rconController = TextEditingController();
  final _rconFocus = FocusNode();
  final List<(String, String)> _rconHistory = [];

  @override
  void initState() {
    super.initState();
    _checkState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _rconController.dispose();
    _rconFocus.dispose();
    super.dispose();
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
      if (run == ServerRunState.running || run == ServerRunState.partial) {
        await _refreshGameState();
        _startPolling();
      } else {
        _stopPolling();
        if (mounted) setState(() { _gameStatus = null; _caps = null; });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_runState == ServerRunState.running) _refreshGameState();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _refreshGameState() async {
    final caps = await _server.fetchCapabilities(_info);
    final status = await _server.fetchGameStatus(_info);
    if (mounted) setState(() { _caps = caps; _gameStatus = status; });
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
          setState(() { _errorMessage = progress.message; });
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

  Future<void> _doAction(Future<void> Function() action) async {
    setState(() => _actionBusy = true);
    await action();
    await _checkState();
    if (mounted) setState(() => _actionBusy = false);
  }

  Future<void> _toggleCheats() async {
    final current = _caps?.cheatsState ?? 'unknown';
    final enable = current != 'on';
    setState(() => _actionBusy = true);
    await _server.setCheats(_info, enable);
    await _refreshGameState();
    if (mounted) setState(() => _actionBusy = false);
  }

  Future<void> _sendRcon() async {
    final cmd = _rconController.text.trim();
    if (cmd.isEmpty) return;
    _rconController.clear();
    final (ok, output) = await _server.sendRcon(_info, cmd);
    if (mounted) {
      setState(() {
        _rconHistory.add((cmd, ok ? output : 'ERROR: $output'));
      });
    }
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
            Icon(Icons.dns_outlined, size: 40, color: BiobaseColors.textTertiary),
            const SizedBox(height: 16),
            const Text('Run your own CS2 server',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
            const SizedBox(height: 8),
            const Text('Zero-lag practice on your local network. Server installs and runs automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: BiobaseColors.textTertiary, height: 1.5)),
            const SizedBox(height: 24),
            _ActionButton(label: 'Install Server', onTap: _startInstall, primary: true),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: BiobaseColors.accent)),
          SizedBox(height: 16),
          Text('Downloading server installer...',
            style: TextStyle(fontSize: 13, color: BiobaseColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildInstalling() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: BiobaseColors.accent)),
            const SizedBox(width: 10),
            const Text('Installing server',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
          ]),
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

  Widget _buildError() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: BiobaseColors.error),
            const SizedBox(height: 12),
            const Text('Installation failed',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: BiobaseColors.textTertiary)),
            ],
            const SizedBox(height: 20),
            _ActionButton(label: 'Retry', onTap: _startInstall, primary: true),
          ],
        ),
      ),
    );
  }

  // ── Full management dashboard ──

  Widget _buildManagement() {
    final info = _info;
    final isRunning = _runState == ServerRunState.running;
    final isPartial = _runState == ServerRunState.partial;
    final isUp = isRunning || isPartial;
    final cheatsOn = _caps?.cheatsState == 'on';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: status + controls ──
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning ? BiobaseColors.live
                      : isPartial ? BiobaseColors.warning
                      : BiobaseColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isRunning ? 'Running' : isPartial ? 'Degraded' : 'Stopped',
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: isRunning ? BiobaseColors.live
                      : isPartial ? BiobaseColors.warning
                      : BiobaseColors.textTertiary,
                ),
              ),
              if (_gameStatus?.map != null) ...[
                const SizedBox(width: 10),
                Text(_gameStatus!.map!,
                  style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
              ],
              if (_gameStatus != null && _gameStatus!.rconOk) ...[
                const SizedBox(width: 10),
                Text('${_gameStatus!.humans}h ${_gameStatus!.bots}b',
                  style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
              ],
              const Spacer(),
              if (_actionBusy)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: BiobaseColors.textTertiary)),
                ),
              _ActionButton(
                label: 'Refresh',
                icon: Icons.refresh,
                onTap: _actionBusy ? null : () => _doAction(() async {}),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Service controls ──
          Row(
            children: [
              if (!isRunning)
                _ActionButton(label: 'Start', onTap: _actionBusy ? null : () => _doAction(_server.start), primary: true),
              if (isUp) ...[
                _ActionButton(label: 'Stop', onTap: _actionBusy ? null : () => _doAction(_server.stop)),
                const SizedBox(width: 8),
                _ActionButton(label: 'Restart', onTap: _actionBusy ? null : () => _doAction(_server.restart)),
              ],
              if (isUp) ...[
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'Connect',
                  icon: Icons.play_arrow,
                  onTap: () => _server.connectToGame(_info),
                  primary: true,
                ),
              ],
            ],
          ),

          if (isUp) ...[
            const SizedBox(height: 20),
            _SectionLabel('GAME CONTROLS'),
            const SizedBox(height: 8),
            _buildGameControls(info, cheatsOn),

            if (_gameStatus != null && _gameStatus!.players.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionLabel('PLAYERS'),
              const SizedBox(height: 8),
              _buildPlayerList(),
            ],

            if (_caps != null && _caps!.plugins.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionLabel('PLUGINS'),
              const SizedBox(height: 8),
              _buildPlugins(),
            ],

            const SizedBox(height: 20),
            _SectionLabel('RCON'),
            const SizedBox(height: 8),
            _buildRconConsole(),
          ],

          const SizedBox(height: 20),
          _SectionLabel('SERVER INFO'),
          const SizedBox(height: 8),
          _buildServerInfo(info),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildGameControls(ServerInfo? info, bool cheatsOn) {
    return _Panel(
      child: Column(
        children: [
          // Map change
          _ControlRow(
            label: 'Map',
            child: _MapSelector(
              currentMap: _gameStatus?.map,
              onMapSelected: (map) async {
                setState(() => _actionBusy = true);
                await _server.changeMap(info, map);
                await Future.delayed(const Duration(seconds: 2));
                await _refreshGameState();
                if (mounted) setState(() => _actionBusy = false);
              },
            ),
          ),
          const _Divider(),
          // Cheats toggle
          _ControlRow(
            label: 'sv_cheats',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(cheatsOn ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: cheatsOn ? BiobaseColors.live : BiobaseColors.textTertiary,
                  )),
                const SizedBox(width: 8),
                _SmallButton(
                  label: cheatsOn ? 'Disable' : 'Enable',
                  onTap: _actionBusy ? null : _toggleCheats,
                ),
              ],
            ),
          ),
          const _Divider(),
          // Bot controls
          _ControlRow(
            label: 'Bots',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmallButton(
                  label: 'Start bots',
                  onTap: _actionBusy ? null : () async {
                    setState(() => _actionBusy = true);
                    await _server.startBots(info);
                    await _refreshGameState();
                    if (mounted) setState(() => _actionBusy = false);
                  },
                ),
                const SizedBox(width: 6),
                _SmallButton(
                  label: 'Kick bots',
                  onTap: _actionBusy ? null : () async {
                    setState(() => _actionBusy = true);
                    await _server.stopBots(info);
                    await _refreshGameState();
                    if (mounted) setState(() => _actionBusy = false);
                  },
                ),
              ],
            ),
          ),
          const _Divider(),
          // Quick exec
          _ControlRow(
            label: 'Config',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmallButton(
                  label: 'Practice mode',
                  onTap: _actionBusy ? null : () async {
                    setState(() => _actionBusy = true);
                    await _server.sendRcon(info, 'exec biobase_dev');
                    await _refreshGameState();
                    if (mounted) setState(() => _actionBusy = false);
                  },
                ),
                const SizedBox(width: 6),
                _SmallButton(
                  label: 'Match mode',
                  onTap: _actionBusy ? null : () async {
                    setState(() => _actionBusy = true);
                    await _server.sendRcon(info, 'exec biobase_play');
                    await _refreshGameState();
                    if (mounted) setState(() => _actionBusy = false);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerList() {
    final players = _gameStatus?.players ?? [];
    final humans = players.where((p) => !p.isBot).toList();
    final bots = players.where((p) => p.isBot).toList();

    return _Panel(
      child: Column(
        children: [
          for (var i = 0; i < humans.length; i++) ...[
            if (i > 0) const _Divider(),
            _PlayerRow(player: humans[i]),
          ],
          if (bots.isNotEmpty) ...[
            if (humans.isNotEmpty) const _Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 100,
                    child: Text('Bots', style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary))),
                  Text('${bots.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: BiobaseColors.textSecondary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _toggleablePlugins = {'matchzy': 'MatchZy', 'kz': 'CS2KZ', 'biobase_pos': 'BiobasePosEmitter'};

  Future<void> _togglePlugin(String cssName, bool currentlyEnabled) async {
    setState(() => _actionBusy = true);
    final cmd = currentlyEnabled ? 'css_plugins unload $cssName' : 'css_plugins load $cssName';
    await _server.sendRcon(_info, cmd);
    await Future.delayed(const Duration(seconds: 1));
    await _refreshGameState();
    if (mounted) setState(() => _actionBusy = false);
  }

  Widget _buildPlugins() {
    final plugins = _caps?.plugins ?? {};
    return _Panel(
      child: Column(
        children: [
          for (var i = 0; i < plugins.length; i++) ...[
            if (i > 0) const _Divider(),
            _ControlRow(
              label: plugins.keys.elementAt(i),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PluginBadge(state: plugins.values.elementAt(i)),
                  if (_toggleablePlugins.containsKey(plugins.keys.elementAt(i))) ...[
                    const SizedBox(width: 8),
                    _SmallButton(
                      label: plugins.values.elementAt(i) == 'enabled' ? 'Unload' : 'Load',
                      onTap: _actionBusy ? null : () => _togglePlugin(
                        _toggleablePlugins[plugins.keys.elementAt(i)]!,
                        plugins.values.elementAt(i) == 'enabled',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRconConsole() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_rconHistory.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _rconHistory.length,
                itemBuilder: (_, i) {
                  final (cmd, output) = _rconHistory[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('> $cmd', style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace',
                          fontWeight: FontWeight.w600, color: BiobaseColors.accent)),
                        if (output.isNotEmpty)
                          Text(output, style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace', color: BiobaseColors.textSecondary)),
                      ],
                    ),
                  );
                },
              ),
            ),
          Row(
            children: [
              const Text('>', style: TextStyle(
                fontSize: 11, fontFamily: 'monospace', color: BiobaseColors.accent)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _rconController,
                  focusNode: _rconFocus,
                  style: const TextStyle(
                    fontSize: 11, fontFamily: 'monospace', color: BiobaseColors.text),
                  decoration: const InputDecoration(
                    hintText: 'sv_cheats 1, status, changelevel de_dust2 ...',
                    hintStyle: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  onSubmitted: (_) => _sendRcon(),
                ),
              ),
              _SmallButton(label: 'Send', onTap: _sendRcon),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServerInfo(ServerInfo? info) {
    if (info == null) return const SizedBox.shrink();
    return _Panel(
      child: Column(
        children: [
          _InfoRow('Server', info.serverName),
          const _Divider(),
          _InfoRow('Game port', 'localhost:${info.gamePort}', copyable: true),
          const _Divider(),
          _InfoRow('Max players', '${info.maxPlayers}'),
          const _Divider(),
          _InfoRow('RCON password', info.rconPassword, copyable: true),
          const _Divider(),
          _InfoRow('Dashboard', 'localhost:${info.dashboardPort}/admin', copyable: true),
          const _Divider(),
          _InfoRow('Dashboard pass', info.dashboardPassword, copyable: true),
          const _Divider(),
          _InfoRow('Install dir', info.installDir),
        ],
      ),
    );
  }
}

// ── Map selector ──

class _MapSelector extends StatefulWidget {
  final String? currentMap;
  final ValueChanged<String> onMapSelected;

  const _MapSelector({this.currentMap, required this.onMapSelected});

  @override
  State<_MapSelector> createState() => _MapSelectorState();
}

class _MapSelectorState extends State<_MapSelector> {
  bool _expanded = false;
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.currentMap ?? '—',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: BiobaseColors.text)),
          const SizedBox(width: 8),
          _SmallButton(label: 'Change', onTap: () => setState(() => _expanded = true)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final map in stockMaps)
              _MapChip(
                name: map,
                active: map == widget.currentMap,
                onTap: () {
                  widget.onMapSelected(map);
                  setState(() => _expanded = false);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: _customController,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: BiobaseColors.text),
                decoration: const InputDecoration(
                  hintText: 'workshop id...',
                  hintStyle: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    widget.onMapSelected(v.trim());
                    _customController.clear();
                    setState(() => _expanded = false);
                  }
                },
              ),
            ),
            _SmallButton(
              label: 'Cancel',
              onTap: () => setState(() => _expanded = false),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Reusable widgets ──

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(
      fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: BiobaseColors.textTertiary));
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BiobaseColors.border),
      ),
      child: child,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: BiobaseColors.borderSubtle,
    );
  }
}

class _ControlRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _ControlRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 100,
            child: Text(label, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary))),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final ServerPlayer player;
  const _PlayerRow({required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(player.name, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: BiobaseColors.text))),
          if (player.connected != null)
            Text(player.connected!, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
          const SizedBox(width: 12),
          Text('${player.ping}ms', style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
        ],
      ),
    );
  }
}

class _PluginBadge extends StatelessWidget {
  final String state;
  const _PluginBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'enabled' => BiobaseColors.live,
      'disabled' => BiobaseColors.textTertiary,
      _ => BiobaseColors.warning,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(state, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

class _MapChip extends StatefulWidget {
  final String name;
  final bool active;
  final VoidCallback onTap;
  const _MapChip({required this.name, required this.active, required this.onTap});

  @override
  State<_MapChip> createState() => _MapChipState();
}

class _MapChipState extends State<_MapChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: widget.active ? BiobaseColors.accentDim
                : _hovered ? BiobaseColors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: widget.active ? BiobaseColors.accent : BiobaseColors.border),
          ),
          child: Text(widget.name, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w500,
            color: widget.active ? BiobaseColors.accent : BiobaseColors.textSecondary)),
        ),
      ),
    );
  }
}

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
            child: Text(entry.message, style: TextStyle(
              fontSize: 11, fontFamily: 'monospace', color: color)),
          ),
        ],
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
          SizedBox(width: 120,
            child: Text(label, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary))),
          Expanded(
            child: Text(value, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: BiobaseColors.text))),
          if (copyable)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: value)),
                child: const Icon(Icons.copy, size: 12, color: BiobaseColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _SmallButton({required this.label, this.onTap});

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered ? BiobaseColors.surfaceHover : BiobaseColors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: BiobaseColors.border),
          ),
          child: Text(widget.label, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w500,
            color: disabled ? BiobaseColors.textTertiary : BiobaseColors.textSecondary)),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  const _ActionButton({required this.label, this.icon, this.onTap, this.primary = false});

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
                : (_hovered ? BiobaseColors.surfaceHover : BiobaseColors.surface),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.primary ? BiobaseColors.accent : BiobaseColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 12,
                  color: disabled ? BiobaseColors.textTertiary
                      : widget.primary ? BiobaseColors.text : BiobaseColors.textSecondary),
                const SizedBox(width: 6),
              ],
              Text(widget.label, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: disabled ? BiobaseColors.textTertiary
                    : widget.primary ? BiobaseColors.text : BiobaseColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
