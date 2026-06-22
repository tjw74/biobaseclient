import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/session_stats.dart';

class ProfileScreen extends StatefulWidget {
  final SessionStats stats;
  const ProfileScreen({super.key, required this.stats});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static const _tabs = [
    'Movement',
    'Jumping',
    'Strafing',
    'Peeking',
    'Combat',
    'Accuracy',
    'Utility',
    'Economy',
    'Performance',
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 32,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: BiobaseColors.accent,
            indicatorWeight: 2,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: BiobaseColors.text,
            unselectedLabelColor: BiobaseColors.textTertiary,
            labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3),
            unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.3),
            dividerColor: Colors.transparent,
            padding: EdgeInsets.zero,
            labelPadding:
                const EdgeInsets.symmetric(horizontal: 10),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _MovementTab(s: widget.stats),
              _JumpingTab(s: widget.stats),
              _StrafingTab(s: widget.stats),
              _PeekingTab(s: widget.stats),
              _CombatTab(s: widget.stats),
              _AccuracyTab(s: widget.stats),
              _UtilityTab(s: widget.stats),
              _EconomyTab(s: widget.stats),
              _PerformanceTab(s: widget.stats),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════
// MOVEMENT TAB
// ════════════════════════════════════════

class _MovementTab extends StatelessWidget {
  final SessionStats s;
  const _MovementTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Velocity hero
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s.speedCurrent.toInt()}',
                      style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: BiobaseColors.text,
                          letterSpacing: -2,
                          height: 1)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _StatePill(s.movementState),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MiniStat('MAX', s.speedMax.toInt().toString()),
                  const SizedBox(width: 20),
                  _MiniStat(
                      'AVG', s.speedAvgSafe.toInt().toString()),
                  const SizedBox(width: 20),
                  _MiniStat(
                      'MIN', s.speedMinSafe.toInt().toString()),
                ],
              ),
              const SizedBox(height: 12),
              _Spark(data: s.speedHistory, maxVal: 300, height: 60),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _StatCard(
                    'Distance',
                    '${s.distanceTraveled.toInt()}',
                    'units')),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Path Efficiency',
                    s.pathEfficiency * 100)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Air Time', s.airTimePercent)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _StatCard('Ground Samples',
                    '${s.groundSamples}', 'ticks')),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('Air Samples',
                    '${s.airSamples}', 'ticks')),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('Total Samples',
                    '${s.totalSamples}', 'ticks')),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('SPEED TREND'),
              const SizedBox(height: 8),
              _Spark(
                  data: s.speedHistory,
                  maxVal: 300,
                  height: 80,
                  color: BiobaseColors.accent),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════
// JUMPING TAB
// ════════════════════════════════════════

class _JumpingTab extends StatelessWidget {
  final SessionStats s;
  const _JumpingTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
                child: _BigStatCard(
                    'Jumps', '${s.jumpCount}')),
            const SizedBox(width: 8),
            Expanded(
                child: _BigStatCard(
                    'Perfect', '${s.perfectJumps}')),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Perfect %', s.perfectJumpPercent)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'Bhop Rate', s.bhopSuccessRate)),
            const SizedBox(width: 8),
            Expanded(
                child: _BigStatCard('Bhop Chain',
                    '${s.consecutiveBhopsMax}')),
            const SizedBox(width: 8),
            Expanded(
                child: _BigStatCard('Current Chain',
                    '${s.consecutiveBhopsCurrent}')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _StatCard('Bhop Attempts',
                    '${s.bhopAttemptCount}', '')),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('Bhop Success',
                    '${s.bhopSuccessCount}', '')),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard('Jump Timing',
                    s.jumpTimingConsistency * 100)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _StatCard('Landing Retention',
                    '${(s.landingSpeedRetention * 100).toInt()}%',
                    '')),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('Speed Loss',
                    s.speedLossOnLanding.toInt().toString(),
                    'on landing')),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════
// STRAFING TAB
// ════════════════════════════════════════

class _StrafingTab extends StatelessWidget {
  final SessionStats s;
  const _StrafingTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'Strafe Sync', s.strafeSyncPercent)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard('Air Strafe Eff.',
                    s.airStrafeEfficiency)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard('Counter-Strafe',
                    s.counterStrafeAccuracy)),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('STRAFE SYNC TREND'),
              const SizedBox(height: 8),
              _Spark(
                  data: s.strafeSyncHistory,
                  maxVal: 100,
                  height: 60,
                  color: BiobaseColors.live),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _StatCard('Air Accel Gained',
                    '+${s.airAccelerationGained.toInt()}',
                    'u/s²')),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('Air Accel Lost',
                    '-${s.airAccelerationLost.toInt()}',
                    'u/s²')),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('COUNTER-STRAFE TREND'),
              const SizedBox(height: 8),
              _Spark(
                  data: s.counterStrafeHistory,
                  maxVal: 100,
                  height: 60,
                  color: BiobaseColors.warning),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _StatCard('Stop Time',
                    s.counterStrafeStopTime.toStringAsFixed(0),
                    'ms')),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('Full Accuracy',
                    s.timeToFullAccuracy.toStringAsFixed(0),
                    'ms')),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════
