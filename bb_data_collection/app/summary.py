"""Aggregate summary for a completed CS2 ingest session."""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

import psycopg2

COLUMNS = {
    "biobase_cs2_match_session": [
        "id",
        "label",
        "status",
        "duration_requested",
        "created_at",
        "started_at",
        "ended_at",
        "loki_start_ns",
        "loki_end_ns",
        "error_message",
    ],
    "biobase_cs2_rcon_sample": [
        "id",
        "session_id",
        "sampled_at",
        "rcon_ok",
        "headline",
        "humans",
        "bots",
        "map",
        "hostname",
        "raw_json",
    ],
    "biobase_cs2_log_line": [
        "id",
        "session_id",
        "ingested_at",
        "loki_ts_ns",
        "line",
    ],
}


def load_summary(database_url: str, session_id: UUID) -> dict[str, Any] | None:
    with psycopg2.connect(database_url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id, label, status, duration_requested, created_at, started_at, ended_at,
                       loki_start_ns, loki_end_ns, error_message
                FROM public.biobase_cs2_match_session
                WHERE id = %s
                """,
                (str(session_id),),
            )
            row = cur.fetchone()
            if not row:
                return None
            (
                _id,
                label,
                status,
                duration_requested,
                created_at,
                started_at,
                ended_at,
                loki_start_ns,
                loki_end_ns,
                error_message,
            ) = row

            cur.execute(
                """
                SELECT
                  count(*)::bigint,
                  min(sampled_at), max(sampled_at),
                  count(*) filter (where rcon_ok) ::bigint,
                  count(*) filter (where not rcon_ok) ::bigint
                FROM public.biobase_cs2_rcon_sample
                WHERE session_id = %s
                """,
                (str(session_id),),
            )
            rc = cur.fetchone() or (0, None, None, 0, 0)
            n_r, t_min, t_max, n_ok, n_fail = rc

            cur.execute(
                """
                SELECT
                  count(*)::bigint,
                  coalesce(sum(octet_length(line::text)), 0)::bigint,
                  min(ingested_at), max(ingested_at)
                FROM public.biobase_cs2_log_line
                WHERE session_id = %s
                """,
                (str(session_id),),
            )
            lc = cur.fetchone() or (0, 0, None, None)
            n_lines, n_bytes, line_i_min, line_i_max = lc

            cur.execute(
                """
                SELECT count(*)::bigint
                FROM public.biobase_cs2_log_line
                WHERE session_id = %s AND line ~* 'kz|gokz|metamod|cs2kz|!record|timer|jump'
                """,
                (str(session_id),),
            )
            kz_hits = cur.fetchone()
            n_kz = int(kz_hits[0]) if kz_hits else 0

    wall_sec: float | None = None
    if started_at and ended_at:
        wall_sec = (ended_at - started_at).total_seconds()

    rcon_grain: str | None = None
    if n_r and int(n_r) > 1 and t_min and t_max and wall_sec and wall_sec > 0:
        rcon_grain = f"~{wall_sec / (int(n_r) - 1):.1f}s between samples (mean)"

    return {
        "session_id": str(session_id),
        "label": label,
        "status": status,
        "duration_requested_seconds": duration_requested,
        "timestamps": {
            "created_at": _iso(created_at),
            "started_at": _iso(started_at),
            "ended_at": _iso(ended_at),
            "wall_clock_seconds": round(wall_sec, 2) if wall_sec is not None else None,
        },
        "loki_window_ns": {"start": loki_start_ns, "end": loki_end_ns},
        "error_message": error_message,
        "rcon_samples": {
            "table": "biobase_cs2_rcon_sample",
            "row_count": int(n_r),
            "column_count": len(COLUMNS["biobase_cs2_rcon_sample"]) - 1,  # minus id
            "column_names": [c for c in COLUMNS["biobase_cs2_rcon_sample"] if c != "id"],
            "rcon_ok_count": int(n_ok),
            "rcon_fail_count": int(n_fail),
            "time_range": {"first_sample": _iso(t_min), "last_sample": _iso(t_max)},
            "sampling_granularity": rcon_grain,
        },
        "log_lines": {
            "table": "biobase_cs2_log_line",
            "row_count": int(n_lines),
            "column_count": len(COLUMNS["biobase_cs2_log_line"]) - 1,
            "column_names": [c for c in COLUMNS["biobase_cs2_log_line"] if c != "id"],
            "approx_total_bytes_utf8": int(n_bytes),
            "ingest_time_range": {"first": _iso(line_i_min), "last": _iso(line_i_max)},
            "heuristic_kz_plugin_hits": n_kz,
            "heuristic_note": "Count of lines matching KZ/Metamod/timer keywords in SQL; see session_ingest.KZ_RE in code",
        },
        "column_catalog": COLUMNS,
    }


def _iso(t: Any) -> str | None:
    if t is None:
        return None
    if isinstance(t, datetime):
        return t.isoformat()
    return str(t)
