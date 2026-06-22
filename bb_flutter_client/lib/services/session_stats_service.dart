import 'dart:math';
import '../models.dart';
import '../models/session_stats.dart';

class SessionStatsService {
  final SessionStats stats = SessionStats();

  LiveMovementSample? _prev;
  bool _prevOnGround = true;
  double _lastAirSpeed = 0;
  int _bhopChain = 0;
  int _ticksSinceLastLanding = 0;
  double _speedSum = 0;
  double _strafeSyncHits = 0;
  double _strafeSyncTotal = 0;
  double _csSum = 0;
  double _peSum = 0;
  int _headLevelSamples = 0;
  double _prevYaw = 0;
  double _prevPitch = 0;
  double _yawStableTime = 0;
  double _yawStableSum = 0;
  int _yawStableCount = 0;

  void processSample(LiveMovementSample s) {
    stats.totalSamples++;
    stats.speedCurrent = s.speed;

    if (s.speed > stats.speedMax) stats.speedMax = s.speed;
    if (s.speed < stats.speedMin) stats.speedMin = s.speed;
    _speedSum += s.speed;
    stats.speedAvg = _speedSum / stats.totalSamples;

    // Movement state
    if (!s.onGround) {
      stats.movementState = 'AIRBORNE';
    } else if (s.keys.crouch && s.speed < 80) {
      stats.movementState = 'CROUCHING';
    } else if (s.speed >= 200) {
      stats.movementState = 'RUNNING';
    } else if (s.speed >= 50) {
      stats.movementState = 'WALKING';
    } else {
      stats.movementState = 'STILL';
    }

    // Ground / air
    if (s.onGround) {
      stats.groundSamples++;
    } else {
      stats.airSamples++;
    }
    stats.airTimePercent = stats.totalSamples > 0
        ? (stats.airSamples / stats.totalSamples) * 100
        : 0;

    // Distance
    if (_prev != null) {
      final dx = s.pos[0] - _prev!.pos[0];
      final dy = s.pos[1] - _prev!.pos[1];
      final dz = s.pos[2] - _prev!.pos[2];
      stats.distanceTraveled += sqrt(dx * dx + dy * dy + dz * dz);
    }

    // Jump detection
    if (_prevOnGround && !s.onGround) {
      stats.jumpCount++;
      _lastAirSpeed = s.speed;
      _ticksSinceLastLanding++;

      // Bhop: jumped within 2 ticks of landing
      if (_ticksSinceLastLanding <= 4) {
        stats.bhopAttemptCount++;
        if (s.speed > 200) {
          stats.bhopSuccessCount++;
          _bhopChain++;
          if (_bhopChain > stats.consecutiveBhopsMax) {
            stats.consecutiveBhopsMax = _bhopChain;
          }
          stats.consecutiveBhopsCurrent = _bhopChain;
        } else {
          _bhopChain = 0;
          stats.consecutiveBhopsCurrent = 0;
        }
      } else {
        _bhopChain = 0;
        stats.consecutiveBhopsCurrent = 0;
      }

      // Perfect jump: speed maintained or gained
      if (_prev != null && s.speed >= _prev!.speed * 0.95) {
        stats.perfectJumps++;
      }
    }

    // Landing detection
    if (!_prevOnGround && s.onGround) {
      _ticksSinceLastLanding = 0;
      final landingSpeed = s.speed;
      if (_lastAirSpeed > 0) {
        stats.landingSpeedRetention = landingSpeed / _lastAirSpeed;
        stats.speedLossOnLanding = _lastAirSpeed - landingSpeed;
      }
    } else {
      _ticksSinceLastLanding++;
    }

    stats.perfectJumpPercent = stats.jumpCount > 0
        ? (stats.perfectJumps / stats.jumpCount) * 100
        : 0;
    stats.bhopSuccessRate = stats.bhopAttemptCount > 0
        ? (stats.bhopSuccessCount / stats.bhopAttemptCount) * 100
        : 0;

    // Strafe sync (airborne: key direction matches velocity change direction)
    if (!s.onGround && _prev != null) {
      _strafeSyncTotal++;
      final velChange = s.velX - _prev!.velX;
      final strafingRight = s.keys.d && !s.keys.a;
      final strafingLeft = s.keys.a && !s.keys.d;
      if ((strafingRight && velChange > 0) ||
          (strafingLeft && velChange < 0)) {
        _strafeSyncHits++;
      }
    }
    stats.strafeSyncPercent = _strafeSyncTotal > 0
        ? (_strafeSyncHits / _strafeSyncTotal) * 100
        : 0;

    // Air acceleration tracking
    if (!s.onGround && _prev != null && !_prevOnGround) {
      final accel = s.speed - _prev!.speed;
      if (accel > 0) {
        stats.airAccelerationGained += accel;
      } else {
        stats.airAccelerationLost += accel.abs();
      }
    }

    // Air strafe efficiency
    final totalAirAccel =
        stats.airAccelerationGained + stats.airAccelerationLost;
    stats.airStrafeEfficiency = totalAirAccel > 0
        ? (stats.airAccelerationGained / totalAirAccel) * 100
        : 0;

    // Counter-strafe
    _csSum += s.counterStrafeScore;
    stats.counterStrafeAccuracy =
        (_csSum / stats.totalSamples) * 100;

    // Path efficiency
    _peSum += s.pathEfficiency;
    stats.pathEfficiency = _peSum / stats.totalSamples;

    // Crosshair tracking
    if (_prev != null) {
      final yawDelta = (s.yaw - _prevYaw).abs();
      final pitchDelta = (s.pitch - _prevPitch).abs();
      final travel =
          sqrt(yawDelta * yawDelta + pitchDelta * pitchDelta);
      stats.crosshairTravelDistance += travel;

      // Flick detection (large movement in single tick)
      if (travel > 15) {
        stats.flickDistance += travel;
      }

      // Angle hold (yaw stable within 3 degrees)
      if (yawDelta < 3) {
        _yawStableTime += 0.5; // 500ms per sample
        _yawStableSum += _yawStableTime;
        _yawStableCount++;
      } else {
        _yawStableTime = 0;
      }
      stats.angleHoldDuration = _yawStableCount > 0
          ? _yawStableSum / _yawStableCount
          : 0;
    }

    // Head-level crosshair (pitch between -5 and 5 degrees ≈ head level)
    if (s.pitch.abs() < 8) {
      _headLevelSamples++;
    }
    stats.crosshairHeadLevelPercent = stats.totalSamples > 0
        ? (_headLevelSamples / stats.totalSamples) * 100
        : 0;

    // Trend history (keep last 60 samples for sparklines)
    stats.speedHistory.add(s.speed);
    if (stats.speedHistory.length > 60) {
      stats.speedHistory.removeAt(0);
    }
    stats.strafeSyncHistory.add(stats.strafeSyncPercent);
    if (stats.strafeSyncHistory.length > 60) {
      stats.strafeSyncHistory.removeAt(0);
    }
    stats.counterStrafeHistory.add(s.counterStrafeScore * 100);
    if (stats.counterStrafeHistory.length > 60) {
      stats.counterStrafeHistory.removeAt(0);
    }
    stats.pathEfficiencyHistory.add(s.pathEfficiency * 100);
    if (stats.pathEfficiencyHistory.length > 60) {
      stats.pathEfficiencyHistory.removeAt(0);
    }

    // Composite scores
    _computeScores();

    _prevYaw = s.yaw;
    _prevPitch = s.pitch;
    _prevOnGround = s.onGround;
    _prev = s;
  }

