#!/usr/bin/env python3
"""
MVP reconcile / inspection stub for BioBase CS2 telemetry flush bundles (schema v1).

- Validates telemetry JSON (stdlib only; optionally jsonschema when installed).
- Summarizes match_id, roster, sample ticks.
- Without --demo: prints "demo reconciliation: not run".
- With --demo pointing at a second telemetry JSON/JSONL bundle: emits JSON alignment metrics.
- With --demo pointing at .dem or other binaries: emits TODO stub (wire awpy / dashboard workers).

Run from repo root:
  python3 tools/biobase_demo_reconcile.py --telemetry docs/cs2/examples/minimal-bundle.json

Optional jsonschema validation:
  pip install jsonschema   # strictly optional enhancement
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCHEMA_PATH = REPO_ROOT / "docs" / "cs2" / "biobase-telemetry-v1.schema.json"
SCHEMA_CONST = "biobase-telemetry-v1"


def _load_optional_json_schema_validator() -> tuple[type[Any] | None, str]:
    try:
        import jsonschema

        validator_cls = getattr(jsonschema, "Draft202012Validator", None) or getattr(
            jsonschema, "Draft7Validator", None
        )
        if validator_cls is None:
            return None, "jsonschema_installed_without_supported_draft"
    except ImportError:
        return None, "jsonschema_not_installed"

    return validator_cls, "ok"


def _load_bundle(path: Path) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        return None, [f"{path}: empty file"]

    if text.startswith("{"):
        try:
            return json.loads(text), errors
        except json.JSONDecodeError as exc:
            return None, [f"{path}: invalid JSON ({exc.msg})"]

    bundles: list[dict[str, Any]] = []
    for idx, raw in enumerate(text.splitlines()):
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as exc:
            errors.append(f"{path}:{idx+1}: invalid JSON ({exc.msg})")
            continue
        if isinstance(obj, dict):
            bundles.append(obj)
    if errors and not bundles:
        return None, errors
    if not bundles:
        return None, [f"{path}: JSONL yielded no JSON objects"]
    preferred = None
    for candidate in bundles:
        if candidate.get("schema_version") == SCHEMA_CONST:
            preferred = candidate
            break
    return (preferred or bundles[0]), errors


def _validate_stdlib(bundle: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if bundle.get("schema_version") != SCHEMA_CONST:
        errors.append(
            f"schema_version must be {SCHEMA_CONST!r}; got {bundle.get('schema_version')!r}"
        )
    for key in ("match_id", "map"):
        val = bundle.get(key)
        if not isinstance(val, str) or not val.strip():
            errors.append(f"{key} must be a non-empty string")
    tickrate = bundle.get("tickrate")
    if not isinstance(tickrate, int) or not (1 <= tickrate <= 256):
        errors.append("tickrate must be int in [1, 256]")
    players = bundle.get("players")
    if not isinstance(players, list):
        errors.append("players must be an array")
    else:
        for idx, player in enumerate(players):
            if not isinstance(player, dict):
                errors.append(f"players[{idx}] must be an object")
                continue
            for field in ("steam_id", "name"):
                fv = player.get(field)
                if not isinstance(fv, str) or not fv.strip():
                    errors.append(f"players[{idx}].{field} must be a non-empty string")
    samples = bundle.get("samples")
    if samples is None:
        errors.append("samples is required")
    elif isinstance(samples, list):
        for idx, row in enumerate(samples):
            if not isinstance(row, dict):
                errors.append(f"samples[{idx}] must be an object")
                continue
            if "tick" not in row:
                errors.append(f"samples[{idx}] missing required field tick")
            elif type(row["tick"]) is not int:
                errors.append(f"samples[{idx}].tick must be int")
            sid = row.get("steam_id")
            if not isinstance(sid, str) or not sid.strip():
                errors.append(f"samples[{idx}].steam_id must be non-empty string")
    elif isinstance(samples, dict):
        fmt = samples.get("format")
        ptr = samples.get("path")
        if fmt not in {"ndjson_relative", "parquet_relative"}:
            errors.append(
                "samples pointer requires format ndjson_relative|parquet_relative"
            )
        if not isinstance(ptr, str) or not ptr.strip():
            errors.append("samples.pointer.path must be a non-empty string")
    else:
        errors.append("samples must be an array or pointer object")
    recs = bundle.get("recordings")
    if recs is not None and not isinstance(recs, list):
        errors.append("recordings must be an array when present")
    return errors


def _sample_stats(samples: Any) -> dict[str, Any]:
    if not isinstance(samples, list):
        return {"count": 0, "tick_min": None, "tick_max": None}
    ticks: list[int] = []
    for row in samples:
        if isinstance(row, dict) and isinstance(row.get("tick"), int):
            ticks.append(row["tick"])
    if not ticks:
        return {"count": len(samples), "tick_min": None, "tick_max": None}
    return {
        "count": len(samples),
        "tick_min": min(ticks),
        "tick_max": max(ticks),
    }


def _steam_ids(bundle: dict[str, Any]) -> set[str]:
    out: set[str] = set()
    players = bundle.get("players")
    if not isinstance(players, list):
        return out
    for p in players:
        if isinstance(p, dict):
            sid = p.get("steam_id")
            if isinstance(sid, str):
                out.add(sid.strip())
    return out


def _tick_set(samples: Any) -> set[int]:
    if not isinstance(samples, list):
        return set()
    return {
        row["tick"]
        for row in samples
        if isinstance(row, dict) and isinstance(row.get("tick"), int)
    }


def _alignment(primary: dict[str, Any], secondary: dict[str, Any]) -> dict[str, Any]:
    ticks_a = _tick_set(primary.get("samples"))
    ticks_b = _tick_set(secondary.get("samples"))
    ids_a = _steam_ids(primary)
    ids_b = _steam_ids(secondary)

    intersect_ticks = ticks_a & ticks_b
    union_ticks = ticks_a | ticks_b
    tick_jaccard = (
        len(intersect_ticks) / len(union_ticks) if union_ticks else 1.0
    )

    intersect_ids = ids_a & ids_b
    union_ids = ids_a | ids_b
    id_jaccard = len(intersect_ids) / len(union_ids) if union_ids else 1.0

    sa = _sample_stats(primary.get("samples"))
    sb = _sample_stats(secondary.get("samples"))
    count_delta = sb["count"] - sa["count"]

    map_match = primary.get("map") == secondary.get("map")
    match_uuid_equal = primary.get("match_id") == secondary.get("match_id")

    return {
        "match_ids_equal": bool(match_uuid_equal),
        "map_equal": bool(map_match),
        "steam_id_jaccard": round(id_jaccard, 4),
        "shared_steam_ids": sorted(intersect_ids),
        "primary_sample_count": sa["count"],
        "secondary_sample_count": sb["count"],
        "sample_count_delta": count_delta,
        "primary_tick_span": {"min": sa["tick_min"], "max": sa["tick_max"]},
        "secondary_tick_span": {"min": sb["tick_min"], "max": sb["tick_max"]},
        "tick_jaccard": round(tick_jaccard, 4),
        "shared_tick_count": len(intersect_ticks),
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--telemetry",
        required=True,
        type=Path,
        help="Telemetry bundle (.json preferred; JSON L first-record fallback)",
    )
    parser.add_argument(
        "--demo",
        type=Path,
        help="Secondary telemetry bundle for diff metrics OR a .dem awaiting parser wiring.",
    )
    parser.add_argument(
        "--schema",
        type=Path,
        default=DEFAULT_SCHEMA_PATH,
        help=f"JSON Schema path (default: {DEFAULT_SCHEMA_PATH})",
    )
    parser.add_argument(
        "--json-out",
        action="store_true",
        help="Emit machine-readable summary JSON instead of plaintext sections.",
    )
    ns = parser.parse_args(argv)

    telemetry_path = ns.telemetry.expanduser().resolve()
    if not telemetry_path.is_file():
        print(f"telemetry path not found: {telemetry_path}", file=sys.stderr)
        return 2

    bundle, read_errors = _load_bundle(telemetry_path)
    if bundle is None:
        for msg in read_errors:
            print(msg, file=sys.stderr)
        return 3

    schema_errors_std = _validate_stdlib(bundle)
    combined_errors = list(schema_errors_std)

    validator_cls, schema_status = _load_optional_json_schema_validator()
    draft_note = ""
    if validator_cls:
        draft_note = validator_cls.__name__
        if ns.schema.is_file():
            schema_obj = json.loads(ns.schema.read_text(encoding="utf-8"))
            try:
                validator_cls(schema_obj).validate(bundle)
            except Exception as exc:
                combined_errors.append(f"jsonschema: {exc}")
        else:
            combined_errors.append(
                f"jsonschema skipped: schema file missing at {ns.schema}"
            )

    roster = bundle.get("players")
    roster_lines: list[str] = []
    if isinstance(roster, list):
        for p in roster:
            if isinstance(p, dict):
                roster_lines.append(
                    f"{p.get('steam_id','?')}: {p.get('name','?')}"
                )

    stats = _sample_stats(bundle.get("samples"))

    reconcile_meta: dict[str, Any] = {
        "demo_reconciliation": "not_run",
        "telemetry_path": str(telemetry_path),
        "jsonschema_note": schema_status,
        "jsonschema_draft": draft_note if validator_cls else "",
    }

    demo_section: dict[str, Any] = {}
    if ns.demo:
        demo_path = ns.demo.expanduser().resolve()
        if not demo_path.is_file():
            print(f"demo path not found: {demo_path}", file=sys.stderr)
            return 2
        suffix = demo_path.suffix.lower()
        if suffix == ".dem":
            demo_section = {
                "phase": "TODO",
                "note": (
                    ".dem ingestion not wired here; reuse bb_cs2_dashboard workers "
                    "(awpy_summary.py, demoparser2_summary.go) inside scheduled job."
                ),
            }
            reconcile_meta["demo_reconciliation"] = "stub_demo_file"
        else:
            demo_bundle, demo_read_errors = _load_bundle(demo_path)
            if demo_bundle is None:
                print("Secondary telemetry failed to load:", file=sys.stderr)
                for msg in demo_read_errors:
                    print(f"  {msg}", file=sys.stderr)
                return 4
            demo_validate = _validate_stdlib(demo_bundle)
            if demo_validate:
                print("Secondary telemetry validation issues:", file=sys.stderr)
                for msg in demo_validate:
                    print(f"  {msg}", file=sys.stderr)
                return 5
            demo_section = {"alignment_metrics": _alignment(bundle, demo_bundle)}
            reconcile_meta["demo_reconciliation"] = (
                "telemetry_vs_telemetry_completed"
            )
            reconcile_meta["demo_path"] = str(demo_path)

    summary = {
        "schema_validation": {"ok": not combined_errors, "errors": combined_errors},
        "read_warnings": read_errors,
        "match_id": bundle.get("match_id"),
        "map": bundle.get("map"),
        "tickrate": bundle.get("tickrate"),
        "sample_counts": stats,
        "player_list": roster_lines,
        "reconcile": reconcile_meta,
        **({"demo_alignment": demo_section} if demo_section else {}),
    }

    if ns.json_out:
        print(json.dumps(summary, indent=2, sort_keys=True))
        return 0 if not combined_errors else 1

    print("BioBase telemetry v1 reconcile (MVP)")
    print(f"telemetry: {telemetry_path}")
    if combined_errors:
        print("validation: FAILED")
        for msg in combined_errors:
            print(f"  - {msg}")
    else:
        print("validation: OK (stdlib thresholds; jsonschema: "
              f"{schema_status})")
        if validator_cls and draft_note:
            print(f"  jsonschema draft: {draft_note}")
    print(f"match_id: {bundle.get('match_id')}")
    print(f"map: {bundle.get('map')}  tickrate: {bundle.get('tickrate')}")
    print(
        f"samples: count={stats['count']} tick_span="
        f"{stats['tick_min']}..{stats['tick_max']}"
    )
    print("players:")
    for row in roster_lines:
        print(f"  - {row}")
    if demo_section:
        label = reconcile_meta["demo_reconciliation"]
        print(f"\ndemo reconciliation: {label}")
        if "alignment_metrics" in demo_section:
            for key, value in demo_section["alignment_metrics"].items():
                print(f"  {key}: {value}")
        elif "note" in demo_section:
            print(f"  note: {demo_section['note']}")
    else:
        print("\ndemo reconciliation: not run (--demo omitted)")
        print("  Provide a second bundle via --demo to compare telemetry exports.")
        print(
            "  Provide a .dem to print parser wiring guidance (stub only here)."
        )
    return 0 if not combined_errors else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
