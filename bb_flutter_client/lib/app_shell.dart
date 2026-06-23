import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'theme.dart';
import 'widgets.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';
import 'services/session_stats_service.dart';
import 'screens/live_screen.dart';
import 'screens/shadow_screen.dart';
import 'screens/replay_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/insights_screen.dart';
import 'services/update_service.dart' show UpdateService, currentVersion;

enum Section { live, shadow, replay, profile, insights }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final ApiService _api = ApiService();
  final SettingsService _settings = SettingsService();
  final UpdateService _updater = UpdateService();
  final SessionStatsService _sessionStats = SessionStatsService();

  Section _section = Section.live;
  bool _drawerOpen = false;
  LiveServerStatus? _serverStatus;
  LiveMovementStatus? _movementStatus;
  String _syncStatus = 'starting…';
  _UpdatePhase _updatePhase = _UpdatePhase.idle;
  String? _updateVersion;
  StreamSubscription? _statusSub;
  StreamSubscription? _movementSub;
  final List<LiveMovementSample> _movementHistory = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _settings.init();
    _statusSub = _api.statusStream.listen((s) {
      if (mounted) setState(() => _serverStatus = s);
    });
    _movementSub = _api.movementStream.listen((m) {
      if (mounted) {
        final tracked = m.tracked ?? m.samples.firstOrNull;
        if (tracked != null) {
          _movementHistory.add(tracked);
          if (_movementHistory.length > 120) {
            _movementHistory.removeAt(0);
          }
          _sessionStats.processSample(tracked);
        }
        setState(() => _movementStatus = m);
      }
    });
    _api.startPolling(trackedPlayer: _settings.trackedPlayerName);
    if (Platform.isWindows) _connectToServer();
    _checkForUpdate();
    setState(() => _syncStatus = 'polling');
  }

  Future<void> _connectToServer() async {
    const host = defaultConnectHost;
    const port = defaultConnectPort;
    final uri = Uri.parse(
        'steam://run/730/-windowed%20-noborder//+connect%20$host:$port');
    try {
      await launchUrl(uri);
      setState(() => _syncStatus = 'Connecting to $host:$port');
    } catch (_) {
      setState(() => _syncStatus = 'Steam not available');
    }
  }

  StatusLevel get _statusLevel {
    final movementOk = _movementStatus?.ok ?? false;
    final serverOk = _serverStatus?.ok ?? false;
    if (movementOk) return StatusLevel.live;
    if (serverOk) return StatusLevel.online;
    return StatusLevel.offline;
  }

  LiveFrame get _liveFrame {
    final tracked =
        _movementStatus?.tracked ?? _movementStatus?.samples.firstOrNull;
    return LiveFrame.fromServerData(_serverStatus, tracked);
  }

  void _pickPlayer(String name) {
    _settings.setTrackedPlayerName(name);
    _api.stopPolling();
    _api.startPolling(trackedPlayer: name);
  }

  Future<void> _checkForUpdate() async {
    final info = await _updater.checkForUpdate();
    if (!mounted || !info.available) return;
    setState(() { _updatePhase = _UpdatePhase.downloading; _updateVersion = info.version; });
    final err = await _updater.downloadAndInstall(info.downloadUrl);
    if (!mounted) return;
    if (err != null) {
      setState(() => _updatePhase = _UpdatePhase.idle);
    } else {
      setState(() => _updatePhase = _UpdatePhase.done);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _updatePhase = _UpdatePhase.idle);
      });
    }
  }

  Future<void> _checkForUpdateManual() async {
    setState(() => _updatePhase = _UpdatePhase.checking);
    final info = await _updater.checkForUpdate();
    if (!mounted) return;
    if (info.available) {
      setState(() { _updatePhase = _UpdatePhase.downloading; _updateVersion = info.version; });
      final err = await _updater.downloadAndInstall(info.downloadUrl);
      if (!mounted) return;
      if (err != null) {
        setState(() => _updatePhase = _UpdatePhase.idle);
      } else {
        setState(() => _updatePhase = _UpdatePhase.done);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _updatePhase = _UpdatePhase.idle);
        });
      }
    } else {
      setState(() => _updatePhase = _UpdatePhase.current);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _updatePhase = _UpdatePhase.idle);
      });
    }
  }

  void _navigateTo(Section s) {
    setState(() {
      _section = s;
      _drawerOpen = false;
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _movementSub?.cancel();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    final topPad = isMac ? 38.0 : 6.0;

    return Scaffold(
      backgroundColor: BiobaseColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              DragToMoveArea(child: SizedBox(height: topPad)),
              DragToMoveArea(
                child: _ContentHeader(
                  serverStatus: _serverStatus,
                  statusLevel: _statusLevel,
                  trackedPlayer: _settings.trackedPlayerName,
                  onPickPlayer: _pickPlayer,
                  onConnect: _connectToServer,
                  api: _api,
                  syncStatus: _syncStatus,
                  onSyncStatusChanged: (s) => setState(() => _syncStatus = s),
                  onOpenNav: () => setState(() => _drawerOpen = true),
                  onCheckUpdate: _checkForUpdateManual,
                  updatePhase: _updatePhase,
                  updateVersion: _updateVersion,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildContent(),
                ),
              ),
              _StatusBar(
                syncStatus: _syncStatus,
                mapName: _serverStatus?.map,
                movementLive: _movementStatus?.ok ?? false,
              ),
            ],
          ),
          if (_drawerOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _drawerOpen = false),
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned(
              top: topPad + 44,
              left: isMac ? 80.0 : 20.0,
              child: _NavPopup(
                section: _section,
                statusLevel: _statusLevel,
                onNav: _navigateTo,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    final frame = _liveFrame;
    final live = _movementStatus?.ok ?? false;
    return switch (_section) {
      Section.live => LiveScreen(frame: frame, live: live, history: _movementHistory, sessionStats: _sessionStats.stats),
      Section.shadow => ShadowScreen(api: _api, mapName: _serverStatus?.map ?? '', live: live),
      Section.replay => const ReplayScreen(),
      Section.profile => ProfileScreen(stats: _sessionStats.stats),
      Section.insights => const InsightsScreen(),
    };
  }
}

// ── Nav popup (floating menu) ──

class _NavPopup extends StatelessWidget {
  final Section section;
  final StatusLevel statusLevel;
  final ValueChanged<Section> onNav;

  const _NavPopup({
    required this.section,
    required this.statusLevel,
    required this.onNav,
  });

  static const _navItems = [
    (Section.live, 'Live', Icons.show_chart),
    (Section.shadow, 'Shadow', Icons.people_outline),
    (Section.replay, 'Replay', Icons.replay),
    (Section.profile, 'Performance Review', Icons.assessment_outlined),
    (Section.insights, 'Insights', Icons.layers_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: BiobaseColors.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BiobaseColors.borderHover),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 30, offset: Offset(0, 8)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in _navItems)
                _NavItem(
                  icon: item.$3,
                  label: item.$2,
                  active: section == item.$1,
                  onTap: () => onNav(item.$1),
                ),
              Container(height: 1, color: BiobaseColors.borderSubtle,
                  margin: const EdgeInsets.symmetric(vertical: 4)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    StatusDot(level: statusLevel),
                    const SizedBox(width: 8),
                    Text(
                      switch (statusLevel) {
                        StatusLevel.live => 'Live',
                        StatusLevel.online => 'Ready',
                        StatusLevel.offline => 'Offline',
                      },
                      style: const TextStyle(
                          fontSize: 11, color: BiobaseColors.textTertiary),
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
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.active
                  ? BiobaseColors.accentDim
                  : _hovered
                      ? BiobaseColors.surfaceHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.active
                      ? BiobaseColors.text
                      : BiobaseColors.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: widget.active
                          ? BiobaseColors.text
                          : BiobaseColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Content header ──

class _ContentHeader extends StatelessWidget {
  final LiveServerStatus? serverStatus;
  final StatusLevel statusLevel;
  final String trackedPlayer;
  final ValueChanged<String> onPickPlayer;
  final VoidCallback onConnect;
  final ApiService api;
  final String syncStatus;
  final ValueChanged<String> onSyncStatusChanged;
  final VoidCallback onOpenNav;
  final VoidCallback onCheckUpdate;
  final _UpdatePhase updatePhase;
  final String? updateVersion;

  const _ContentHeader({
    required this.serverStatus,
    required this.statusLevel,
    required this.trackedPlayer,
    required this.onPickPlayer,
    required this.onConnect,
    required this.api,
    required this.syncStatus,
    required this.onSyncStatusChanged,
    required this.onOpenNav,
    required this.onCheckUpdate,
    required this.updatePhase,
    required this.updateVersion,
  });

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    final leftPad = isMac ? 80.0 : 20.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(leftPad, 8, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onOpenNav,
              child: Image.asset('assets/logo.png', height: 22, filterQuality: FilterQuality.high),
            ),
          ),
          const SizedBox(width: 10),
          _VersionIndicator(phase: updatePhase, updateVersion: updateVersion, onTap: onCheckUpdate),
          const Spacer(),
          _ServerPill(
            status: serverStatus,
            statusLevel: statusLevel,
            trackedPlayer: trackedPlayer,
            onPickPlayer: onPickPlayer,
            onConnect: onConnect,
          ),
          const SizedBox(width: 4),
          _AppMenuButton(
            api: api,
            onStatus: onSyncStatusChanged,
          ),
        ],
      ),
    );
  }
}

