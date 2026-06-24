import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/performance_contract.dart';
import '../models/performance_metric_catalog.dart';
import '../models/performance_review.dart';
import '../models/session_stats.dart';
import '../services/settings_service.dart';
import '../widgets/performance_evidence.dart';

const _defaultCategoryOrder = [
  PerformanceCategoryId.movement,
  PerformanceCategoryId.aim,
  PerformanceCategoryId.combat,
  PerformanceCategoryId.utility,
  PerformanceCategoryId.positioning,
  PerformanceCategoryId.decisionMaking,
  PerformanceCategoryId.teamplay,
  PerformanceCategoryId.economy,
  PerformanceCategoryId.roundPerformance,
  PerformanceCategoryId.consistency,
  PerformanceCategoryId.mechanicalExecution,
  PerformanceCategoryId.biometrics,
];

class ProfileScreen extends StatefulWidget {
  final SessionStats stats;
  final SettingsService settings;

  const ProfileScreen({super.key, required this.stats, required this.settings});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _scroll = ScrollController();
  final Set<PerformanceCategoryId> _expanded = {};
  final Map<PerformanceCategoryId, GlobalKey> _keys = {
    for (final id in _defaultCategoryOrder) id: GlobalKey(),
  };
  late List<PerformanceCategoryId> _categoryOrder;

  @override
  void initState() {
    super.initState();
    _categoryOrder = _restoreIds(
      widget.settings.performanceCategoryOrder,
      fallback: _defaultCategoryOrder,
    );
    _expanded.addAll(
      _restoreIds(widget.settings.expandedPerformanceCategories),
    );
  }

  List<PerformanceCategoryId> _restoreIds(
    List<String> stored, {
    List<PerformanceCategoryId> fallback = const [],
  }) {
    final restored = <PerformanceCategoryId>[];
    for (final name in stored) {
      for (final id in PerformanceCategoryId.values) {
        if (id.name == name && !restored.contains(id)) restored.add(id);
      }
    }
    if (restored.isEmpty) return List.of(fallback);
    for (final id in _defaultCategoryOrder) {
      if (!restored.contains(id)) restored.add(id);
    }
    return restored;
  }

  void _persistOrder() {
    widget.settings.setPerformanceCategoryOrder(
      _categoryOrder.map((id) => id.name).toList(),
    );
  }

  void _persistExpanded() {
    widget.settings.setExpandedPerformanceCategories(
      _expanded.map((id) => id.name).toList(),
    );
  }