// PEEKING TAB
// ════════════════════════════════════════

class _PeekingTab extends StatelessWidget {
  final SessionStats s;
  const _PeekingTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('PEEK BREAKDOWN'),
              const SizedBox(height: 12),
              _BarRow('Total Peeks', s.peekCount, 100),
              const SizedBox(height: 6),
              _BarRow('Wide', s.widePeekCount,
                  max(1, s.peekCount)),
              const SizedBox(height: 6),
              _BarRow('Jiggle', s.jigglePeekCount,
                  max(1, s.peekCount)),
              const SizedBox(height: 6),
              _BarRow('Shoulder', s.shoulderPeekCount,
                  max(1, s.peekCount)),
              const SizedBox(height: 6),
              _BarRow('Re-peek', s.rePeekCount,
                  max(1, s.peekCount)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'Peek Success', s.peekSuccessRate)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('Exposed Time',
                    s.timeExposed.toStringAsFixed(1), 's')),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard('In Cover',
                    s.timeInCover.toStringAsFixed(1), 's')),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════
// COMBAT TAB
// ════════════════════════════════════════

class _CombatTab extends StatelessWidget {
  final SessionStats s;
  const _CombatTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('ENTRY FRAGGING'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Attempts',
                          '${s.entryAttempts}')),
                  Expanded(
                      child: _InlineStat('Success',
                          '${s.entrySuccesses}')),
                  Expanded(
                      child: _InlineStat('Rate',
                          '${s.entrySuccessRate.toInt()}%')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('TRADES'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Opportunities',
                          '${s.tradeOpportunities}')),
                  Expanded(
                      child: _InlineStat('Successful',
                          '${s.successfulTrades}')),
                  Expanded(
                      child: _InlineStat('Trade Deaths',
                          '${s.tradeDeaths}')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Trade Time',
                          '${s.tradeTime.toStringAsFixed(1)}s')),
                  Expanded(
                      child: _InlineStat('Time Alive',
                          '${s.timeAlive.toStringAsFixed(0)}s')),
                  Expanded(
                      child: _InlineStat('Survival',
                          '${s.survivalRate.toInt()}%')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('DAMAGE'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Dealt',
                          '${s.damageDealt}')),
                  Expanded(
                      child: _InlineStat('Received',
                          '${s.damageReceived}')),
                  Expanded(
                      child: _InlineStat('Per Round',
                          s.damagePerRound.toStringAsFixed(1))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Utility DMG',
                          '${s.utilityDamage}')),
                  const Expanded(child: SizedBox()),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _NeedsGameEvents(),
      ],
    );
  }
}

// ════════════════════════════════════════
// ACCURACY TAB
// ════════════════════════════════════════

class _AccuracyTab extends StatelessWidget {
  final SessionStats s;
  const _AccuracyTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'Headshot %', s.headshotPercent)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    '1st Bullet', s.firstBulletAccuracy)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Spray', s.sprayAccuracy)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'Burst', s.burstAccuracy)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Tap', s.tapAccuracy)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard('Spray Transfer',
                    s.sprayTransferSuccess)),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('CROSSHAIR'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Head Level',
                          '${s.crosshairHeadLevelPercent.toInt()}%')),
                  Expanded(
                      child: _InlineStat('Travel',
                          '${s.crosshairTravelDistance.toInt()}°')),
                  Expanded(
                      child: _InlineStat('Placement Error',
                          '${s.crosshairPlacementError.toInt()}°')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Flick Dist',
                          '${s.flickDistance.toInt()}°')),
                  Expanded(
                      child: _InlineStat('Flick Acc',
                          '${s.flickAccuracy.toInt()}%')),
                  Expanded(
                      child: _InlineStat('Pre-aim',
                          '${s.preAimAccuracy.toInt()}%')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('TIMING'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Reaction',
                          '${s.reactionTime.toInt()}ms')),
                  Expanded(
                      child: _InlineStat('→ 1st Shot',
                          '${s.timeToFirstShot.toStringAsFixed(1)}s')),
                  Expanded(
                      child: _InlineStat('→ 1st DMG',
                          '${s.timeToFirstDamage.toStringAsFixed(1)}s')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('→ 1st Kill',
                          '${s.timeToFirstKill.toStringAsFixed(1)}s')),
                  Expanded(
                      child: _InlineStat('TTK',
                          '${s.timeToKill.toStringAsFixed(2)}s')),
                  Expanded(
                      child: _InlineStat('TTD',
                          '${s.timeToDeath.toStringAsFixed(2)}s')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('ANGLES'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Hold Duration',
                          '${s.angleHoldDuration.toStringAsFixed(1)}s')),
                  Expanded(
                      child: _InlineStat('Win Rate',
                          '${s.angleWinRate.toInt()}%')),
                  Expanded(
                      child: _InlineStat('Enemy Vis.',
                          '${s.enemyVisibleBeforeFiring.toInt()}ms')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Idle Time',
                          '${s.crosshairIdleTime.toStringAsFixed(1)}s')),
                  Expanded(
                      child: _InlineStat('Off-target',
                          '${s.crosshairOffTargetTime.toStringAsFixed(1)}s')),
                  Expanded(
                      child: _InlineStat('Missed',
                          '${s.missedShots}')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _NeedsGameEvents(),
      ],
    );
  }
}

