import 'package:flutter/material.dart';

import '../services/demo_analytics.dart';
import '../services/demo_session.dart';

import '../theme.dart';
import '../widgets/mini_charts.dart';

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
  String? _analyzedDemoId;
  String? _steamid;

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
    String? keepSelection = _steamid;
    if (keepSelection == null ||
        !analytics.players.any((p) => p.steamid == keepSelection)) {
      keepSelection = analytics.players.isEmpty
          ? null
          : analytics.players.first.steamid;
    }
    setState(() {
      _analytics = analytics;
      _analyzedDemoId = demo.demoId;
      _steamid = keepSelection;
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
        _combatSection(analytics, steamid),
        const SizedBox(height: 8),
        _movementSection(analytics, steamid),
        const SizedBox(height: 8),
        _mechanicsSection(analytics, steamid, stats),
        const SizedBox(height: 8),
        _consistencySection(analytics, steamid),
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
