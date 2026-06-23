class SessionStats {
  // ── Movement ──
  double speedCurrent = 0;
  double speedMax = 0;
  double speedAvg = 0;
  double speedMin = double.infinity;
  String movementState = 'STILL';
  double distanceTraveled = 0;
  double pathEfficiency = 0;
  int groundSamples = 0;
  int airSamples = 0;
  int totalSamples = 0;
  double airTimePercent = 0;

  // ── Jumping ──
  int jumpCount = 0;
  int perfectJumps = 0;
  double perfectJumpPercent = 0;
  double jumpTimingConsistency = 0;
  int bhopSuccessCount = 0;
  int bhopAttemptCount = 0;
  double bhopSuccessRate = 0;
  int consecutiveBhopsMax = 0;
  int consecutiveBhopsCurrent = 0;

  // ── Air & Strafe ──
  double airStrafeEfficiency = 0;
  double strafeSyncPercent = 0;
  double airAccelerationGained = 0;
  double airAccelerationLost = 0;
  double landingSpeedRetention = 0;
  double speedLossOnLanding = 0;

  // ── Counter-strafe ──
  double counterStrafeAccuracy = 0;
  double counterStrafeStopTime = 0;
  double timeToFullAccuracy = 0;

  // ── Peeking ──
  int peekCount = 0;
  int widePeekCount = 0;
  int jigglePeekCount = 0;
  int shoulderPeekCount = 0;
  int rePeekCount = 0;
  double peekSuccessRate = 0;

  // ── Combat ──
  int entryAttempts = 0;
  int entrySuccesses = 0;
  double entrySuccessRate = 0;
  int tradeOpportunities = 0;
  int successfulTrades = 0;
  int tradeDeaths = 0;
  double tradeTime = 0;
  double timeAlive = 0;
  double survivalRate = 0;

  // ── Damage ──
  int damageDealt = 0;
  int damageReceived = 0;
  double damagePerRound = 0;
  int utilityDamage = 0;

  // ── Accuracy ──
  double headshotPercent = 0;
  double firstBulletAccuracy = 0;
  double sprayAccuracy = 0;
  double sprayTransferSuccess = 0;
  double burstAccuracy = 0;
  double tapAccuracy = 0;
  int missedShots = 0;
  double timeToFirstShot = 0;
  double timeToFirstDamage = 0;
  double timeToFirstKill = 0;
  double timeToKill = 0;
  double timeToDeath = 0;

  // ── Crosshair ──
  double crosshairPlacementError = 0;
  double crosshairHeadLevelPercent = 0;
  double crosshairTravelDistance = 0;
  double flickDistance = 0;
  double flickAccuracy = 0;
  double preAimAccuracy = 0;
  double reactionTime = 0;
  double enemyVisibleBeforeFiring = 0;
  double angleHoldDuration = 0;
  double angleWinRate = 0;
  double crosshairIdleTime = 0;
  double crosshairOffTargetTime = 0;

  // ── Utility ──
  double flashEffectiveness = 0;
  double flashBlindnessDuration = 0;
  int enemiesFlashed = 0;
  int teammatesFlashed = 0;
  double smokeEffectiveness = 0;
  double molotovEffectiveness = 0;
  double heEffectiveness = 0;
  double utilityUsageEfficiency = 0;
  double grenadeLineupSuccess = 0;

  // ── Economy ──
  int equipmentValue = 0;
  String economyState = '—';

  // ── Timing ──
  int footstepCount = 0;
  int weaponSwitchCount = 0;
  double reloadTiming = 0;
  int reloadCancelCount = 0;

  // ── Performance ──
  double roundWinProbability = 0;
  int clutchAttempts = 0;
  double clutchSuccessPercent = 0;
  double openingDuelPercent = 0;
  double openingDuelWinPercent = 0;
  int multiKillRounds = 0;
  double adr = 0;
  double kast = 0;
  double hltvRating = 0;

  // ── Positioning ──
  double timeExposed = 0;
  double timeInCover = 0;
  double rotationTiming = 0;
  double rotationEfficiency = 0;
  double decisionLatency = 0;
  double teamSpacing = 0;
  double nearestTeammateDistance = 0;
  int isolationDeaths = 0;

  // ── Scores ──
  double fatigueScore = 0;
  double confidenceScore = 0;
  double consistencyScore = 0;

  // ── Trends (last N values for sparklines) ──
  final List<double> speedHistory = [];
  final List<double> strafeSyncHistory = [];
  final List<double> counterStrafeHistory = [];
  final List<double> pathEfficiencyHistory = [];

  double get speedAvgSafe => totalSamples > 0 ? speedAvg : 0;
  double get speedMinSafe =>
      speedMin == double.infinity ? 0 : speedMin;

  // ── Category Scores (0–100) ──

  double get movementScore {
    if (totalSamples == 0) return 0;
    final s = (speedAvgSafe / 250).clamp(0.0, 1.0);
    final p = pathEfficiency.clamp(0.0, 1.0);
    final a = (airTimePercent / 30).clamp(0.0, 1.0);
    return (s * 40 + p * 40 + a * 20).clamp(0.0, 100.0);
  }

  double get aimScore {
    if (crosshairHeadLevelPercent == 0 && firstBulletAccuracy == 0) return 0;
    return crosshairHeadLevelPercent.clamp(0.0, 100.0);
  }

  double get combatScore {
    if (entryAttempts == 0 && damageDealt == 0) return 0;
    return entrySuccessRate.clamp(0.0, 100.0);
  }

  double get utilityScore {
    final t = flashEffectiveness + smokeEffectiveness +
        molotovEffectiveness + heEffectiveness;
    if (t == 0) return 0;
    return (t / 4).clamp(0.0, 100.0);
  }

  double get positioningScore {
    if (peekCount == 0 && timeExposed == 0) return 0;
    return peekSuccessRate.clamp(0.0, 100.0);
  }

  double get decisionMakingScore {
    if (rotationEfficiency == 0) return 0;
    return rotationEfficiency.clamp(0.0, 100.0);
  }

  double get economyScore => 0;
  double get teamplayScore => 0;

  double get roundPerformanceScore {
    if (hltvRating == 0) return 0;
    return (hltvRating * 50).clamp(0.0, 100.0);
  }

  double get consistencyScoreCategory =>
      consistencyScore.clamp(0.0, 100.0);

  double get mechanicalExecutionScore {
    if (totalSamples == 0) return 0;
    final vals = [
      strafeSyncPercent, counterStrafeAccuracy,
      bhopSuccessRate, perfectJumpPercent,
    ];
    final active = vals.where((v) => v > 0);
    if (active.isEmpty) return 0;
    return (active.reduce((a, b) => a + b) / active.length)
        .clamp(0.0, 100.0);
  }

  double get biometricsScore {
    if (totalSamples == 0) return 0;
    return (100 - fatigueScore).clamp(0.0, 100.0);
  }

  double get overallScore {
    final scores = categoryScores;
    final active = scores.where((s) => s > 0).toList();
    if (active.isEmpty) return 0;
    return active.reduce((a, b) => a + b) / active.length;
  }

  List<double> get categoryScores => [
        movementScore, aimScore, combatScore, utilityScore,
        positioningScore, decisionMakingScore, economyScore,
        teamplayScore, roundPerformanceScore, consistencyScoreCategory,
        mechanicalExecutionScore, biometricsScore,
      ];
}