// ════════════════════════════════════════
// UTILITY TAB
// ════════════════════════════════════════

class _UtilityTab extends StatelessWidget {
  final SessionStats s;
  const _UtilityTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'Flash Eff.', s.flashEffectiveness)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Smoke Eff.', s.smokeEffectiveness)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Molly Eff.', s.molotovEffectiveness)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'HE Eff.', s.heEffectiveness)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard('Utility Usage',
                    s.utilityUsageEfficiency)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard('Lineup Acc.',
                    s.grenadeLineupSuccess)),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('FLASH STATS'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Enemies Flashed',
                          '${s.enemiesFlashed}')),
                  Expanded(
                      child: _InlineStat('Team Flashed',
                          '${s.teammatesFlashed}')),
                  Expanded(
                      child: _InlineStat('Blind Duration',
                          '${s.flashBlindnessDuration.toStringAsFixed(1)}s')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('SOUND & TIMING'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Footsteps',
                          '${s.footstepCount}')),
                  Expanded(
                      child: _InlineStat('Wep Switches',
                          '${s.weaponSwitchCount}')),
                  Expanded(
                      child: _InlineStat('Reload Cancels',
                          '${s.reloadCancelCount}')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _NeedsGameEvents(),
      ],
    );
  }
}

// ════════════════════════════════════════
// ECONOMY TAB
// ════════════════════════════════════════

class _EconomyTab extends StatelessWidget {
  final SessionStats s;
  const _EconomyTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
                child: _BigStatCard('Equipment',
                    '\$${s.equipmentValue}')),
            const SizedBox(width: 8),
            Expanded(
                child: _BigStatCard(
                    'Economy', s.economyState)),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('WEAPON USAGE'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Switches',
                          '${s.weaponSwitchCount}')),
                  Expanded(
                      child: _InlineStat('Reload Timing',
                          '${s.reloadTiming.toStringAsFixed(1)}s')),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _NeedsGameEvents(),
      ],
    );
  }
}

// ════════════════════════════════════════
// PERFORMANCE TAB
// ════════════════════════════════════════

class _PerformanceTab extends StatelessWidget {
  final SessionStats s;
  const _PerformanceTab({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Composite scores
        Row(
          children: [
            Expanded(
                child: _GaugeCard(
                    'Confidence', s.confidenceScore)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Consistency', s.consistencyScore)),
            const SizedBox(width: 8),
            Expanded(
                child: _GaugeCard(
                    'Fatigue', s.fatigueScore)),
          ],
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('RATINGS'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('HLTV Rating',
                          s.hltvRating.toStringAsFixed(2))),
                  Expanded(
                      child: _InlineStat('ADR',
                          s.adr.toStringAsFixed(1))),
                  Expanded(
                      child: _InlineStat('KAST',
                          '${s.kast.toInt()}%')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('CLUTCH & DUELS'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Clutch Attempts',
                          '${s.clutchAttempts}')),
                  Expanded(
                      child: _InlineStat('Clutch %',
                          '${s.clutchSuccessPercent.toInt()}%')),
                  Expanded(
                      child: _InlineStat('Multi-kill Rds',
                          '${s.multiKillRounds}')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Opening Duel',
                          '${s.openingDuelPercent.toInt()}%')),
                  Expanded(
                      child: _InlineStat('Duel Win',
                          '${s.openingDuelWinPercent.toInt()}%')),
                  Expanded(
                      child: _InlineStat('Round Win Prob.',
                          '${s.roundWinProbability.toInt()}%')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('POSITIONING'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Rotation',
                          '${s.rotationTiming.toStringAsFixed(1)}s')),
                  Expanded(
                      child: _InlineStat('Rotation Eff.',
                          '${s.rotationEfficiency.toInt()}%')),
                  Expanded(
                      child: _InlineStat('Decision Latency',
                          '${s.decisionLatency.toInt()}ms')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _InlineStat('Team Spacing',
                          '${s.teamSpacing.toInt()}u')),
                  Expanded(
                      child: _InlineStat('Nearest Ally',
                          '${s.nearestTeammateDistance.toInt()}u')),
                  Expanded(
                      child: _InlineStat('Isolation Deaths',
                          '${s.isolationDeaths}')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('PATH EFFICIENCY TREND'),
              const SizedBox(height: 8),
              _Spark(
                  data: s.pathEfficiencyHistory,
                  maxVal: 100,
                  height: 60,
                  color: BiobaseColors.live),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _NeedsGameEvents(),
      ],
    );
  }
}

// ════════════════════════════════════════
// SHARED WIDGETS
// ════════════════════════════════════════

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: BiobaseColors.textTertiary));
  }
}