// ── Server pill ──

class _ServerPill extends StatefulWidget {
  final LiveServerStatus? status;
  final StatusLevel statusLevel;
  final String trackedPlayer;
  final ValueChanged<String> onPickPlayer;
  final VoidCallback onConnect;

  const _ServerPill({
    required this.status,
    required this.statusLevel,
    required this.trackedPlayer,
    required this.onPickPlayer,
    required this.onConnect,
  });

  @override
  State<_ServerPill> createState() => _ServerPillState();
}

class _ServerPillState extends State<_ServerPill> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.status?.ok ?? false;
    final mapName = widget.status?.map ?? 'offline';

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (_) => _buildDropdown(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _overlayController.toggle(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(level: widget.statusLevel),
                  const SizedBox(width: 6),
                  Text(
                    isOnline ? mapName : 'Not connected',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: BiobaseColors.textTertiary),
                  ),
                  const SizedBox(width: 4),
                  const Text('▾',
                      style: TextStyle(
                          fontSize: 8, color: BiobaseColors.textTertiary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    final humans = widget.status?.humans ?? [];
    final bots = widget.status?.botCount ?? 0;
    final isOnline = widget.status?.ok ?? false;
    final mapName = widget.status?.map ?? 'offline';

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _overlayController.hide(),
            behavior: HitTestBehavior.opaque,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                color: BiobaseColors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BiobaseColors.borderHover),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 30,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Server',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: BiobaseColors.textSecondary)),
                            StatusBadge(
                                status: isOnline
                                    ? StatusLevel.online
                                    : StatusLevel.offline),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(mapName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: BiobaseColors.text)),
                        if (isOnline)
                          Text(
                            '${humans.length} player${humans.length != 1 ? "s" : ""}${bots > 0 ? " · $bots bot${bots != 1 ? "s" : ""}" : ""}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: BiobaseColors.textTertiary),
                          ),
                      ],
                    ),
                  ),
                  if (humans.isNotEmpty) ...[
                    Container(height: 1, color: BiobaseColors.border),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Players — click to track',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: BiobaseColors.textSecondary)),
                          const SizedBox(height: 4),
                          ...humans.map((p) => _playerRow(p)),
                        ],
                      ),
                    ),
                  ],
                  Container(height: 1, color: BiobaseColors.border),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _overlayController.hide();
                          widget.onConnect();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BiobaseColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                          textStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        child: const Text('Connect to Server'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _playerRow(LiveServerPlayer player) {
    final selected = widget.trackedPlayer == player.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            widget.onPickPlayer(player.name);
            _overlayController.hide();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? BiobaseColors.accentDim : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(player.name,
                    style: const TextStyle(
                        fontSize: 12, color: BiobaseColors.text)),
                Text('${player.ping}ms',
                    style: const TextStyle(
                        fontSize: 11, color: BiobaseColors.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── App menu (⋯) ──

class _AppMenuButton extends StatefulWidget {
  final ApiService api;
  final ValueChanged<String> onStatus;

  const _AppMenuButton({required this.api, required this.onStatus});

  @override
  State<_AppMenuButton> createState() => _AppMenuButtonState();
}

class _AppMenuButtonState extends State<_AppMenuButton> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();
  String? _companionUrl;
  bool _busy = false;

  Future<void> _createSideView() async {
    setState(() => _busy = true);
    final result = await widget.api.createCompanionLink();
    if (result['ok'] == true && result['url'] != null) {
      setState(() {
        _companionUrl = result['url'] as String;
        _busy = false;
      });
      widget.onStatus('SideView ready');
    } else {
      setState(() => _busy = false);
      widget.onStatus(result['error']?.toString() ?? 'SideView failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (_) => _buildMenu(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              final opening = !_overlayController.isShowing;
              if (opening) {
                _overlayController.show();
                if (_companionUrl == null) _createSideView();
              } else {
                _overlayController.hide();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: const Text('⋯',
                  style: TextStyle(
                      fontSize: 16,
                      letterSpacing: 2,
                      color: BiobaseColors.textTertiary)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu() {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _overlayController.hide(),
            behavior: HitTestBehavior.opaque,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 4),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                color: BiobaseColors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BiobaseColors.borderHover),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 30,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('SideView',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: BiobaseColors.textSecondary)),
                        SizedBox(height: 2),
                        Text('Open stats on another screen',
                            style: TextStyle(
                                fontSize: 11,
                                color: BiobaseColors.textTertiary)),
                      ],
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Center(
                          child: Text('Generating…',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: BiobaseColors.textTertiary))),
                    ),
                  if (_companionUrl != null) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: QrImageView(
                          data: _companionUrl!,
                          version: QrVersions.auto,
                          size: 160,
                          backgroundColor: Colors.transparent,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: BiobaseColors.text,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: BiobaseColors.text,
                          ),
                        ),
                      ),
                    ),
                    Container(height: 1, color: BiobaseColors.border),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: _menuBtn('New QR', () {
                              _createSideView();
                            }),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _menuBtn('Copy link', () async {
                              if (_companionUrl == null) return;
                              await Clipboard.setData(
                                  ClipboardData(text: _companionUrl!));
                              widget.onStatus('SideView link copied');
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuBtn(String label, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: BiobaseColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: BiobaseColors.border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: BiobaseColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

// ── Update indicator (inline on version number) ──

enum _UpdatePhase { idle, checking, downloading, done, current }

class _VersionIndicator extends StatelessWidget {
  final _UpdatePhase phase;
  final String? updateVersion;
  final VoidCallback onTap;

  const _VersionIndicator({required this.phase, required this.updateVersion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final showNewVersion = phase == _UpdatePhase.downloading || phase == _UpdatePhase.done;
    final versionText = showNewVersion && updateVersion != null ? 'v$updateVersion' : 'v$currentVersion';
    final showSpinner = phase == _UpdatePhase.checking || phase == _UpdatePhase.downloading;
    final showCheck = phase == _UpdatePhase.done || phase == _UpdatePhase.current;
    final color = phase == _UpdatePhase.done ? BiobaseColors.live
        : phase == _UpdatePhase.downloading ? BiobaseColors.accent
        : BiobaseColors.textTertiary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: phase == _UpdatePhase.idle || phase == _UpdatePhase.current ? onTap : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (showSpinner)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: color)),
            ),
          if (showCheck)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(Icons.check, size: 11, color: color),
            ),
          Text(versionText, style: TextStyle(fontSize: 11, color: color)),
        ]),
      ),
    );
  }
}

// ── Status bar ──

class _StatusBar extends StatelessWidget {
  final String syncStatus;
  final String? mapName;
  final bool movementLive;

  const _StatusBar({
    required this.syncStatus,
    required this.mapName,
    required this.movementLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: BiobaseColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(syncStatus,
              style: const TextStyle(
                  fontSize: 11, color: BiobaseColors.textTertiary)),
          const SizedBox(width: 12),
          Text(mapName ?? 'server offline',
              style: const TextStyle(
                  fontSize: 11, color: BiobaseColors.textTertiary)),
          const SizedBox(width: 12),
          Text(movementLive ? 'movement feed live' : 'ready',
              style: const TextStyle(
                  fontSize: 11, color: BiobaseColors.textTertiary)),
        ],
      ),
    );
  }
}
