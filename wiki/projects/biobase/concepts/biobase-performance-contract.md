---
title: >-
  BioBase Performance Dataset Contract
category: concepts
tags: [biobase, performance, analytics, flutter, data-contract]
sources: [projects/biobase]
summary: >-
  Versioned contract connecting telemetry, confidence-aware scoring, the Flutter Performance Review, and durable client session history.
provenance:
  extracted: 0.9
  inferred: 0.08
  ambiguous: 0.02
created: 2026-06-24T01:20:47Z
updated: 2026-06-24T01:20:47Z
---

# BioBase Performance Dataset Contract

BioBase now has a machine-readable `biobase-performance-v1` contract at
`docs/features/performance_dataset_contract_v1.json`. It fixes the stable
category IDs, category order, metric source vocabulary, and evidence states
used by the release client.

## Trust rules

- A displayed result is `observed`, `derived`, or `unavailable`.
- Derived results include confidence and a readable source description.
- Unavailable categories render as **Not measured**, never as a numeric zero,
  and are excluded from the overall score.
- Replay-derived metrics retain tick or time alignment.
- Biometrics require a real biometric device stream; movement fatigue
  estimates cannot be labeled biometric evidence.

## Initial Flutter coverage

The shipped Flutter Performance Review calculates confidence-weighted results
only from categories supported by current data. Movement, limited aim
orientation, short-window consistency, and movement mechanics can be derived
from the live movement feed. Combat, Utility, Positioning, Decision Making,
Teamplay, Economy, Round Performance, and Biometrics remain visibly
unavailable until their source pipelines are connected.

## Session persistence

Paired clients can store and retrieve device-scoped session payloads through
`POST /api/client/sessions` and `GET /api/client/sessions`. The dashboard
backend stores these records in SQLite under `BB_CLIENT_DATA_DIR`, replacing
the previous append-only JSONL sink for new uploads.

## Related

- [[biobase-performance-dataset-roadmap]]
- [[biobase-performance-review-ui-doctrine]]
- [[biobase-windows-client-primary-ui]]
- [[biobase-cs2-telemetry-and-reconciliation]]