  void _scrollTo(PerformanceCategoryId id) {
    setState(() => _expanded.add(id));
    _persistExpanded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggle(PerformanceCategoryId id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
    _persistExpanded();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _categoryOrder.removeAt(oldIndex);
      _categoryOrder.insert(newIndex, item);
    });
    _persistOrder();
  }

  void _resetOrder() {
    setState(() => _categoryOrder = List.of(_defaultCategoryOrder));
    _persistOrder();
  }

  void _expandAll() {
    setState(() => _expanded.addAll(_categoryOrder));
    _persistExpanded();
  }

  void _collapseAll() {
    setState(() => _expanded.clear());
    _persistExpanded();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final assessments = s.releaseAssessments;
    final assessmentsById = {for (final a in assessments) a.id: a};
    return Column(
      children: [
        _TopSummary(stats: s, assessments: assessments),
        const SizedBox(height: 6),
        _ReviewControls(
          expandedCount: _expanded.length,
          onExpandAll: _expandAll,
          onCollapseAll: _collapseAll,
          onResetOrder: _resetOrder,
        ),
        const SizedBox(height: 6),
        _CategoryRail(
          order: _categoryOrder,
          assessments: assessmentsById,
          onTap: _scrollTo,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: _scroll,
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            itemCount: _categoryOrder.length,
            onReorderItem: _reorder,
            itemBuilder: (_, i) {
              final id = _categoryOrder[i];
              final assessment = assessmentsById[id]!;
              return Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.only(bottom: 3),
                child: Container(
                  key: _keys[id],
                  child: _Section(
                    id: id,
                    assessment: assessment,
                    expanded: _expanded.contains(id),
                    onToggle: () => _toggle(id),
                    dragHandle: ReorderableDragStartListener(
                      index: i,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 17,
                          color: BiobaseColors.textTertiary,
                        ),
                      ),
                    ),
                    stats: s,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════
// TOP SUMMARY
// ════════════════════════════════════════

class _TopSummary extends StatelessWidget {
  final SessionStats stats;
  final List<CategoryAssessment> assessments;
  const _TopSummary({required this.stats, required this.assessments});

  @override
  Widget build(BuildContext context) {
    final overall = stats.releaseOverallScore;
    final available = assessments.where((a) => a.available).toList();
    String strongest = '—', weakest = '—';
    double hi = 0, lo = 101;
    for (final assessment in available) {
      final score = assessment.score!;
      if (score > hi) {
        hi = score;
        strongest = assessment.label;
      }
      if (score < lo) {
        lo = score;
        weakest = assessment.label;
      }
    }
    if (hi == 0) strongest = '—';
    if (lo > 100) weakest = '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CustomPaint(
              painter: _ArcGaugePainter(
                value: (overall / 100).clamp(0.0, 1.0),
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PERFORMANCE REVIEW',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: BiobaseColors.textTertiary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _chip('Strength', strongest, BiobaseColors.live),
                    const SizedBox(width: 20),
                    _chip('Weakness', weakest, BiobaseColors.warning),
                    const SizedBox(width: 20),
                    _chip(
                      'Samples',
                      '${stats.totalSamples}',
                      BiobaseColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: BiobaseColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════
// CATEGORY RAIL
// ════════════════════════════════════════

class _ReviewControls extends StatelessWidget {
  final int expandedCount;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final VoidCallback onResetOrder;

  const _ReviewControls({
    required this.expandedCount,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onResetOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.drag_indicator_rounded,
          size: 14,
          color: BiobaseColors.textTertiary,
        ),
        const SizedBox(width: 5),
        const Text(
          'Drag categories to personalize your review',
          style: TextStyle(fontSize: 9, color: BiobaseColors.textTertiary),
        ),
        const Spacer(),
        Text(
          expandedCount.toString() + ' open',
          style: const TextStyle(
            fontSize: 9,
            color: BiobaseColors.textTertiary,
          ),
        ),
        const SizedBox(width: 8),
        _ReviewAction(label: 'Expand all', onTap: onExpandAll),
        _ReviewAction(label: 'Collapse all', onTap: onCollapseAll),
        _ReviewAction(label: 'Reset order', onTap: onResetOrder),
      ],
    );
  }
}

class _ReviewAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ReviewAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 24),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        foregroundColor: BiobaseColors.textSecondary,
        textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  final List<PerformanceCategoryId> order;
  final Map<PerformanceCategoryId, CategoryAssessment> assessments;
  final ValueChanged<PerformanceCategoryId> onTap;

  const _CategoryRail({
    required this.order,
    required this.assessments,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: order.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final id = order[i];
          final assessment = assessments[id]!;
          final score = assessment.score;
          final live = assessment.available;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onTap(id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: BiobaseColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      assessment.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: live
                            ? BiobaseColors.text
                            : BiobaseColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      live ? score!.toInt().toString() : '—',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _scoreColor(score ?? 0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════
// EXPANDABLE SECTION
// ════════════════════════════════════════

class _Section extends StatelessWidget {
  final PerformanceCategoryId id;
  final CategoryAssessment assessment;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget dragHandle;
  final SessionStats stats;

  const _Section({
    required this.id,
    required this.assessment,
    required this.expanded,
    required this.onToggle,
    required this.dragHandle,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    dragHandle,
                    const SizedBox(width: 7),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CustomPaint(
                        painter: _MiniGaugePainter(
                          value: ((assessment.score ?? 0) / 100).clamp(
                            0.0,
                            1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        assessment.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BiobaseColors.text,
                        ),
                      ),
                    ),
                    PerformanceEvidenceBadge(assessment: assessment),
                    const SizedBox(width: 10),
                    if (!expanded)
                      Flexible(
                        child: Text(
                          collapsedAssessmentSummary(assessment),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: BiobaseColors.textTertiary,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: BiobaseColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PerformanceEvidenceNote(assessment: assessment),
                        const SizedBox(height: 12),
                        _buildContent(id, stats),
                        const SizedBox(height: 14),
                        _MetricInventory(
                          metrics: performanceMetricCatalog[id] ?? const [],
                          assessment: assessment,
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}

Widget _buildContent(PerformanceCategoryId id, SessionStats s) {
  return switch (id) {
    PerformanceCategoryId.movement => _MovementContent(s: s),
    PerformanceCategoryId.aim => _AimContent(s: s),
    PerformanceCategoryId.combat => _CombatContent(s: s),
    PerformanceCategoryId.utility => _UtilityContent(s: s),
    PerformanceCategoryId.positioning => _PositioningContent(s: s),
    PerformanceCategoryId.decisionMaking => _DecisionContent(s: s),
    PerformanceCategoryId.teamplay => _TeamplayContent(s: s),
    PerformanceCategoryId.economy => _EconomyContent(s: s),
    PerformanceCategoryId.roundPerformance => _RoundContent(s: s),
    PerformanceCategoryId.consistency => _ConsistencyContent(s: s),
    PerformanceCategoryId.mechanicalExecution => _MechanicsContent(s: s),
    PerformanceCategoryId.biometrics => _BiometricsContent(s: s),
  };
}

// ════════════════════════════════════════
// CATEGORY CONTENT BUILDERS
// ════════════════════════════════════════

class _MovementContent extends StatelessWidget {
  final SessionStats s;
  const _MovementContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Kpi('AVG', '${s.speedAvgSafe.toInt()}', ' u/s'),
            _Kpi('MAX', '${s.speedMax.toInt()}', ' u/s'),
            _Kpi('MIN', '${s.speedMinSafe.toInt()}', ' u/s'),
            _Kpi('DIST', _fd(s.distanceTraveled), ''),
            _Kpi('AIR', '${s.airTimePercent.toInt()}', '%'),
            _Kpi('PATH', '${(s.pathEfficiency * 100).toInt()}', '%'),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('SPEED TREND'),
        const SizedBox(height: 4),
        _Spark(data: s.speedHistory, maxVal: 300, height: 44),
        const SizedBox(height: 10),
        const _Label('PATH EFFICIENCY TREND'),
        const SizedBox(height: 4),
        _Spark(
          data: s.pathEfficiencyHistory,
          maxVal: 100,
          height: 32,
          color: BiobaseColors.live,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Kpi('GROUND', '${s.groundSamples}', ' ticks'),
            _Kpi('AIR', '${s.airSamples}', ' ticks'),
            _Kpi('TOTAL', '${s.totalSamples}', ' ticks'),
            _Kpi('STATE', s.movementState, ''),
          ],
        ),
      ],
    );
  }
}

class _AimContent extends StatelessWidget {
  final SessionStats s;
  const _AimContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Kpi('HEAD', '${s.crosshairHeadLevelPercent.toInt()}', '%'),
            _Kpi('1ST BULLET', '${s.firstBulletAccuracy.toInt()}', '%'),
            _Kpi('SPRAY', '${s.sprayAccuracy.toInt()}', '%'),
            _Kpi('TAP', '${s.tapAccuracy.toInt()}', '%'),
            _Kpi('FLICK', '${s.flickAccuracy.toInt()}', '%'),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('ACCURACY'),
        const SizedBox(height: 4),
        _HBar('Headshot', s.headshotPercent),
        _HBar('1st Bullet', s.firstBulletAccuracy),
        _HBar('Spray', s.sprayAccuracy),
        _HBar('Burst', s.burstAccuracy),
        _HBar('Tap', s.tapAccuracy),
        _HBar('Flick', s.flickAccuracy),
        _HBar('Pre-aim', s.preAimAccuracy),
        const SizedBox(height: 10),
        const _Label('CROSSHAIR'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('TRAVEL', '${s.crosshairTravelDistance.toInt()}', '°'),
            _Kpi('ERROR', '${s.crosshairPlacementError.toInt()}', '°'),
            _Kpi('IDLE', '${s.crosshairIdleTime.toStringAsFixed(1)}', 's'),
            _Kpi(
              'OFF-TGT',
              '${s.crosshairOffTargetTime.toStringAsFixed(1)}',
              's',
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('ANGLES & TIMING'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('HOLD', '${s.angleHoldDuration.toStringAsFixed(1)}', 's'),
            _Kpi('WIN', '${s.angleWinRate.toInt()}', '%'),
            _Kpi('REACT', '${s.reactionTime.toInt()}', 'ms'),
            _Kpi('TTK', '${s.timeToKill.toStringAsFixed(2)}', 's'),
            _Kpi('TTD', '${s.timeToDeath.toStringAsFixed(2)}', 's'),
          ],
        ),
        if (s.crosshairHeadLevelPercent == 0 && s.firstBulletAccuracy == 0) ...[
          const SizedBox(height: 10),
          const _NeedsEvents(),
        ],
      ],
    );
  }
}

class _CombatContent extends StatelessWidget {
  final SessionStats s;
  const _CombatContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('ENTRY FRAGGING'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('ATTEMPTS', '${s.entryAttempts}', ''),
            _Kpi('SUCCESS', '${s.entrySuccesses}', ''),
            _Kpi('RATE', '${s.entrySuccessRate.toInt()}', '%'),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('TRADES'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('OPPS', '${s.tradeOpportunities}', ''),
            _Kpi('SUCCESS', '${s.successfulTrades}', ''),
            _Kpi('DEATHS', '${s.tradeDeaths}', ''),
            _Kpi('TIME', '${s.tradeTime.toStringAsFixed(1)}', 's'),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('DAMAGE'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('DEALT', '${s.damageDealt}', ''),
            _Kpi('RECEIVED', '${s.damageReceived}', ''),
            _Kpi('PER RD', s.damagePerRound.toStringAsFixed(1), ''),
            _Kpi('UTIL DMG', '${s.utilityDamage}', ''),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('SURVIVAL'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('ALIVE', '${s.timeAlive.toStringAsFixed(0)}', 's'),
            _Kpi('SURVIVE', '${s.survivalRate.toInt()}', '%'),
          ],
        ),
        const SizedBox(height: 10),
        const _NeedsEvents(),
      ],
    );
  }
}

class _UtilityContent extends StatelessWidget {
  final SessionStats s;
  const _UtilityContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('EFFECTIVENESS'),
        const SizedBox(height: 6),
        _HBar('Flash', s.flashEffectiveness),
        _HBar('Smoke', s.smokeEffectiveness),
        _HBar('Molotov', s.molotovEffectiveness),
        _HBar('HE', s.heEffectiveness),
        _HBar('Usage Eff.', s.utilityUsageEfficiency),
        _HBar('Lineup', s.grenadeLineupSuccess),
        const SizedBox(height: 10),
        const _Label('FLASH DETAILS'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('ENEMIES', '${s.enemiesFlashed}', ''),
            _Kpi('TEAM', '${s.teammatesFlashed}', ''),
            _Kpi(
              'BLIND',
              '${s.flashBlindnessDuration.toStringAsFixed(1)}',
              's',
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _NeedsEvents(),
      ],
    );
  }
}

class _PositioningContent extends StatelessWidget {
  final SessionStats s;
  const _PositioningContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('PEEK BREAKDOWN'),
        const SizedBox(height: 6),
        _HBar('Total', s.peekCount > 0 ? 100 : 0),
        _HBar(
          'Wide',
          s.peekCount > 0 ? s.widePeekCount / s.peekCount * 100 : 0,
        ),
        _HBar(
          'Jiggle',
          s.peekCount > 0 ? s.jigglePeekCount / s.peekCount * 100 : 0,
        ),
        _HBar(
          'Shoulder',
          s.peekCount > 0 ? s.shoulderPeekCount / s.peekCount * 100 : 0,
        ),
        _HBar(
          'Re-peek',
          s.peekCount > 0 ? s.rePeekCount / s.peekCount * 100 : 0,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Kpi('PEEKS', '${s.peekCount}', ''),
            _Kpi('SUCCESS', '${s.peekSuccessRate.toInt()}', '%'),
            _Kpi('EXPOSED', '${s.timeExposed.toStringAsFixed(1)}', 's'),
            _Kpi('COVER', '${s.timeInCover.toStringAsFixed(1)}', 's'),
          ],
        ),
        const SizedBox(height: 10),
        const _NeedsEvents(),
      ],
    );
  }
}

class _DecisionContent extends StatelessWidget {
  final SessionStats s;
  const _DecisionContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Kpi('ROTATION', '${s.rotationTiming.toStringAsFixed(1)}', 's'),
            _Kpi('ROT EFF.', '${s.rotationEfficiency.toInt()}', '%'),
            _Kpi('LATENCY', '${s.decisionLatency.toInt()}', 'ms'),
          ],
        ),
        const SizedBox(height: 10),
        const _NeedsEvents(),
      ],
    );
  }
}