class _StatePill extends StatelessWidget {
  final String state;
  const _StatePill(this.state);

  Color get _color {
    return switch (state) {
      'AIRBORNE' => BiobaseColors.warning,
      'RUNNING' => BiobaseColors.accent,
      'WALKING' => BiobaseColors.text,
      'CROUCHING' => BiobaseColors.textTertiary,
      _ => BiobaseColors.textTertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(state,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _color,
              letterSpacing: 0.5)),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.text,
                letterSpacing: -0.5)),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: BiobaseColors.textTertiary)),
      ],
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final String value;
  const _InlineStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BiobaseColors.text,
                letterSpacing: -0.3)),
        const SizedBox(height: 1),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: BiobaseColors.textTertiary)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _StatCard(this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: BiobaseColors.text,
                  letterSpacing: -0.5)),
          if (unit.isNotEmpty)
            Text(unit,
                style: const TextStyle(
                    fontSize: 10,
                    color: BiobaseColors.textTertiary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: BiobaseColors.textTertiary)),
        ],
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final String label;
  final String value;
  const _BigStatCard(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: BiobaseColors.text,
                  letterSpacing: -1,
                  height: 1)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: BiobaseColors.textTertiary)),
        ],
      ),
    );
  }
}

class _GaugeCard extends StatelessWidget {
  final String label;
  final double percent;
  const _GaugeCard(this.label, this.percent);

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(
              painter: _GaugePainter(
                  value: percent.clamp(0, 100) / 100),
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  color: BiobaseColors.textTertiary)),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  _GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 4;
    const startAngle = 0.75 * pi;
    const sweepTotal = 1.5 * pi;

    // Track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = BiobaseColors.surfaceRaised
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Value
    if (value > 0) {
      final color = value > 0.7
          ? BiobaseColors.live
          : value > 0.4
              ? BiobaseColors.accent
              : BiobaseColors.warning;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * value,
        false,
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Value text
    final tp = TextPainter(
      text: TextSpan(
          text: '${(value * 100).toInt()}',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: BiobaseColors.text,
              letterSpacing: -0.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      value != old.value;
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
          painter:
              _SparkPainter(data: data, maxVal: maxVal, color: color),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> data;
  final double maxVal;
  final Color color;

  _SparkPainter(
      {required this.data, required this.maxVal, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = BiobaseColors.surfaceRaised.withAlpha(80)
        ..strokeWidth = 0.5,
    );

    if (data.isEmpty) return;
    final n = data.length;
    final d = max(1, n - 1).toDouble();

    final path = Path();
    final fill = Path();
    for (int i = 0; i < n; i++) {
      final x = (i / d) * size.width;
      final y = size.height -
          (data[i] / maxVal).clamp(0.0, 1.0) * size.height;
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
          colors: [color.withAlpha(25), color.withAlpha(3)],
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

    // End dot
    final lx = ((n - 1) / d) * size.width;
    final ly = size.height -
        (data.last / maxVal).clamp(0.0, 1.0) * size.height;
    canvas.drawCircle(
        Offset(lx, ly), 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      data.length != old.data.length;
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  const _BarRow(this.label, this.value, this.maxValue);

  @override
  Widget build(BuildContext context) {
    final pct = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11, color: BiobaseColors.textTertiary)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: BiobaseColors.surfaceRaised,
                valueColor: AlwaysStoppedAnimation(
                    BiobaseColors.accent.withAlpha(160)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text('$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: BiobaseColors.text)),
        ),
      ],
    );
  }
}

class _NeedsGameEvents extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BiobaseColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: BiobaseColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 14, color: BiobaseColors.textTertiary.withAlpha(120)),
          const SizedBox(width: 8),
          const Text(
            'Combat & utility stats populate with game event integration',
            style: TextStyle(
                fontSize: 11, color: BiobaseColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
