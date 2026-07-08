import 'package:flutter/material.dart';

import '../services/demo_analytics.dart';
import '../services/demo_session.dart';
import '../services/radar_analytics.dart';
import '../services/career_service.dart';

import '../theme.dart';
import '../widgets/mini_charts.dart';
import '../widgets/radar_chart.dart';

/// Performance Review: tick-level analysis of the demo loaded in Replay.
/// One screen — summary strip, then expandable category sections. Every
/// chart point taps through to that tick in the replay.
class ReviewScreen extends StatefulWidget {
  final VoidCallback? onOpenReplay;

  const ReviewScreen({super.key, this.onOpenReplay});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final DemoSession _session = DemoSession.instance;
  DemoAnalytics? _analytics;
  RadarAnalytics? _radar;
  String? _analyzedDemoId;
  String? _steamid;

  // Radar controls
  RadarSide _radarSide = RadarSide.both;
  String _radarCompare = 'none'; // none | team_avg | opp_avg | <steamid>
  int? _radarAxis;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _rebuild();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    _rebuild();
  }

  void _rebuild() {
    final demo = _session.demo;
    if (demo == null) {
      setState(() {
        _analytics = null;
        _radar = null;
        _analyzedDemoId = null;
        _steamid = null;
      });
      return;
    }
    if (demo.demoId == _analyzedDemoId && _analytics != null) {
      setState(() {});
      return;
    }
    final analytics = DemoAnalytics(demo);
    final radar = RadarAnalytics(analytics);
    String? keepSelection = _steamid;
    if (keepSelection == null ||
        !analytics.players.any((p) => p.steamid == keepSelection)) {
      keepSelection = analytics.players.isEmpty
          ? null
          : analytics.players.first.steamid;
    }
    setState(() {
      _analytics = analytics;
      _radar = radar;
      _analyzedDemoId = demo.demoId;
      _steamid = keepSelection;
      _radarCompare = 'none';
      _radarAxis = null;
    });
  }

  void _jumpToTick(int tick) {
    _session.requestSeek(tick);
    widget.onOpenReplay?.call();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = _analytics;
    final steamid = _steamid;
    if (analytics == null || steamid == null) {
      return _emptyState();
    }
    final stats = analytics.statsFor(steamid);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _header(analytics),
        const SizedBox(height: 8),
        _summaryStrip(stats),
        const SizedBox(height: 8),
        _radarSection(steamid),
        const SizedBox(height: 8),
        _combatSection(analytics, steamid),
        const SizedBox(height: 8),
        _movementSection(analytics, steamid),
        const SizedBox(height: 8),
        _mechanicsSection(analytics, steamid, stats),
        const SizedBox(height: 8),
        _consistencySection(analytics, steamid),
        const SizedBox(height: 8),
        _careerSection(steamid),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.query_stats,
            size: 44,
            color: BiobaseColors.textTertiary.withAlpha(80),
          ),
          const SizedBox(height: 12),
          const Text(
            'No demo loaded',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: BiobaseColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Load a demo in Replay — its tick data appears here',
            style: TextStyle(fontSize: 11, color: BiobaseColors.textTertiary),
          ),
          const SizedBox(height: 14),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onOpenReplay,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: BiobaseColors.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'Open Replay',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BiobaseColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionTitle(String title, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BiobaseColors.text,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                style: const TextStyle(
                  fontSize: 9,
                  color: BiobaseColors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(DemoAnalytics analytics) {
    return _panel(
      children: [
        Text(
          _session.demoName ?? '',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: BiobaseColors.text,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          '${analytics.demo.mapName} · ${analytics.rounds.length} rounds',
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: BiobaseColors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final p in analytics.players) _playerChip(p),
          ],
        ),
      ],
    );
  }

  Widget _playerChip(PlayerRef p) {
    final selected = p.steamid == _steamid;
    final teamColor = p.team == 'CT'
        ? const Color(0xFF60A5FA)
        : p.team == 'T'
        ? const Color(0xFFF59E0B)
        : BiobaseColors.textTertiary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _steamid = p.steamid),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? BiobaseColors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? BiobaseColors.accent : BiobaseColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: teamColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                p.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? BiobaseColors.accent : BiobaseColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryStrip(PlayerMatchStats stats) {
    return _panel(
      children: [
        Row(
          children: [
            _kpi('${stats.kills}', 'Kills'),
            _kpi('${stats.deaths}', 'Deaths'),
            _kpi(stats.kd.toStringAsFixed(2), 'K/D'),
            _kpi(stats.adr.toStringAsFixed(0), 'ADR'),
            _kpi('${stats.hsPct.round()}%', 'HS'),
            _kpi('${stats.avgSpeed.round()}', 'Avg u/s'),
            _kpi(
              stats.counterStrafePct.isNaN
                  ? '—'
                  : '${stats.counterStrafePct.round()}%',
              'Set shots',
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpi(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: BiobaseColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Role Performance Radar ──

  RadarProfile? _comparisonProfile(RadarAnalytics radar, String steamid) {
    switch (_radarCompare) {
      case 'none':
        return null;
      case 'team_avg':
        final ids = [...radar.teammatesOf(steamid), steamid];
        return radar.averageProfile(ids, side: _radarSide, label: 'Team avg');
      case 'opp_avg':
        return radar.averageProfile(
          radar.teammatesOf(steamid, opponents: true),
          side: _radarSide,
          label: 'Opponent avg',
        );
      default:
        return radar.profileFor(
          _radarCompare,
          side: _radarSide,
          label: _nameOf(_radarCompare),
        );
    }
  }

  String _nameOf(String steamid) {
    final a = _analytics;
    if (a == null) return steamid;
    for (final p in a.players) {
      if (p.steamid == steamid) return p.name;
    }
    return steamid;
  }

  Widget _radarSection(String steamid) {
    final radar = _radar;
    final analytics = _analytics;
    if (radar == null || analytics == null) return const SizedBox.shrink();
    final profile = radar.profileFor(
      steamid,
      side: _radarSide,
      label: _nameOf(steamid),
    );
    final comparison = _comparisonProfile(radar, steamid);
    final lowSample = profile.rounds < 30;
    final axis = _radarAxis;

    return _panel(
      children: [
        Row(
          children: [
            const Text(
              'Role Radar',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.text,
              ),
            ),
            const SizedBox(width: 10),
            _sideToggle(),
            const Spacer(),
            _compareSelector(analytics, steamid),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  RadarChart(
                    profile: profile,
                    comparison: comparison,
                    selectedAxis: axis,
                    onAxisTap: (i) =>
                        setState(() => _radarAxis = _radarAxis == i ? null : i),
                    lowSample: lowSample,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legendSwatch(BiobaseColors.accent, profile.label),
                      if (comparison != null) ...[
                        const SizedBox(width: 14),
                        _legendSwatch(
                          BiobaseColors.warning,
                          comparison.label,
                          dashed: true,
                        ),
                      ],
                    ],
                  ),
                  if (lowSample)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        profile.rounds < 30
                            ? 'Low sample — ${profile.rounds} rounds, directional only'
                            : '',
                        style: const TextStyle(
                          fontSize: 9,
                          color: BiobaseColors.warning,
                        ),
                      ),
                    ),
                  if (axis != null) _axisDetail(profile, comparison, axis),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(flex: 6, child: _radarTable(profile, comparison)),
          ],
        ),
      ],
    );
  }

  Widget _sideToggle() {
    Widget chip(RadarSide side, String label) {
      final active = _radarSide == side;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() => _radarSide = side),
          child: Container(
            margin: const EdgeInsets.only(right: 3),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: active ? BiobaseColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: active ? BiobaseColors.accent : BiobaseColors.border,
              ),
            ),
            child: Text(
              label,
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(RadarSide.both, 'BOTH'),
        chip(RadarSide.t, 'T'),
        chip(RadarSide.ct, 'CT'),
      ],
    );
  }

  Widget _compareSelector(DemoAnalytics analytics, String steamid) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'none', child: Text('No comparison')),
      const DropdownMenuItem(value: 'team_avg', child: Text('Team average')),
      const DropdownMenuItem(value: 'opp_avg', child: Text('Opponent average')),
      for (final p in analytics.players)
        if (p.steamid != steamid)
          DropdownMenuItem(value: p.steamid, child: Text('vs ${p.name}')),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: BiobaseColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((i) => i.value == _radarCompare)
              ? _radarCompare
              : 'none',
          items: items,
          isDense: true,
          style: const TextStyle(fontSize: 10, color: BiobaseColors.text),
          dropdownColor: BiobaseColors.surfaceRaised,
          icon: const Icon(
            Icons.expand_more,
            size: 14,
            color: BiobaseColors.textTertiary,
          ),
          onChanged: (v) => setState(() => _radarCompare = v ?? 'none'),
        ),
      ),
    );
  }

  Widget _legendSwatch(Color color, String label, {bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: dashed ? 1.5 : 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: BiobaseColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _axisDetail(
    RadarProfile profile,
    RadarProfile? comparison,
    int axis,
  ) {
    if (axis < 0 || axis >= profile.axes.length) {
      return const SizedBox.shrink();
    }
    final v = profile.axes[axis];
    final c = comparison != null && axis < comparison.axes.length
        ? comparison.axes[axis]
        : null;
    final parts = <String>[
      v.def.name,
      '${_fmtRaw(v)}${v.def.unit.isEmpty ? '' : ' ${v.def.unit}'}',
      'P${v.normalized.round()}',
      if (c != null) 'vs ${_fmtRaw(c)}',
      'n=${v.sample}',
      if (v.stabilized) 'stabilized',
      if (v.def.styleAxis) 'style axis',
      if (v.def.lowerIsBetter) 'lower is better',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        parts.join('  ·  '),
        style: const TextStyle(
          fontSize: 9,
          fontFamily: 'monospace',
          color: BiobaseColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _fmtRaw(RadarAxisValue v) => v.raw.toStringAsFixed(v.def.decimals);

  Widget _radarTable(RadarProfile profile, RadarProfile? comparison) {
    TextStyle cell({Color? color, FontWeight? weight}) => TextStyle(
      fontSize: 9,
      fontFamily: 'monospace',
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? BiobaseColors.textSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 4,
              child: Text('METRIC', style: cell(color: BiobaseColors.textTertiary)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'RAW',
                textAlign: TextAlign.right,
                style: cell(color: BiobaseColors.textTertiary),
              ),
            ),
            if (comparison != null)
              Expanded(
                flex: 2,
                child: Text(
                  'COMP',
                  textAlign: TextAlign.right,
                  style: cell(color: BiobaseColors.textTertiary),
                ),
              ),
            Expanded(
              flex: 2,
              child: Text(
                'PCTL',
                textAlign: TextAlign.right,
                style: cell(color: BiobaseColors.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < profile.axes.length; i++)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () =>
                  setState(() => _radarAxis = _radarAxis == i ? null : i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
                decoration: BoxDecoration(
                  color: _radarAxis == i
                      ? BiobaseColors.accentDim
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        profile.axes[i].def.name,
                        style: cell(
                          color: _radarAxis == i
                              ? BiobaseColors.accent
                              : BiobaseColors.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _fmtRaw(profile.axes[i]),
                        textAlign: TextAlign.right,
                        style: cell(weight: FontWeight.w600),
                      ),
                    ),
                    if (comparison != null)
                      Expanded(
                        flex: 2,
                        child: Text(
                          i < comparison.axes.length
                              ? _fmtRaw(comparison.axes[i])
                              : '—',
                          textAlign: TextAlign.right,
                          style: cell(color: BiobaseColors.warning),
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'P${profile.axes[i].normalized.round()}',
                        textAlign: TextAlign.right,
                        style: cell(
                          color: profile.axes[i].normalized >= 50
                              ? BiobaseColors.live
                              : BiobaseColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'Percentiles vs static pro reference (v1). Style axes describe role, not quality.',
          style: TextStyle(fontSize: 8, color: BiobaseColors.textTertiary),
        ),
      ],
    );
  }

  // ── Career (cross-demo) ──

  Widget _careerSection(String steamid) {
    final entries = CareerService.instance.forPlayer(steamid);
    if (entries.length < 2) return const SizedBox.shrink();
    final ratings = [
      for (var i = 0; i < entries.length; i++)
        ChartPoint(
          x: (i + 1).toDouble(),
          y: entries[i].metrics['rating'] ?? 0,
          tick: 0,
        ),
    ];
    final recent = entries.reversed.take(8).toList();
    return _panel(
      children: [
        _sectionTitle(
          'Career',
          hint: '${entries.length} analyzed demos on this machine',
        ),
        const Text(
          'BB Rating per demo (oldest → newest)',
          style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
        ),
        const SizedBox(height: 4),
        MiniLineChart(points: ratings, height: 64),
        const SizedBox(height: 10),
        for (final e in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    e.demoName,
                    style: const TextStyle(
                      fontSize: 9,
                      color: BiobaseColors.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    e.mapName,
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: BiobaseColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    'ADR ${(e.metrics['adr'] ?? 0).toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: BiobaseColors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    (e.metrics['rating'] ?? 0).toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: (e.metrics['rating'] ?? 0) >= 1.0
                          ? BiobaseColors.live
                          : BiobaseColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<ChartPoint> _roundBars(DemoAnalytics a, List<num> values) {
    return [
      for (var i = 0; i < values.length && i < a.rounds.length; i++)
        ChartPoint(
          x: (i + 1).toDouble(),
          y: values[i].toDouble(),
          tick: a.rounds[i].startTick,
        ),
    ];
  }

  Widget _combatSection(DemoAnalytics a, String steamid) {
    final kills = _roundBars(a, a.killsPerRound(steamid));
    final deaths = _roundBars(a, a.deathsPerRound(steamid));
    final damage = _roundBars(a, a.damagePerRound(steamid));
    return _panel(
      children: [
        _sectionTitle('Combat', hint: 'tap a round to watch it'),
        const Text(
          'Kills / deaths by round',
          style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
        ),
        const SizedBox(height: 4),
        MiniBarChart(
          bars: kills,
          secondaryBars: deaths,
          color: BiobaseColors.live,
          secondaryColor: BiobaseColors.error,
          onBarTap: (p) => _jumpToTick(p.tick),
        ),
        const SizedBox(height: 12),
        const Text(
          'Damage by round',
          style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
        ),
        const SizedBox(height: 4),
        MiniBarChart(
          bars: damage,
          color: BiobaseColors.accent,
          onBarTap: (p) => _jumpToTick(p.tick),
        ),
      ],
    );
  }

  Widget _movementSection(DemoAnalytics a, String steamid) {
    final speeds = a.speedSeries(steamid);
    final downsampled = _downsample(speeds, 420);
    final roundMarkers = [
      for (final r in a.rounds)
        (r.startTick - a.demo.startTick) /
            (a.demo.tickRateGuess <= 0 ? 64 : a.demo.tickRateGuess),
    ];
    final avgSpeed = _roundBars(a, a.avgSpeedPerRound(steamid));
    return _panel(
      children: [
        _sectionTitle('Movement', hint: 'speed over the match, u/s'),
        MiniLineChart(
          points: [
            for (final s in downsampled)
              ChartPoint(x: s.timeSec, y: s.value, tick: s.tick),
          ],
          unit: ' u/s',
          markersX: roundMarkers,
          onPointTap: (p) => _jumpToTick(p.tick),
        ),
        const SizedBox(height: 12),
        const Text(
          'Average speed by round',
          style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
        ),
        const SizedBox(height: 4),
        MiniBarChart(
          bars: avgSpeed,
          color: BiobaseColors.accent,
          onBarTap: (p) => _jumpToTick(p.tick),
        ),
      ],
    );
  }

  Widget _mechanicsSection(
    DemoAnalytics a,
    String steamid,
    PlayerMatchStats stats,
  ) {
    final shots = a.shotSpeeds(steamid);
    final flicks = a.killFlicks(steamid);
    return _panel(
      children: [
        _sectionTitle(
          'Mechanical Execution',
          hint: 'counter-strafing and flicks',
        ),
        Row(
          children: [
            _kpi(
              shots.isEmpty ? '—' : '${stats.counterStrafePct.round()}%',
              'Shots fired set (<60 u/s)',
            ),
            _kpi('${shots.length}', 'Shots'),
            _kpi(
              flicks.isEmpty ? '—' : '${stats.avgFlickSpeed.round()}°/s',
              'Avg flick into kill',
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Speed at each shot — low is set, high is running',
          style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
        ),
        const SizedBox(height: 4),
        MiniLineChart(
          points: [
            for (final s in _downsample(shots, 400))
              ChartPoint(x: s.timeSec, y: s.value, tick: s.tick),
          ],
          color: BiobaseColors.warning,
          unit: ' u/s',
          onPointTap: (p) => _jumpToTick(p.tick),
        ),
        if (flicks.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Crosshair flick speed before each kill',
            style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
          ),
          const SizedBox(height: 4),
          MiniBarChart(
            bars: [
              for (var i = 0; i < flicks.length; i++)
                ChartPoint(
                  x: (i + 1).toDouble(),
                  y: flicks[i].value,
                  tick: flicks[i].tick,
                ),
            ],
            color: BiobaseColors.live,
            onBarTap: (p) => _jumpToTick(p.tick),
          ),
        ],
      ],
    );
  }

  Widget _consistencySection(DemoAnalytics a, String steamid) {
    final damage = a.damagePerRound(steamid);
    final speed = a.avgSpeedPerRound(steamid);
    final dist = a.distancePerRound(steamid);
    final adrSigma = DemoAnalytics.stdDev(damage);
    final speedSigma = DemoAnalytics.stdDev(speed);
    return _panel(
      children: [
        _sectionTitle('Consistency', hint: 'round-to-round variance — lower σ is steadier'),
        Row(
          children: [
            _kpi('±${adrSigma.round()}', 'Damage σ'),
            _kpi('±${speedSigma.round()}', 'Speed σ u/s'),
            _kpi(
              dist.isEmpty
                  ? '—'
                  : '${(dist.reduce((x, y) => x + y) / dist.length / 1000).toStringAsFixed(1)}k',
              'Avg dist/round u',
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Distance travelled by round',
          style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
        ),
        const SizedBox(height: 4),
        MiniBarChart(
          bars: _roundBars(a, dist),
          color: BiobaseColors.accent,
          onBarTap: (p) => _jumpToTick(p.tick),
        ),
      ],
    );
  }

  List<TickSample> _downsample(List<TickSample> input, int target) {
    if (input.length <= target) return input;
    final stride = (input.length / target).ceil();
    return [
      for (var i = 0; i < input.length; i += stride) input[i],
    ];
  }
}