class _EconomyContent extends StatelessWidget {
  final SessionStats s;
  const _EconomyContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Kpi('EQUIP', '\$${s.equipmentValue}', ''),
            _Kpi('STATE', s.economyState, ''),
            _Kpi('WEP SWITCHES', '${s.weaponSwitchCount}', ''),
            _Kpi('RELOAD', '${s.reloadTiming.toStringAsFixed(1)}', 's'),
          ],
        ),
        const SizedBox(height: 10),
        const _NeedsEvents(),
      ],
    );
  }
}

class _TeamplayContent extends StatelessWidget {
  final SessionStats s;
  const _TeamplayContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Kpi('SPACING', '${s.teamSpacing.toInt()}', 'u'),
            _Kpi('NEAREST', '${s.nearestTeammateDistance.toInt()}', 'u'),
            _Kpi('ISO DEATHS', '${s.isolationDeaths}', ''),
          ],
        ),
        const SizedBox(height: 10),
        const _NeedsEvents(),
      ],
    );
  }
}

class _RoundContent extends StatelessWidget {
  final SessionStats s;
  const _RoundContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('RATINGS'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('HLTV', s.hltvRating.toStringAsFixed(2), ''),
            _Kpi('ADR', s.adr.toStringAsFixed(1), ''),
            _Kpi('KAST', '${s.kast.toInt()}', '%'),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('CLUTCH & DUELS'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('CLUTCH ATT', '${s.clutchAttempts}', ''),
            _Kpi('CLUTCH %', '${s.clutchSuccessPercent.toInt()}', '%'),
            _Kpi('MULTI-KILL', '${s.multiKillRounds}', ''),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Kpi('OPEN DUEL', '${s.openingDuelPercent.toInt()}', '%'),
            _Kpi('DUEL WIN', '${s.openingDuelWinPercent.toInt()}', '%'),
            _Kpi('ROUND WIN', '${s.roundWinProbability.toInt()}', '%'),
          ],
        ),
        const SizedBox(height: 10),
        const _NeedsEvents(),
      ],
    );
  }
}

