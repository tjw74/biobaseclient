---
title: >-
  BioBase CS2 telemetry + demo reconciliation
category: concepts
tags: [cs2, telemetry, reconciliation, faceit, demos]
sources: [projects/biobase]
summary: >-
  Versioned JSON flush bundle (v1) for GAME/FACEIT-style sidecars, file-drop /
  compressed NDJSON MVP, Postgres-centric ingest noted for context, reconcile
  stub + parsers (awpy, demoparser2, demoinfocs-golang).
provenance:
  extracted: 0.55
  inferred: 0.40
  ambiguous: 0.05
created: 2026-05-13T18:55:00Z
updated: 2026-05-13T20:00:00Z
---

# BioBase CS2 telemetry & reconciliation

BioBase ingest today persists sessions and structured gameplay in Postgres (`[[biobase-telemetry-schema]]`, `[[biobase-session-ingest]]`). The **FACEIT GAME stack plus BioBase Postgres sidecar** still needs an explicit, versioned interchange so exporter output can be audited against GOTV-derived truth without blocking on new DB migrations day one.

## Architecture snapshot

```
FACEIT MATCH / GAME-plane exporters  ──┐
     │                                 ├──> ZSTD / JSON bundles (telemetry v1)
     │                                 │
     └── optional GOTV / demo artifacts ┘────────┐
                                                ▼
                        tools/biobase_demo_reconcile.py (MVP)
                                                │
Postgres ingest (existing) ◀────────────────────┘  (later HTTP / COPY jobs)
```

- **Upstream plane:** server plugins, GOTV relays, or third-party ingest agents emit flushed JSON matching `schema_version`.
- **QA plane:** deterministic bundle-to-bundle metrics before wiring heavy `.dem` pipelines.
- **Persistence plane:** today’s Postgres schemas remain authoritative for operator dashboards (`[[biobase-cs2-admin-dashboard]]`). This contract is complementary.

## Telemetry contract v1 (machine + human readable)

| Artifact | Repo path |
|----------|-----------|
| Operator narrative | `/home/clearmined/code/prod/biobase/docs/cs2/biobase-telemetry-v1.md` |
| JSON Schema | `/home/clearmined/code/prod/biobase/docs/cs2/biobase-telemetry-v1.schema.json` |
| Example bundle | `/home/clearmined/code/prod/biobase/docs/cs2/examples/minimal-bundle.json` |
| Ops pointer stub | `/home/clearmined/code/prod/biobase/bb_cs2_dashboard/.biobase/telemetry/README.md` |

Key semantic rules:

- **`schema_version`:** literal `biobase-telemetry-v1` until a breaking iteration ships.
- **`match_id`, `map`, `tickrate`, `players`, `samples`:** required baseline; recordings optional.
- **Flush transport:** ZSTD-compressed **`{match_id}.jsonl.zst`** (single-line JSON MVP) documented in the Markdown spec.

## Reconciliation tooling (MVP)

Run from repo root:

```bash
python3 tools/biobase_demo_reconcile.py \
  --telemetry docs/cs2/examples/minimal-bundle.json

python3 tools/biobase_demo_reconcile.py \
  --telemetry golden.json \
  --demo candidate.json \
  --json-out
```

- Stdlib-first validation with optional **`jsonschema`** if installed globally.
- When `--demo` targets another telemetry bundle → JSON alignment metrics (sample counts, tick overlap, SteamID overlap Jaccard, map parity).
- When `--demo` targets `.dem` → stub noting future bridge to **`bb_cs2_dashboard/parser_workers`** (awpy summary, demoparser2 worker, Go `demoinfocs_summary` binary).

Documentation cross-links remain in-repo; runtime wiring intentionally stays out of Flask/FastAPI hot paths until ingest owners define drop directories.

### Parser affinity

| Component | Repo location / notes |
|-----------|-----------------------|
| [awpy](https://github.com/pnxenopoulos/awpy) | Listed in `bb_cs2_dashboard/requirements.txt`; Python `.dem` parse path |
| `demoparser2_summary.py` | `bb_cs2_dashboard/parser_workers/` |
| demoinfocs-golang | `/home/clearmined/code/prod/biobase/bb_cs2_dashboard/demoinfocs_summary/` + packaged binary expectation |

Phase 2 work layers parsed demo ticks onto `samples[].tick` for numerical drift metrics.

## MVP roadmap bullets

1. Provision shared drop directory (`/data/telemetry/flushes/` or NFS bind) honoring `{match_id}.jsonl.zst`.
2. Add signed upload or `POST /telemetry/v1/flushes` once auth story matches hub routing (`[[biobase-hub-routing]]`).
3. Hydrate Postgres staging tables translating flush bundles → `game.*` loaders without rewriting session anchor semantics.
4. Automate nightly `.dem` reconciliation using existing dashboard subprocess harness (`demo_parser_compare.py`).
5. Publish alerting when `steam_id_jaccard` / tick overlap regress below SLA thresholds derived from QA matches.

## Risks & limitations

- **Pointer-format `samples`** (`parquet_relative`, `ndjson_relative`) are schema-valid but tooling does not dereference files yet — ship inline arrays for deterministic MVP tests only.
- **ZSTD ingestion** omitted from reconcile stub intentionally (no mandated Python dependency); decompress offline or integrate in Go/Rust ingest services.
- **Clock / tick mapping** vs GOTV demos may drift absent shared `recording_offset` metadata — backlog item before strict mm-level spatial regression.
- **FACEIT-internal identifiers** aren’t mirrored today; exporters must synthesize deterministic `match_id` values correlated with GOTV manifests.
