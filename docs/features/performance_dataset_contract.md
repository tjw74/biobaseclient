# BioBase Performance Dataset Contract v1

The machine-readable contract is
[`performance_dataset_contract_v1.json`](performance_dataset_contract_v1.json).
It is the stable release boundary between telemetry, analytics, persistence,
and the Flutter Performance Review.

## Release rules

- Category IDs and order are stable; labels may evolve without changing IDs.
- Every displayed category declares an evidence state: `observed`, `derived`,
  or `unavailable`.
- Derived results require a confidence value and a human-readable source.
- Unavailable categories show `Not measured`; they never render as a zero and
  are excluded from category and overall scores.
- Replay-derived results must preserve tick or time alignment.
- Biometric scores require a biometric device stream. Movement-based fatigue
  estimates must not be presented as biometric evidence.

## Initial release coverage

- Movement: derived from live server position and velocity telemetry.
- Aim: limited estimate from view orientation; shot/target validation is still
  required before presenting full aim accuracy.
- Consistency: derived from the current movement sample window.
- Mechanical Execution: limited to movement mechanics until input and weapon
  events are connected.
- Combat, Utility, Positioning, Decision Making, Teamplay, Economy, Round
  Performance, and Biometrics remain explicitly unavailable until their
  required data sources are connected.

The central client API persists authenticated session payloads in SQLite and
returns device-scoped history through `POST/GET /api/client/sessions`.