class _ConsistencyContent extends StatelessWidget {
  final SessionStats s;
  const _ConsistencyContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _GaugeBlock('Confidence', s.confidenceScore)),
            const SizedBox(width: 8),
            Expanded(child: _GaugeBlock('Consistency', s.consistencyScore)),
            const SizedBox(width: 8),
            Expanded(child: _GaugeBlock('Fatigue', s.fatigueScore)),
          ],
        ),
        const SizedBox(height: 12),
        const _Label('SPEED TREND'),
        const SizedBox(height: 4),
        _Spark(data: s.speedHistory, maxVal: 300, height: 36),
        const SizedBox(height: 8),
        const _Label('STRAFE SYNC TREND'),
        const SizedBox(height: 4),
        _Spark(
          data: s.strafeSyncHistory,
          maxVal: 100,
          height: 36,
          color: BiobaseColors.live,
        ),
        const SizedBox(height: 8),
        const _Label('COUNTER-STRAFE TREND'),
        const SizedBox(height: 4),
        _Spark(
          data: s.counterStrafeHistory,
          maxVal: 100,
          height: 36,
          color: BiobaseColors.warning,
        ),
        const SizedBox(height: 8),
        const _Label('PATH EFFICIENCY TREND'),
        const SizedBox(height: 4),
        _Spark(
          data: s.pathEfficiencyHistory,
          maxVal: 100,
          height: 36,
          color: const Color(0xFF8B5CF6),
        ),
      ],
    );
  }
}

