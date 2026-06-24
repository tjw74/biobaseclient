import 'performance_contract.dart';

class PerformanceMetricDefinition {
  final String id;
  final String label;

  const PerformanceMetricDefinition(this.id, this.label);
}

const performanceMetricCatalog =
    <PerformanceCategoryId, List<PerformanceMetricDefinition>>{
      PerformanceCategoryId.movement: [
        PerformanceMetricDefinition('velocity', 'Velocity'),
        PerformanceMetricDefinition('strafing', 'Strafing'),
        PerformanceMetricDefinition('bunny_hops', 'Bunny hops'),
        PerformanceMetricDefinition('counter_strafes', 'Counter-strafes'),
        PerformanceMetricDefinition('jumps', 'Jumps'),
        PerformanceMetricDefinition('air_control', 'Air control'),
        PerformanceMetricDefinition('positioning', 'Positioning'),
        PerformanceMetricDefinition(
          'movement_efficiency',
          'Movement efficiency',
        ),
      ],
      PerformanceCategoryId.aim: [
        PerformanceMetricDefinition(
          'crosshair_placement',
          'Crosshair placement',
        ),
        PerformanceMetricDefinition('head_level_percent', 'Head-level %'),
        PerformanceMetricDefinition('flick_accuracy', 'Flick accuracy'),
        PerformanceMetricDefinition('spray_control', 'Spray control'),
        PerformanceMetricDefinition('spray_transfer', 'Spray transfer'),
        PerformanceMetricDefinition('burst_accuracy', 'Burst accuracy'),
        PerformanceMetricDefinition('tap_accuracy', 'Tap accuracy'),
        PerformanceMetricDefinition(
          'first_bullet_accuracy',
          'First-bullet accuracy',
        ),
        PerformanceMetricDefinition('crosshair_travel', 'Crosshair travel'),
        PerformanceMetricDefinition('target_acquisition', 'Target acquisition'),
        PerformanceMetricDefinition('time_to_first_shot', 'Time to first shot'),
        PerformanceMetricDefinition('reaction_time', 'Reaction time'),
      ],
      PerformanceCategoryId.combat: [
        PerformanceMetricDefinition('kills', 'Kills'),
        PerformanceMetricDefinition('deaths', 'Deaths'),
        PerformanceMetricDefinition('assists', 'Assists'),
        PerformanceMetricDefinition('adr', 'ADR'),
        PerformanceMetricDefinition('damage_dealt', 'Damage dealt'),
        PerformanceMetricDefinition('damage_taken', 'Damage taken'),
        PerformanceMetricDefinition('headshot_percent', 'Headshot %'),
        PerformanceMetricDefinition('opening_duels', 'Opening duels'),
        PerformanceMetricDefinition('trade_kills', 'Trade kills'),
        PerformanceMetricDefinition('trade_deaths', 'Trade deaths'),
        PerformanceMetricDefinition('multi_kills', 'Multi-kills'),
        PerformanceMetricDefinition('clutches', 'Clutches'),
        PerformanceMetricDefinition('time_to_kill', 'Time to kill'),
        PerformanceMetricDefinition('survival_time', 'Survival time'),
      ],
      PerformanceCategoryId.utility: [
        PerformanceMetricDefinition(
          'flash_effectiveness',
          'Flash effectiveness',
        ),
        PerformanceMetricDefinition('teammates_flashed', 'Teammates flashed'),
        PerformanceMetricDefinition('enemies_flashed', 'Enemies flashed'),
        PerformanceMetricDefinition(
          'smoke_effectiveness',
          'Smoke effectiveness',
        ),
        PerformanceMetricDefinition(
          'molotov_effectiveness',
          'Molotov effectiveness',
        ),
        PerformanceMetricDefinition('he_damage', 'HE damage'),
        PerformanceMetricDefinition('utility_damage', 'Utility damage'),
        PerformanceMetricDefinition(
          'utility_value_per_round',
          'Utility value per round',
        ),
        PerformanceMetricDefinition('utility_timing', 'Utility timing'),
        PerformanceMetricDefinition('lineup_success', 'Lineup success'),
      ],
      PerformanceCategoryId.positioning: [
        PerformanceMetricDefinition('heatmaps', 'Heatmaps'),
        PerformanceMetricDefinition('angle_hold_time', 'Angle-hold time'),
        PerformanceMetricDefinition('angle_win_rate', 'Angle win rate'),
        PerformanceMetricDefinition('time_in_cover', 'Time in cover'),
        PerformanceMetricDefinition('time_exposed', 'Time exposed'),
        PerformanceMetricDefinition('peek_locations', 'Peek locations'),
        PerformanceMetricDefinition('death_locations', 'Death locations'),
        PerformanceMetricDefinition('kill_locations', 'Kill locations'),
        PerformanceMetricDefinition('rotation_paths', 'Rotation paths'),
        PerformanceMetricDefinition('distance_traveled', 'Distance traveled'),
      ],
      PerformanceCategoryId.decisionMaking: [
        PerformanceMetricDefinition('rotate_timing', 'Rotate timing'),
        PerformanceMetricDefinition('save_decisions', 'Save decisions'),
        PerformanceMetricDefinition(
          'retake_participation',
          'Retake participation',
        ),
        PerformanceMetricDefinition('entry_timing', 'Entry timing'),
        PerformanceMetricDefinition('re_peek_frequency', 'Re-peek frequency'),
        PerformanceMetricDefinition('aggression_score', 'Aggression score'),
        PerformanceMetricDefinition('risk_score', 'Risk score'),
        PerformanceMetricDefinition(
          'opportunity_conversion',
          'Opportunity conversion',
        ),
        PerformanceMetricDefinition('decision_latency', 'Decision latency'),
      ],
      PerformanceCategoryId.teamplay: [
        PerformanceMetricDefinition('trade_percentage', 'Trade percentage'),
        PerformanceMetricDefinition('spacing', 'Spacing'),
        PerformanceMetricDefinition(
          'distance_to_teammates',
          'Distance to teammates',
        ),
        PerformanceMetricDefinition(
          'support_effectiveness',
          'Support effectiveness',
        ),
        PerformanceMetricDefinition('flash_assists', 'Flash assists'),
        PerformanceMetricDefinition('crossfires', 'Crossfires'),
        PerformanceMetricDefinition('bait_deaths', 'Bait deaths'),
        PerformanceMetricDefinition('refrag_timing', 'Refrag timing'),
        PerformanceMetricDefinition(
          'site_support_timing',
          'Site-support timing',
        ),
      ],
      PerformanceCategoryId.economy: [
        PerformanceMetricDefinition('buy_efficiency', 'Buy efficiency'),
        PerformanceMetricDefinition('equipment_value', 'Equipment value'),
        PerformanceMetricDefinition('weapon_value', 'Weapon value'),
        PerformanceMetricDefinition('economy_impact', 'Economy impact'),
        PerformanceMetricDefinition('save_success', 'Save success'),
        PerformanceMetricDefinition('upgrade_timing', 'Upgrade timing'),
        PerformanceMetricDefinition('cost_per_kill', 'Cost per kill'),
        PerformanceMetricDefinition('cost_per_damage', 'Cost per damage'),
      ],
      PerformanceCategoryId.roundPerformance: [
        PerformanceMetricDefinition('round_impact_score', 'Round-impact score'),
        PerformanceMetricDefinition('mvp_rounds', 'MVP rounds'),
        PerformanceMetricDefinition('win_contribution', 'Win contribution'),
        PerformanceMetricDefinition(
          'objective_contribution',
          'Objective contribution',
        ),
        PerformanceMetricDefinition('bomb_plants', 'Bomb plants'),
        PerformanceMetricDefinition('defuses', 'Defuses'),
        PerformanceMetricDefinition('entry_impact', 'Entry impact'),
        PerformanceMetricDefinition('clutch_impact', 'Clutch impact'),
        PerformanceMetricDefinition('momentum', 'Momentum'),
      ],
      PerformanceCategoryId.consistency: [
        PerformanceMetricDefinition('performance_trend', 'Performance trend'),
        PerformanceMetricDefinition(
          'round_to_round_variance',
          'Round-to-round variance',
        ),
        PerformanceMetricDefinition('aim_consistency', 'Aim consistency'),
        PerformanceMetricDefinition(
          'movement_consistency',
          'Movement consistency',
        ),
        PerformanceMetricDefinition(
          'decision_consistency',
          'Decision consistency',
        ),
        PerformanceMetricDefinition(
          'utility_consistency',
          'Utility consistency',
        ),
        PerformanceMetricDefinition('confidence_score', 'Confidence score'),
        PerformanceMetricDefinition('fatigue_score', 'Fatigue score'),
        PerformanceMetricDefinition('tilt_indicator', 'Tilt indicator'),
      ],
      PerformanceCategoryId.mechanicalExecution: [
        PerformanceMetricDefinition('reload_timing', 'Reload timing'),
        PerformanceMetricDefinition('weapon_switching', 'Weapon switching'),
        PerformanceMetricDefinition('scope_timing', 'Scope timing'),
        PerformanceMetricDefinition('accuracy_recovery', 'Accuracy recovery'),
        PerformanceMetricDefinition('weapon_handling', 'Weapon handling'),
        PerformanceMetricDefinition('input_efficiency', 'Input efficiency'),
        PerformanceMetricDefinition('idle_time', 'Idle time'),
        PerformanceMetricDefinition('actions_per_minute', 'Actions per minute'),
      ],
      PerformanceCategoryId.biometrics: [
        PerformanceMetricDefinition('heart_rate', 'Heart rate'),
        PerformanceMetricDefinition('hrv', 'Heart-rate variability'),
        PerformanceMetricDefinition('respiration', 'Respiration'),
        PerformanceMetricDefinition('skin_temperature', 'Skin temperature'),
        PerformanceMetricDefinition('skin_conductance', 'Skin conductance'),
        PerformanceMetricDefinition('eye_tracking', 'Eye tracking'),
        PerformanceMetricDefinition('blink_rate', 'Blink rate'),
        PerformanceMetricDefinition('pupil_dilation', 'Pupil dilation'),
        PerformanceMetricDefinition('posture', 'Posture'),
        PerformanceMetricDefinition('hand_tremor', 'Hand tremor'),
        PerformanceMetricDefinition('muscle_tension', 'Muscle tension'),
        PerformanceMetricDefinition('fatigue', 'Fatigue'),
        PerformanceMetricDefinition('cognitive_load', 'Cognitive load'),
        PerformanceMetricDefinition('focus_score', 'Focus score'),
        PerformanceMetricDefinition('stress_score', 'Stress score'),
      ],
    };
