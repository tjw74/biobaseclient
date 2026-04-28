"""
Background CS2 data session: RCON/HTTP status + per-player snapshots from bb_cs2_control,
Loki log lines (bb_cs2_server), and parsed game events / movement samples.
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

from app.log_parser import parse_events_from_lines

log = logging.getLogger(__name__)

KZ_RE = re.compile(
    r"(?i)kz|cs2kz|gokz|metamod|!record|timer|jumpstats",
)

MAX_LOKI_LINES = int(os.environ.get("BIOBASE_LOKI_LINE_LIMIT", "5000"))


def _db(database_url: str) -> psycopg2.extensions.connection:
    return psycopg2.connect(database_url)


def _insert_player_snapshots(
    cur: Any,
    session_id: str,
    rcon_sample_id: int,
    sampled_at: datetime,
    players: list[dict[str, Any]],
) -> None:
    if not players:
        return
    rows = [
        (
            session_id,
            rcon_sample_id,
            sampled_at,
            p.get("userid"),
            p.get("name"),
            p.get("steamid"),
            p.get("connected"),
            p.get("ping"),
            p.get("loss"),
            p.get("state"),
        )
        for p in players
    ]
    execute_values(
        cur,
        """
        INSERT INTO public.biobase_cs2_player_snapshot
        (session_id, rcon_sample_id, sampled_at,
         userid, player_name, steamid, connected, ping, loss, state)
        VALUES %s
        """,
        rows,
    )


def _insert_game_events(
    cur: Any,
    game_events: list[dict[str, Any]],
) -> None:
    if not game_events:
        return
    rows = [
        (
            ev["session_id"],
            ev.get("event_ts"),
            ev["event_type"],
            ev.get("round_num"),
            ev.get("attacker_name"),
            ev.get("attacker_steamid"),
            ev.get("attacker_team"),
            ev.get("victim_name"),
            ev.get("victim_steamid"),
            ev.get("victim_team"),
            ev.get("weapon"),
            ev.get("headshot"),
            Json(ev["extra_json"]) if ev.get("extra_json") is not None else None,
            ev["raw_line"][:4000],
        )
        for ev in game_events
    ]
    execute_values(
        cur,
        """
        INSERT INTO public.biobase_cs2_game_event
        (session_id, event_ts, event_type, round_num,
         attacker_name, attacker_steamid, attacker_team,
         victim_name, victim_steamid, victim_team,
         weapon, headshot, extra_json, raw_line)
        VALUES %s
        """,
        rows,
    )


def _insert_movement_samples(
    cur: Any,
    movement_samples: list[dict[str, Any]],
) -> None:
    if not movement_samples:
        return
    rows = [
        (
            ms["session_id"],
            ms.get("tick"),
            ms.get("player_name"),
            ms.get("steamid"),
            ms.get("pos_x"),
            ms.get("pos_y"),
            ms.get("pos_z"),
            ms.get("vel_x"),
            ms.get("vel_y"),
            ms.get("vel_z"),
            ms.get("speed"),
            ms.get("yaw"),
            ms.get("pitch"),
            ms.get("on_ground"),
            Json(ms["extra_json"]) if ms.get("extra_json") is not None else None,
        )
        for ms in movement_samples
    ]
    execute_values(
        cur,
        """
        INSERT INTO public.biobase_cs2_movement_sample
        (session_id, tick, player_name, steamid,
         pos_x, pos_y, pos_z, vel_x, vel_y, vel_z,
         speed, yaw, pitch, on_ground, extra_json)
        VALUES %s
        """,
        rows,
    )


def _insert_round_stats(
    cur: Any,
    round_stats_rows: list[dict[str, Any]],
) -> None:
    if not round_stats_rows:
        return
    rows = [
        (
            rs["session_id"],
            rs.get("round_number"),
            rs.get("score_t"),
            rs.get("score_ct"),
            rs.get("map"),
            rs.get("slot_index"),
            rs.get("accountid"),
            rs.get("team"),
            rs.get("money"),
            rs.get("kills"),
            rs.get("deaths"),
            rs.get("assists"),
            rs.get("dmg"),
            rs.get("hsp"),
            rs.get("kdr"),
            rs.get("adr"),
            rs.get("mvp"),
            rs.get("ef"),
            rs.get("ud"),
            rs.get("kills_3k"),
            rs.get("kills_4k"),
            rs.get("kills_5k"),
            rs.get("clutchk"),
            rs.get("firstk"),
            rs.get("pistolk"),
            rs.get("sniperk"),
            rs.get("blindk"),
            rs.get("bombk"),
            rs.get("firedmg"),
            rs.get("uniquek"),
            rs.get("dinks"),
            rs.get("chickenk"),
        )
        for rs in round_stats_rows
    ]
    execute_values(
        cur,
        """
        INSERT INTO public.biobase_cs2_round_stats
        (session_id, round_number, score_t, score_ct, map, slot_index,
         accountid, team, money, kills, deaths, assists,
         dmg, hsp, kdr, adr, mvp, ef, ud,
         kills_3k, kills_4k, kills_5k,
         clutchk, firstk, pistolk, sniperk, blindk, bombk,
         firedmg, uniquek, dinks, chickenk)
        VALUES %s
        """,
        rows,
    )


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
    sid_str = str(session_id)

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
                    ("running", datetime.now(UTC), loki_start, sid_str),
                )

        with _db(database_url) as rconn:
            rconn.autocommit = True
            async with httpx.AsyncClient(timeout=30.0) as client:
                while time.time() < t_end:
                    # Check for cancellation
                    with rconn.cursor() as cur:
                        cur.execute(
                            """
                            SELECT cancel_requested FROM public.biobase_cs2_match_session
                            WHERE id = %s
                            """,
                            (sid_str,),
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
                        j: dict[str, Any] = (
                            r.json() if r.status_code == 200
                            else {"error": r.text, "rcon_ok": False}
                        )
                        ok = r.status_code == 200 and j.get("rcon_ok", True) is not False
                    except Exception as e:  # noqa: BLE001
                        j = {"error": str(e), "rcon_ok": False}
                        ok = False

                    with rconn.cursor() as cur:
                        # Insert RCON sample and get back its PK for the player FK
                        cur.execute(
                            """
                            INSERT INTO public.biobase_cs2_rcon_sample
                            (session_id, sampled_at, rcon_ok, headline, humans, bots,
                             map, hostname, raw_json)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                            RETURNING id
                            """,
                            (
                                sid_str,
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
                        rcon_sample_id: int = cur.fetchone()[0]

                        # Per-player snapshots from the players list in the status response
                        players: list[dict[str, Any]] = j.get("players") or []
                        _insert_player_snapshots(cur, sid_str, rcon_sample_id, now_s, players)

                    sleep_t = rcon_interval_sec
                    remain = t_end - time.time()
                    if remain <= 0:
                        break
                    await asyncio.sleep(min(sleep_t, remain))

        loki_end = time.time_ns()
        if loki_end <= loki_start:
            loki_end = loki_start + 1

        # Fetch log lines from Loki for the session window
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
                        line_rows.append((sid_str, ns_i, line))
                if n_read > MAX_LOKI_LINES:
                    loki_note = (
                        f"truncated at {MAX_LOKI_LINES} log lines (cap); "
                        "increase BIOBASE_LOKI_LINE_LIMIT to ingest more"
                    )
        except Exception as e:  # noqa: BLE001
            log.exception("Loki query_range failed")
            loki_note = f"loki_error: {e!s}"[:2000]

        if cancelled_early:
            extra = " sampling stopped early (hub Stop or cancel); Loki window closed at stop time."
            loki_note = (loki_note + extra) if loki_note else extra.strip()

        # Parse game events, movement samples, and round stats from log lines
        plain_lines = [(sid_str, row[2]) for row in line_rows]
        try:
            game_events, movement_samples, round_stats_rows = parse_events_from_lines(plain_lines)
            log.info(
                "Session %s: parsed %d game events, %d movement samples, "
                "%d round-stat rows from %d log lines",
                session_id,
                len(game_events), len(movement_samples),
                len(round_stats_rows), len(line_rows),
            )
        except Exception as e:  # noqa: BLE001
            log.exception("Log event parsing failed for session %s", session_id)
            game_events, movement_samples, round_stats_rows = [], [], []
            parse_note = f"log_parse_error: {e!s}"[:500]
            loki_note = (loki_note + " " + parse_note) if loki_note else parse_note

        with _db(database_url) as conn:
            conn.autocommit = True
            with conn.cursor() as cur:
                # Insert raw log lines
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
                # Insert parsed game events
                _insert_game_events(cur, game_events)
                # Insert movement samples
                _insert_movement_samples(cur, movement_samples)
                # Insert per-player round stats from JSON_BEGIN/END blocks
                _insert_round_stats(cur, round_stats_rows)

                cur.execute(
                    """
                    UPDATE public.biobase_cs2_match_session
                    SET loki_end_ns = %s, ended_at = %s, status = %s, error_message = %s,
                        cancel_requested = false
                    WHERE id = %s
                    """,
                    (loki_end, datetime.now(UTC), "complete", loki_note, sid_str),
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
                        ("failed", datetime.now(UTC), str(e)[:2000], time.time_ns(), sid_str),
                    )
        except Exception:  # noqa: BLE001
            pass


__all__ = ["run_session", "KZ_RE", "MAX_LOKI_LINES"]
