# Biobase Performance Dataset Categories

Updated: 2026-06-22T22:15:47Z

These are the canonical pro-player performance categories and metrics for Biobase.

### Movement

- Velocity
- Strafing
- Bunny hops
- Counter-strafes
- Jumps
- Air control
- Positioning
- Movement efficiency
### Aim

- Crosshair placement
- Head-level %
- Flick accuracy
- Spray control
- Spray transfer
- Burst accuracy
- Tap accuracy
- First bullet accuracy
- Crosshair travel
- Target acquisition
- Time to first shot
- Reaction time
### Combat

- Kills
- Deaths
- Assists
- ADR
- Damage dealt
- Damage taken
- Headshot %
- Opening duels
- Trade kills
- Trade deaths
- Multi-kills
- Clutches
- Time to kill
- Survival time
### Utility

- Flash effectiveness
- Teammates flashed
- Enemies flashed
- Smoke effectiveness
- Molotov effectiveness
- HE damage
- Utility damage
- Utility value per round
- Utility timing
- Lineup success
### Positioning

- Heatmaps
- Angle hold time
- Angle win rate
- Time in cover
- Time exposed
- Peek locations
- Death locations
- Kill locations
- Rotation paths
- Distance traveled
### Decision Making

- Rotate timing
- Save decisions
- Retake participation
- Entry timing
- Re-peek frequency
- Aggression score
- Risk score
- Opportunity conversion
- Decision latency
### Economy

- Buy efficiency
- Equipment value
- Weapon value
- Economy impact
- Save success
- Upgrade timing
- Cost per kill
- Cost per damage
### Teamplay

- Trade percentage
- Spacing
- Distance to teammates
- Support effectiveness
- Flash assists
- Crossfires
- Bait deaths
- Refrag timing
- Site support timing
### Round Performance

- Round impact score
- MVP rounds
- Win contribution
- Objective contribution
- Bomb plants
- Defuses
- Entry impact
- Clutch impact
- Momentum
### Consistency

- Performance trend
- Round-to-round variance
- Aim consistency
- Movement consistency
- Decision consistency
- Utility consistency
- Confidence score
- Fatigue score
- Tilt indicator
### Mechanical Execution

- Reload timing
- Weapon switching
- Scope timing
- Accuracy recovery
- Weapon handling
- Input efficiency
- Idle time
- APM (actions per minute)
### BioBase Biometrics

- Heart rate
- HRV
- Respiration
- Skin temperature
- Skin conductance (stress)
- Eye tracking
- Blink rate
- Pupil dilation
- Posture
- Hand tremor
- Muscle tension
- Fatigue
- Cognitive load
- Focus score
- Stress score

## Implementation Notes

- Store categories as stable identifiers; labels can change later, IDs should not.
- Every metric should declare source: demo parser, server telemetry, derived heuristic, manual/contextual, or biometric device.
- Every derived/heuristic metric should carry confidence.
- Every replay-linked metric should preserve tick/time alignment.