class _MechanicsContent extends StatelessWidget {
  final SessionStats s;
  const _MechanicsContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('STRAFING'),
        const SizedBox(height: 6),
        _HBar('Strafe Sync', s.strafeSyncPercent),
        _HBar('Air Strafe Eff.', s.airStrafeEfficiency),
        _HBar('Counter-strafe', s.counterStrafeAccuracy),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('STOP TIME', s.counterStrafeStopTime.toStringAsFixed(0), 'ms'),
            _Kpi('FULL ACC', s.timeToFullAccuracy.toStringAsFixed(0), 'ms'),
            _Kpi('AIR ACCEL+', '+${s.airAccelerationGained.toInt()}', ''),
            _Kpi('AIR ACCEL−', '−${s.airAccelerationLost.toInt()}', ''),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('STRAFE SYNC TREND'),
        const SizedBox(height: 4),
        _Spark(
          data: s.strafeSyncHistory,
          maxVal: 100,
          height: 36,
          color: BiobaseColors.live,
        ),
        const SizedBox(height: 12),
        const _Label('JUMPING'),
        const SizedBox(height: 6),
        Row(
          children: [
            _Kpi('JUMPS', '${s.jumpCount}', ''),
            _Kpi('PERFECT', '${s.perfectJumps}', ''),
            _Kpi('PERFECT %', '${s.perfectJumpPercent.toInt()}', '%'),
            _Kpi('TIMING', '${(s.jumpTimingConsistency * 100).toInt()}', '%'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Kpi('BHOP ATT', '${s.bhopAttemptCount}', ''),
            _Kpi('BHOP OK', '${s.bhopSuccessCount}', ''),
            _Kpi('BHOP %', '${s.bhopSuccessRate.toInt()}', '%'),
            _Kpi('CHAIN MAX', '${s.consecutiveBhopsMax}', ''),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Kpi(
              'LANDING RET.',
              '${(s.landingSpeedRetention * 100).toInt()}',
              '%',
            ),
            _Kpi('SPEED LOSS', '${s.speedLossOnLanding.toInt()}', 'u/s'),
          ],
        ),
      ],
    );
  }
}

