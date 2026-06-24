# BioBase CS2 telemetry — flush bundle **v1**

Human-oriented summary for operators and tooling authors. The canonical structure is **`biobase-telemetry-v1.schema.json`** in this directory (`docs/cs2/`).

## Scope

BioBase ingest today is Postgres-centric (session anchor in `public`, RCON/logs in `ops`, parsed gameplay in `game`; see wiki [[biobase-telemetry-schema]]). This contract adds a **versioned, sidecar-friendly flush bundle** for:

- MATCH / GAME-plane stacks (FACEIT infra, GOTV relays, exporters) aligned with demos
- Offline reconciliation QA (live exporter vs replay parser)
- Future HTTP ingestion without changing Postgres row shapes on day one

`schema_version: "biobase-telemetry-v1"` is bumped only on breaking JSON changes.

## Flush bundle contents

Minimum required JSON keys:

| Field | Meaning |
|--------|---------|
| `schema_version` | Literal `biobase-telemetry-v1` |
| `match_id` | Logical match identifier (UUID string recommended) |
| `map` | Active map name (e.g. `de_dust2`) |
| `tickrate` | Nominal simulation tickrate (64 / 128 typical) |
| `players[]` | `steam_id` + `name` per connected player (+ optional slot/team) |
| `samples` | Inline per-tick array **or** pointer object (`format` + `path`) |

Optional:

- `recordings[]`: GOTV / demo fingerprints (often empty early MVP)
- `producer`: sidecar identity + semver
- `flushed_at`: wall-clock RFC3339 for traceability

Each **sample** (when inlined) minimally includes `tick` (int) + `steam_id` (string). Position / angles are optional floats for richer reconciliation.

### Samples: inline vs sidecar

- **Inline `samples`: array** — Best for demos, tests, small matches.
- **Pointer `samples` object** — For large payloads: `{ "format": "ndjson_relative", "path": "..." }`. Parquet and wide NDJSON SHOULD share the same per-row semantics as inlined items (tick + steam_id minimum); exact Parquet footer conventions are deliberately **documentation-level** until a `v2` schema pins Arrow names.

## File drop (MVP)

**Primary MVP path**: drop compressed NDJSON bundles on a shared volume or ingest spool directory.

| Convention | Meaning |
|------------|---------|
| Filename | **`{match_id}.jsonl.zst`** (`match_id` must match the JSON `match_id` field) |
| Payload | ZSTD-compressed newline-delimited JSON |
| Lines | Default **whole-bundle mode**: decompress → **exactly one** JSON object per file (formatted as JSONL single line) carrying the complete bundle including inlined `samples` **or** valid pointer `samples` |
| Alternate | **`{match_id}.telemetry.json`** — single JSON object for dev (no `.zst`) |

Processors MUST reject files whose embedded `schema_version` is unknown.

Repo pointer for operators deploying the dashboard stack: **`bb_cs2_dashboard/.biobase/telemetry/README.md`**.

## Flush contract (later HTTP)

Placeholder for symmetry with file ingestion (not implemented server-side yet):

| Item | Planned shape |
|------|----------------|
| Verb / path | `POST /telemetry/v1/flushes` (or operator-specific prefix) |
| Headers | `Content-Type: application/json` OR `application/x-ndjson` if streaming batches |
| Body | Single flush bundle matching this schema |

On accept, ingestion SHOULD store raw JSON + optionally expand pointer `samples` by copying sidecar files referenced relative to uploaded bundle roots.

## Reconciliation tooling

Minimal stub (stdlib validation):

```bash
python3 tools/biobase_demo_reconcile.py --telemetry path/to/bundle.json
```

Comparison between two telemetry bundles (golden vs candidate):

```bash
python3 tools/biobase_demo_reconcile.py --telemetry golden.json --demo candidate.json
```

`.dem` files: **phase 2** — wire `[awpy](https://github.com/pnxenopoulos/awpy)` / **`demoparser2`** summaries that already ship with `bb_cs2_dashboard`; see wiki [[biobase-cs2-telemetry-and-reconciliation]].

## Related parsers / references

| Library | Typical use |
|---------|--------------|
| [awpy](https://github.com/pnxenopoulos/awpy) | Python parses from `.dem`; present in `bb_cs2_dashboard` |
| demoparser2 (`bb_cs2_dashboard/parser_workers/`) | Python worker wrapper vs demo binaries |
| [demoinfocs-golang](https://github.com/markus-wa/demoinfocs-golang) | Go summary binary (`demoinfocs_summary`) in dashboard compose |
