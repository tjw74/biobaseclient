"""
Background CS2 data session: RCON/HTTP status from bb_cs2_control + Loki log lines (bb_cs2_server).
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
import time
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import httpx
import psycopg2
from psycopg2.extras import Json, execute_values

log = logging.getLogger(__name__)

KZ_RE = re.compile(
    r"(?i)kz|cs2kz|gokz|metamod|!record|timer|jumpstats",
)

# Default to Loki's common max_entries per query (5k); override if your cluster allows more.
MAX_LOKI_LINES = int(os.environ.get("BIOBASE_LOKI_LINE_LIMIT", "5000"))


def _db(database_url: str) -> psycopg2.extensions.connection:
    return psycopg2.connect(database_url)


async def run_session(
    database_url: str,
    loki_url: str,
    control_url: str,
    control_token: str,
    session_id: UUID,
    duration_sec: int,
    label: str | None,
    rcon_interval_sec: float,
) -> None:
    t0 = time.time()
    loki_start = time.time_ns()
    t_end = t0 + max(1, duration_sec)
    cancelled_early = False

    headers: dict[str, str] = {}
    if control_token:
        headers["X-Api-Key"] = control_token

    try:
        with _db(database_url) as conn:
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE public.biobase_cs2_match_session
                    SET status = %s, started_at = %s, loki_start_ns = %s
                    WHERE id = %s
                    """,
                    ("running", datetime.now(UTC), loki_start, str(session_id)),
                )

        with _db(database_url) as rconn:
            rconn.autocommit = True
            async with httpx.AsyncClient(timeout=30.0) as client:
                while time.time() < t_end:
                    with rconn.cursor() as cur:
                        cur.execute(
                            """
                            SELECT cancel_requested FROM public.biobase_cs2_match_session
                            WHERE id = %s
                            """,
                            (str(session_id),),
                        )
                        cr = cur.fetchone()
                    if cr and cr[0]:
                        cancelled_early = True
                        log.info("Session %s: cancel_requested; stopping RCON loop", session_id)
                        break
                    now_s = datetime.now(UTC)
                    try:
                        r = await client.get(
                            f"{control_url.rstrip('/')}/api/status",
                            headers=headers,
                        )
                        j: dict[str, Any] = r.json() if r.status_code == 200 else {"error": r.text, "rcon_ok": False}
                        ok = r.status_code == 200 and j.get("rcon_ok", True) is not False
                    except Exception as e:  # noqa: BLE001
                        j = {"error": str(e), "rcon_ok": False}
                        ok = False

                    with rconn.cursor() as cur:
                        cur.execute(
                            """
                            INSERT INTO public.biobase_cs2_rcon_sample
                            (session_id, sampled_at, rcon_ok, headline, humans, bots, map, hostname, raw_json)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                            """,
                            (
                                str(session_id),
                                now_s,
                                ok,
                                j.get("headline"),
                                j.get("humans"),
                                j.get("bots"),
                                j.get("map"),
                                j.get("hostname"),
                                Json(j),
                            ),
                        )
                    sleep_t = rcon_interval_sec
                    remain = t_end - time.time()
                    if remain <= 0:
                        break
                    await asyncio.sleep(min(sleep_t, remain))

        loki_end = time.time_ns()
        if loki_end <= loki_start:
            loki_end = loki_start + 1

        line_rows: list[tuple[str, int | None, str]] = []
        n_read = 0
        loki_note: str | None = None
        try:
            async with httpx.AsyncClient(timeout=120.0) as lclient:
                q = '{container="bb_cs2_server"}'
                params = {
                    "query": q,
                    "start": str(loki_start),
                    "end": str(loki_end),
                    "limit": MAX_LOKI_LINES,
                    "direction": "forward",
                }
                lr = await lclient.get(
                    f"{loki_url.rstrip('/')}/loki/api/v1/query_range",
                    params=params,
                )
                lr.raise_for_status()
                body = lr.json()
                for stream in body.get("data", {}).get("result", []):
                    for ts_ns, line in stream.get("values", []):
                        n_read += 1
                        if n_read > MAX_LOKI_LINES:
                            break
                        try:
                            ns_i = int(ts_ns) if ts_ns is not None else None
                        except (TypeError, ValueError):
                            ns_i = None
                        line_rows.append((str(session_id), ns_i, line))
                if n_read > MAX_LOKI_LINES:
                    loki_note = f"truncated at {MAX_LOKI_LINES} log lines (cap); increase MAX_LOKI_LINES in code to ingest more"
        except Exception as e:  # noqa: BLE001
            log.exception("Loki query_range failed")
            loki_note = f"loki_error: {e!s}"[:2000]

        if cancelled_early:
            extra = " sampling stopped early (hub Stop or cancel); Loki window closed at stop time."
            loki_note = (loki_note + extra) if loki_note else extra.strip()

        with _db(database_url) as conn:
            conn.autocommit = True
            with conn.cursor() as cur:
                if line_rows:
                    execute_values(
                        cur,
                        """
                        INSERT INTO public.biobase_cs2_log_line (session_id, loki_ts_ns, line)
                        VALUES %s
                        """,
                        line_rows,
                        page_size=5000,
                    )
                cur.execute(
                    """
                    UPDATE public.biobase_cs2_match_session
                    SET loki_end_ns = %s, ended_at = %s, status = %s, error_message = %s,
                        cancel_requested = false
                    WHERE id = %s
                    """,
                    (loki_end, datetime.now(UTC), "complete", loki_note, str(session_id)),
                )
    except Exception as e:  # noqa: BLE001
        log.exception("Session %s failed", session_id)
        try:
            with _db(database_url) as conn:
                conn.autocommit = True
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        UPDATE public.biobase_cs2_match_session
                        SET status = %s, ended_at = %s, error_message = %s, loki_end_ns = %s
                        WHERE id = %s
                        """,
                        ("failed", datetime.now(UTC), str(e)[:2000], time.time_ns(), str(session_id)),
                    )
        except Exception:  # noqa: BLE001
            pass


__all__ = ["run_session", "KZ_RE", "MAX_LOKI_LINES"]