class _BiometricsContent extends StatelessWidget {
  final SessionStats s;
  const _BiometricsContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(
          Icons.sensors_outlined,
          size: 14,
          color: BiobaseColors.textTertiary,
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'No biometric device is connected. Heart rate, HRV, stress, and focus remain unavailable and are excluded from scoring.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

const _releaseMetricIds = <PerformanceCategoryId, Set<String>>{
  PerformanceCategoryId.movement: {
    'velocity',
    'strafing',
    'bunny_hops',
    'counter_strafes',
    'jumps',
    'air_control',
    'positioning',
    'movement_efficiency',
  },
  PerformanceCategoryId.aim: {'crosshair_placement', 'head_level_percent'},
  PerformanceCategoryId.consistency: {
    'performance_trend',
    'movement_consistency',
    'confidence_score',
    'fatigue_score',
  },
  PerformanceCategoryId.mechanicalExecution: {
    'accuracy_recovery',
    'input_efficiency',
  },
};

class _MetricInventory extends StatelessWidget {
  final List<PerformanceMetricDefinition> metrics;
  final CategoryAssessment assessment;

  const _MetricInventory({required this.metrics, required this.assessment});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _Label('FULL METRIC INVENTORY'),
            const Spacer(),
            Text(
              metrics.length.toString() + ' metrics',
              style: const TextStyle(
                fontSize: 9,
                color: BiobaseColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 620
                ? 3
                : 2;
            final width =
                (constraints.maxWidth - ((columns - 1) * 6)) / columns;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: metrics
                  .map(
                    (metric) => SizedBox(
                      width: width,
                      child: _MetricInventoryRow(
                        metric: metric,
                        assessment: assessment,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _MetricInventoryRow extends StatelessWidget {
  final PerformanceMetricDefinition metric;
  final CategoryAssessment assessment;

  const _MetricInventoryRow({required this.metric, required this.assessment});

  @override
  Widget build(BuildContext context) {
    final supported =
        assessment.available &&
        (_releaseMetricIds[assessment.id]?.contains(metric.id) ?? false);
    final label = supported ? assessment.stateLabel : 'Not measured';
    final color = supported
        ? BiobaseColors.warning
        : BiobaseColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: BiobaseColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              metric.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                color: BiobaseColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════
// SHARED VISUALIZATION WIDGETS
// ════════════════════════════════════════

Color _scoreColor(double score) {
  if (score <= 0) return BiobaseColors.textTertiary;
  if (score >= 80) return BiobaseColors.live;
  if (score >= 60) return BiobaseColors.accent;
  if (score >= 40) return BiobaseColors.warning;
  return BiobaseColors.error;
}

Color _barColor(double pct) {
  if (pct >= 70) return BiobaseColors.live;
  if (pct >= 40) return BiobaseColors.accent;
  if (pct > 0) return BiobaseColors.warning;
  return BiobaseColors.surfaceRaised;
}

String _fd(double d) {
  if (d >= 10000) return '${(d / 1000).toStringAsFixed(0)}k';
  if (d >= 1000) return '${(d / 1000).toStringAsFixed(1)}k';
  return d.toInt().toString();
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _Kpi(this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: BiobaseColors.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: unit,
                      style: const TextStyle(
                        fontSize: 10,
                        color: BiobaseColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: BiobaseColors.textTertiary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: BiobaseColors.textTertiary,
      ),
    );
  }
}

class _HBar extends StatelessWidget {
  final String label;
  final double percent;
  const _HBar(this.label, this.percent);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: BiobaseColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1.5),
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  backgroundColor: BiobaseColors.surfaceRaised,
                  valueColor: AlwaysStoppedAnimation(
                    _barColor(percent).withAlpha(180),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              '${percent.toInt()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: BiobaseColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugeBlock extends StatelessWidget {
  final String label;
  final double value;
  const _GaugeBlock(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _ArcGaugePainter(
                value: (value / 100).clamp(0.0, 1.0),
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: BiobaseColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  final List<double> data;
  final double maxVal;
  final double height;
  final Color color;

  const _Spark({
    required this.data,
    required this.maxVal,
    this.height = 40,
    this.color = BiobaseColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        child: CustomPaint(
          size: Size(double.infinity, height),
          painter: _SparkPainter(data: data, maxVal: maxVal, color: color),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> data;
  final double maxVal;
  final Color color;

  _SparkPainter({
    required this.data,
    required this.maxVal,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = BiobaseColors.surfaceRaised.withAlpha(60)
        ..strokeWidth = 0.5,
    );

    if (data.isEmpty) return;
    final n = data.length;
    final d = max(1, n - 1).toDouble();

    final path = Path();
    final fill = Path();
    for (int i = 0; i < n; i++) {
      final x = (i / d) * size.width;
      final y = size.height - (data[i] / maxVal).clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(((n - 1) / d) * size.width, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(25), color.withAlpha(2)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    final lx = ((n - 1) / d) * size.width;
    final ly = size.height - (data.last / maxVal).clamp(0.0, 1.0) * size.height;
    canvas.drawCircle(Offset(lx, ly), 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      data.length != old.data.length;
}

class _NeedsEvents extends StatelessWidget {
  const _NeedsEvents();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BiobaseColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 12,
            color: BiobaseColors.textTertiary.withAlpha(100),
          ),
          const SizedBox(width: 6),
          const Text(
            'Populates with game event integration',
            style: TextStyle(fontSize: 10, color: BiobaseColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Gauge Painters ──

class _ArcGaugePainter extends CustomPainter {
  final double value;
  final double fontSize;
  _ArcGaugePainter({required this.value, this.fontSize = 14});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 3;
    const startAngle = 0.75 * pi;
    const sweepTotal = 1.5 * pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = BiobaseColors.surfaceRaised
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * value,
        false,
        Paint()
          ..color = _scoreColor(value * 100)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: '${(value * 100).toInt()}',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: BiobaseColors.text,
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter old) => value != old.value;
}

class _MiniGaugePainter extends CustomPainter {
  final double value;
  _MiniGaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 2;
    const startAngle = 0.75 * pi;
    const sweepTotal = 1.5 * pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = BiobaseColors.surfaceRaised
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * value,
        false,
        Paint()
          ..color = _scoreColor(value * 100)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    final pct = (value * 100).toInt();
    final tp = TextPainter(
      text: TextSpan(
        text: pct > 0 ? '$pct' : '—',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: pct > 0 ? BiobaseColors.text : BiobaseColors.textTertiary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniGaugePainter old) => value != old.value;
}