  void _computeScores() {
    // Consistency: inverse of speed variance (normalized)
    if (stats.speedHistory.length > 10) {
      final avg = stats.speedAvg;
      if (avg > 0) {
        double variance = 0;
        for (final s in stats.speedHistory) {
          variance += (s - avg) * (s - avg);
        }
        variance /= stats.speedHistory.length;
        stats.consistencyScore =
            ((1 - sqrt(variance) / avg) * 100).clamp(0, 100);
      }
    }

    // Confidence: composite of speed + strafe sync + counter-strafe
    stats.confidenceScore = (
        (stats.speedAvg / 250 * 30).clamp(0.0, 30.0) +
        (stats.strafeSyncPercent * 0.35).clamp(0.0, 35.0) +
        (stats.counterStrafeAccuracy * 0.35).clamp(0.0, 35.0)
    ).clamp(0.0, 100.0);

    // Fatigue: degrades as consistency drops over time
    if (stats.speedHistory.length > 30) {
      final recent = stats.speedHistory.sublist(
          stats.speedHistory.length - 15);
      final earlier = stats.speedHistory.sublist(0, 15);
      final recentAvg =
          recent.reduce((a, b) => a + b) / recent.length;
      final earlierAvg =
          earlier.reduce((a, b) => a + b) / earlier.length;
      if (earlierAvg > 0) {
        stats.fatigueScore =
            ((1 - recentAvg / earlierAvg) * 100).clamp(0, 100);
      }
    }
  }

  void reset() {
    final s = stats;
    s.speedCurrent = 0;
    s.speedMax = 0;
    s.speedAvg = 0;
    s.speedMin = double.infinity;
    s.totalSamples = 0;
    s.groundSamples = 0;
    s.airSamples = 0;
    s.jumpCount = 0;
    s.perfectJumps = 0;
    s.bhopSuccessCount = 0;
    s.bhopAttemptCount = 0;
    s.consecutiveBhopsMax = 0;
    s.distanceTraveled = 0;
    s.crosshairTravelDistance = 0;
    s.speedHistory.clear();
    s.strafeSyncHistory.clear();
    s.counterStrafeHistory.clear();
    s.pathEfficiencyHistory.clear();
    _speedSum = 0;
    _strafeSyncHits = 0;
    _strafeSyncTotal = 0;
    _csSum = 0;
    _peSum = 0;
    _headLevelSamples = 0;
    _prev = null;
    _prevOnGround = true;
  }
}
