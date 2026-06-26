import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/server_service.dart';
import '../services/settings_service.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final ServerService _server = ServerService();
  final SettingsService _settings = SettingsService();

  ServerInstallState _installState = ServerInstallState.notInstalled;
  ServerRunState _runState = ServerRunState.unknown;
  ServerInfo? _info;
  GameStatus? _gameStatus;
  ServerCapabilities? _caps;
  final List<InstallProgress> _log = [];
  String? _errorMessage;
  bool _actionBusy = false;
  Timer? _pollTimer;
  bool _settingsReady = false;

  final _rconController = TextEditingController();
  final _rconFocus = FocusNode();
  final List<(String, String)> _rconHistory = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _settings.init();
    if (mounted) setState(() => _settingsReady = true);
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

  bool _selectorOpen = false;

  String get _activeAddress => _settings.activeServerAddress;
  List<SavedServer> get _servers => _settingsReady ? _settings.savedServers : [];
  String get _localAddr => 'localhost:${_info?.gamePort ?? 27015}';
  bool get _isLocalActive => _activeAddress == _localAddr;

  Future<void> _selectServer(String address) async {
    await _settings.setActiveServer(address);
    if (mounted) setState(() => _selectorOpen = false);
  }

  Future<void> _addCustomServer(String name, String host, int port) async {
    await _settings.addServer(SavedServer(name: name, host: host, port: port));
    await _settings.setActiveServer('$host:$port');
    if (mounted) setState(() => _selectorOpen = false);
  }

  Future<void> _removeServer(SavedServer server) async {
    await _settings.removeServer(server);
    if (_activeAddress == server.address) {
      await _settings.setActiveServer('cs2.clarionlab.dev:27015');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsReady) return const SizedBox.shrink();

    final installing = _installState == ServerInstallState.downloading ||
        _installState == ServerInstallState.installing;
    if (installing) return _buildInstalling();
    if (_installState == ServerInstallState.error) return _buildError();

    final isRunning = _runState == ServerRunState.running;
    final isPartial = _runState == ServerRunState.partial;
    final isUp = isRunning || isPartial;
    final cheatsOn = _caps?.cheatsState == 'on';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildServerPanel(),

          if (isUp) ...[
            const SizedBox(height: 20),
            _SectionLabel('GAME CONTROLS'),
            const SizedBox(height: 8),
            _buildGameControls(_info, cheatsOn),

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

          if (_server.isInstalled) ...[
            const SizedBox(height: 20),
            _SectionLabel('SERVER INFO'),
            const SizedBox(height: 8),
            _buildServerInfo(_info),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Server panel ──

  Widget _buildServerPanel() {
    final servers = _servers;
    final hasLocal = _server.isInstalled;
    final isRunning = _runState == ServerRunState.running;
    final isPartial = _runState == ServerRunState.partial;
    final isUp = isRunning || isPartial;

    // Resolve active server display
    String activeName;
    if (_isLocalActive) {
      activeName = 'Local Server';
    } else {
      final match = servers.where((s) => s.address == _activeAddress);
      activeName = match.isNotEmpty ? match.first.name : _activeAddress;
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Server selector — click to expand
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectorOpen = !_selectorOpen),
                    child: Row(
                      children: [
                        Text(activeName, style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: BiobaseColors.text)),
                        const SizedBox(width: 8),
                        Text(_activeAddress, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
                        if (_isLocalActive && hasLocal) ...[
                          const SizedBox(width: 8),
                          Container(width: 6, height: 6,
                            decoration: BoxDecoration(shape: BoxShape.circle,
                              color: isUp
                                  ? (isRunning ? BiobaseColors.live : BiobaseColors.warning)
                                  : BiobaseColors.textTertiary)),
                        ],
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _selectorOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(Icons.expand_more, size: 16, color: BiobaseColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Start/Stop for local server
              if (_isLocalActive && hasLocal) ...[
                if (_actionBusy)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: BiobaseColors.textTertiary)),
                  ),
                _SmallButton(
                  label: isUp ? 'Stop' : 'Start',
                  onTap: _actionBusy ? null : () => _doAction(isUp ? _server.stop : _server.start),
                ),
                const SizedBox(width: 8),
              ],
              _ActionButton(
                label: 'Play',
                icon: Icons.sports_esports,
                onTap: () => _server.connectToServer(_activeAddress),
                primary: true,
              ),
            ],
          ),

          // Expanded server list
          if (_selectorOpen) ...[
            const SizedBox(height: 4),
            const _Divider(),
            const SizedBox(height: 2),
            for (final s in servers)
              if (s.address != _activeAddress)
                _SelectorOption(
                  name: s.name,
                  detail: s.address,
                  onTap: () => _selectServer(s.address),
                  onRemove: s.address != 'cs2.clarionlab.dev:27015'
                    ? () => _removeServer(s) : null,
                ),
            if (!_isLocalActive && hasLocal)
              _SelectorOption(
                name: 'Local Server',
                detail: isUp ? 'running' : 'stopped',
                statusColor: isUp ? BiobaseColors.live : null,
                onTap: () => _selectServer(_localAddr),
              ),
            if (!hasLocal)
              _SelectorOption(
                name: 'Local Server',
                detail: 'not installed',
                onTap: () {},
                trailing: _SmallButton(label: 'Install', onTap: _startInstall),
              ),
            _AddServerRow(onAdd: _addCustomServer),
          ],
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

  Widget _buildGameControls(ServerInfo? info, bool cheatsOn) {
    final hasBots = (_gameStatus?.bots ?? 0) > 0;

    return _Panel(
      child: Column(
        children: [
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
          _ToggleRow(
            label: 'Training mode',
            description: 'noclip, infinite ammo, impacts, no round limits',
            enabled: cheatsOn,
            busy: _actionBusy,
            onToggle: () async {
              setState(() => _actionBusy = true);
              if (!cheatsOn) {
                await _server.sendRcon(info, 'exec biobase_dev');
              } else {
                await _server.sendRcon(info, 'exec biobase_play');
              }
              await Future.delayed(const Duration(milliseconds: 500));
              await _refreshGameState();
              if (mounted) setState(() => _actionBusy = false);
            },
          ),
          const _Divider(),
          _ToggleRow(
            label: 'Bots',
            description: hasBots ? '${_gameStatus!.bots} active' : 'fill server with bots',
            enabled: hasBots,
            busy: _actionBusy,
            onToggle: () async {
              setState(() => _actionBusy = true);
              if (hasBots) {
                await _server.stopBots(info);
              } else {
                await _server.startBots(info);
              }
              await _refreshGameState();
              if (mounted) setState(() => _actionBusy = false);
            },
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

// ── Server selector widgets ──

class _SelectorOption extends StatefulWidget {
  final String name;
  final String detail;
  final Color? statusColor;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final Widget? trailing;
  const _SelectorOption({
    required this.name,
    required this.detail,
    this.statusColor,
    required this.onTap,
    this.onRemove,
    this.trailing,
  });

  @override
  State<_SelectorOption> createState() => _SelectorOptionState();
}

class _SelectorOptionState extends State<_SelectorOption> {
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
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          color: _hovered ? BiobaseColors.surfaceHover.withValues(alpha: 0.3) : Colors.transparent,
          child: Row(
            children: [
              Text(widget.name, style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: BiobaseColors.textSecondary)),
              const SizedBox(width: 8),
              if (widget.statusColor != null) ...[
                Container(width: 5, height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.statusColor)),
                const SizedBox(width: 4),
              ],
              Text(widget.detail, style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
              const Spacer(),
              if (widget.trailing != null)
                widget.trailing!
              else if (widget.onRemove != null)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: const Icon(Icons.close, size: 12, color: BiobaseColors.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddServerRow extends StatefulWidget {
  final Future<void> Function(String name, String host, int port) onAdd;
  const _AddServerRow({required this.onAdd});

  @override
  State<_AddServerRow> createState() => _AddServerRowState();
}

class _AddServerRowState extends State<_AddServerRow> {
  bool _expanded = false;
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final raw = _hostCtrl.text.trim();
    if (name.isEmpty || raw.isEmpty) return;

    final parts = raw.split(':');
    final host = parts[0];
    final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 27015) : 27015;

    widget.onAdd(name, host, port);
    _nameCtrl.clear();
    _hostCtrl.clear();
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = true),
            child: Row(
              children: const [
                Icon(Icons.add, size: 12, color: BiobaseColors.textTertiary),
                SizedBox(width: 4),
                Text('Add server', style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 11, color: BiobaseColors.text),
              decoration: const InputDecoration(
                hintText: 'Name',
                hintStyle: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _hostCtrl,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: BiobaseColors.text),
              decoration: const InputDecoration(
                hintText: 'host:port',
                hintStyle: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          _SmallButton(label: 'Add', onTap: _submit),
          const SizedBox(width: 4),
          _SmallButton(label: 'Cancel', onTap: () => setState(() => _expanded = false)),
        ],
      ),
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

class _ToggleRow extends StatefulWidget {
  final String label;
  final String description;
  final bool enabled;
  final bool busy;
  final VoidCallback onToggle;
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.enabled,
    required this.busy,
    required this.onToggle,
  });

  @override
  State<_ToggleRow> createState() => _ToggleRowState();
}

class _ToggleRowState extends State<_ToggleRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    return MouseRegion(
      cursor: widget.busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 6),
          color: _hovered ? BiobaseColors.surfaceHover.withValues(alpha: 0.3) : Colors.transparent,
          child: Row(
            children: [
              SizedBox(width: 100,
                child: Text(widget.label, style: const TextStyle(fontSize: 11, color: BiobaseColors.textTertiary))),
              Expanded(
                child: Text(widget.description, style: const TextStyle(fontSize: 10, color: BiobaseColors.textTertiary)),
              ),
              const SizedBox(width: 8),
              _TogglePill(enabled: on),
            ],
          ),
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  final bool enabled;
  const _TogglePill({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 36,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: enabled ? BiobaseColors.live : BiobaseColors.surfaceHover,
        border: Border.all(
          color: enabled ? BiobaseColors.live : BiobaseColors.border,
        ),
      ),
      alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white : BiobaseColors.textTertiary,
        ),
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
