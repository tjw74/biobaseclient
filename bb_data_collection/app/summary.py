"""Aggregate summary for a completed CS2 ingest session."""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

import psycopg2

ROUND_STAT_COLS = [
    "id", "session_id", "recorded_at", "round_number", "score_t", "score_ct", "map",
    "slot_index", "accountid", "team", "money", "kills", "deaths", "assists",
    "dmg", "hsp", "kdr", "adr", "mvp", "ef", "ud",
    "kills_3k", "kills_4k", "kills_5k",
    "clutchk", "firstk", "pistolk", "sniperk", "blindk", "bombk",
    "firedmg", "uniquek", "dinks", "chickenk",
]

COLUMNS = {
    "biobase_cs2_match_session": [
        "id", "label", "status", "duration_requested",
        "created_at", "started_at", "ended_at",
        "loki_start_ns", "loki_end_ns", "error_message",
    ],
    "biobase_cs2_rcon_sample": [
        "id", "session_id", "sampled_at", "rcon_ok",
        "headline", "humans", "bots", "map", "hostname", "raw_json",
    ],
    "biobase_cs2_player_snapshot": [
        "id", "session_id", "rcon_sample_id", "sampled_at",
        "userid", "player_name", "steamid", "connected", "ping", "loss", "state",
    ],
    "biobase_cs2_log_line": [
        "id", "session_id", "ingested_at", "loki_ts_ns", "line",
    ],
    "biobase_cs2_game_event": [
        "id", "session_id", "log_line_id", "event_ts", "event_type",
        "round_num", "attacker_name", "attacker_steamid", "attacker_team",
        "victim_name", "victim_steamid", "victim_team",
        "weapon", "headshot", "extra_json", "raw_line",
    ],
    "biobase_cs2_movement_sample": [
        "id", "session_id", "log_line_id", "sampled_at", "tick",
        "player_name", "steamid",
        "pos_x", "pos_y", "pos_z", "vel_x", "vel_y", "vel_z",
        "speed", "yaw", "pitch", "on_ground", "extra_json",
    ],
    "biobase_cs2_round_stats": ROUND_STAT_COLS,
}


def load_summary(database_url: str, session_id: UUID) -> dict[str, Any] | None:
    with psycopg2.connect(database_url) as conn:
        with conn.cursor() as cur:
            # Session row
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
                _id, label, status, duration_requested,
                created_at, started_at, ended_at,
                loki_start_ns, loki_end_ns, error_message,
            ) = row

            # RCON samples
            cur.execute(
                """
                SELECT count(*)::bigint,
                       min(sampled_at), max(sampled_at),
                       count(*) filter (where rcon_ok)::bigint,
                       count(*) filter (where not rcon_ok)::bigint
                FROM public.biobase_cs2_rcon_sample
                WHERE session_id = %s
                """,
                (str(session_id),),
            )
            rc = cur.fetchone() or (0, None, None, 0, 0)
            n_r, t_min, t_max, n_ok, n_fail = rc

            # Player snapshots
            cur.execute(
                """
                SELECT count(*)::bigint,
                       count(distinct player_name)::bigint,
                       count(distinct steamid)::bigint,
                       min(sampled_at), max(sampled_at)
                FROM public.biobase_cs2_player_snapshot
                WHERE session_id = %s
                """,
                (str(session_id),),
            )
            ps = cur.fetchone() or (0, 0, 0, None, None)
            n_ps, n_unique_players, n_unique_ids, ps_min, ps_max = ps

            # Log lines
            cur.execute(
                """
                SELECT count(*)::bigint,
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

            # Game events — total + per type breakdown
            cur.execute(
                """
                SELECT count(*)::bigint,
                       count(*) filter (where event_type = 'kill')::bigint,
                       count(*) filter (where event_type = 'round_start')::bigint,
                       count(*) filter (where event_type = 'round_end')::bigint,
                       count(*) filter (where headshot)::bigint,
                       max(round_num),
                       count(*) filter (where event_type = 'damage')::bigint,
                       count(*) filter (where event_type = 'assist')::bigint
                FROM public.biobase_cs2_game_event
                WHERE session_id = %s
                """,
                (str(session_id),),
            )
            ge = cur.fetchone() or (0, 0, 0, 0, 0, None, 0, 0)
            n_ge, n_kills, n_round_start, n_round_end, n_hs, max_round, n_damage, n_assists = ge

            # Top killers
            cur.execute(
                """
                SELECT attacker_name, attacker_steamid,
                       count(*)::bigint AS kills,
                       count(*) filter (where headshot)::bigint AS headshots
                FROM public.biobase_cs2_game_event
                WHERE session_id = %s AND event_type = 'kill'
                GROUP BY attacker_name, attacker_steamid
                ORDER BY kills DESC
                LIMIT 10
                """,
                (str(session_id),),
            )
            top_killers = [
                {
                    "name": r[0], "steamid": r[1],
                    "kills": int(r[2]), "headshots": int(r[3]),
                }
                for r in cur.fetchall()
            ]

            # Weapon breakdown
            cur.execute(
                """
                SELECT weapon, count(*)::bigint AS kills
                FROM public.biobase_cs2_game_event
                WHERE session_id = %s AND event_type = 'kill' AND weapon IS NOT NULL
                GROUP BY weapon
                ORDER BY kills DESC
                LIMIT 15
                """,
                (str(session_id),),
            )
            weapon_stats = [{"weapon": r[0], "kills": int(r[1])} for r in cur.fetchall()]

            # Movement samples
            cur.execute(
                """
                SELECT count(*)::bigint,
                       count(distinct player_name)::bigint,
                       min(sampled_at), max(sampled_at)
                FROM public.biobase_cs2_movement_sample
                WHERE session_id = %s
                """,
                (str(session_id),),
            )
            mv = cur.fetchone() or (0, 0, None, None)
            n_mv, n_mv_players, mv_min, mv_max = mv

            # Round stats (from JSON_BEGIN/END blocks)
            cur.execute(
                """
                SELECT count(*)::bigint,
                       count(distinct round_number)::bigint,
                       max(round_number),
                       coalesce(sum(kills), 0)::bigint,
                       coalesce(sum(deaths), 0)::bigint,
                       coalesce(sum(dmg), 0)
                FROM public.biobase_cs2_round_stats
                WHERE session_id = %s
                """,
                (str(session_id),),
            )
            rs_r = cur.fetchone() or (0, 0, None, 0, 0, 0)
            n_rs, n_rs_rounds, max_rs_round, rs_kills, rs_deaths, rs_dmg = rs_r

            # Top players by kills across all rounds in round_stats
            cur.execute(
                """
                SELECT ps.player_name, rs.slot_index,
                       sum(rs.kills)::bigint AS total_kills,
                       sum(rs.deaths)::bigint AS total_deaths,
                       sum(rs.dmg) AS total_dmg,
                       round(avg(rs.adr)::numeric, 1) AS avg_adr
                FROM public.biobase_cs2_round_stats rs
                LEFT JOIN LATERAL (
                    SELECT DISTINCT ON (userid) player_name
                    FROM public.biobase_cs2_player_snapshot
                    WHERE session_id = rs.session_id AND userid = rs.slot_index
                    ORDER BY userid, sampled_at
                    LIMIT 1
                ) ps ON true
                WHERE rs.session_id = %s
                GROUP BY ps.player_name, rs.slot_index
                ORDER BY total_kills DESC
                LIMIT 10
                """,
                (str(session_id),),
            )
            rs_top = [
                {
                    "name": r[0] or f"slot_{r[1]}",
                    "slot": r[1],
                    "kills": int(r[2] or 0),
                    "deaths": int(r[3] or 0),
                    "total_damage": float(r[4] or 0),
                    "avg_adr": float(r[5] or 0),
                }
                for r in cur.fetchall()
            ]

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
            "column_count": len(COLUMNS["biobase_cs2_rcon_sample"]) - 1,
            "column_names": [c for c in COLUMNS["biobase_cs2_rcon_sample"] if c != "id"],
            "rcon_ok_count": int(n_ok),
            "rcon_fail_count": int(n_fail),
            "time_range": {"first_sample": _iso(t_min), "last_sample": _iso(t_max)},
            "sampling_granularity": rcon_grain,
        },
        "player_snapshots": {
            "table": "biobase_cs2_player_snapshot",
            "row_count": int(n_ps),
            "column_count": len(COLUMNS["biobase_cs2_player_snapshot"]) - 1,
            "column_names": [c for c in COLUMNS["biobase_cs2_player_snapshot"] if c != "id"],
            "unique_player_names": int(n_unique_players),
            "unique_steamids": int(n_unique_ids),
            "time_range": {"first": _iso(ps_min), "last": _iso(ps_max)},
            "note": "One row per player per RCON status poll; steamid='BOT' for bots",
        },
        "log_lines": {
            "table": "biobase_cs2_log_line",
            "row_count": int(n_lines),
            "column_count": len(COLUMNS["biobase_cs2_log_line"]) - 1,
            "column_names": [c for c in COLUMNS["biobase_cs2_log_line"] if c != "id"],
            "approx_total_bytes_utf8": int(n_bytes),
            "ingest_time_range": {"first": _iso(line_i_min), "last": _iso(line_i_max)},
            "heuristic_kz_plugin_hits": n_kz,
            "heuristic_note": (
                "Count of lines matching KZ/Metamod/timer keywords in SQL; "
                "see session_ingest.KZ_RE in code"
            ),
        },
        "game_events": {
            "table": "biobase_cs2_game_event",
            "row_count": int(n_ge),
            "column_count": len(COLUMNS["biobase_cs2_game_event"]) - 1,
            "column_names": [c for c in COLUMNS["biobase_cs2_game_event"] if c != "id"],
            "kills": int(n_kills),
            "headshots": int(n_hs),
            "assists": int(n_assists),
            "damage_events": int(n_damage),
            "round_start_events": int(n_round_start),
            "round_end_events": int(n_round_end),
            "rounds_played": int(max_round) if max_round is not None else 0,
            "top_killers": top_killers,
            "weapon_kill_counts": weapon_stats,
            "note": (
                "Parsed from biobase_cs2_log_line; event_type includes: "
                "kill, damage, assist, round_start, round_end, team_score, connect, "
                "disconnect, say, say_team, biobase_pos, biobase_event. "
                "damage events include attacker/victim [x y z] positions and hitgroup."
            ),
        },
        "movement_samples": {
            "table": "biobase_cs2_movement_sample",
            "row_count": int(n_mv),
            "column_count": len(COLUMNS["biobase_cs2_movement_sample"]) - 1,
            "column_names": [c for c in COLUMNS["biobase_cs2_movement_sample"] if c != "id"],
            "unique_players": int(n_mv_players),
            "time_range": {"first": _iso(mv_min), "last": _iso(mv_max)},
            "note": (
                "Populated only when a server plugin emits BIOBASE_POS_JSON lines; "
                "contains pos_x/y/z, vel_x/y/z, speed, yaw, pitch, on_ground per tick"
            ),
        },
        "round_stats": {
            "table": "biobase_cs2_round_stats",
            "row_count": int(n_rs),
            "column_count": len(ROUND_STAT_COLS) - 1,
            "column_names": [c for c in ROUND_STAT_COLS if c != "id"],
            "rounds_with_data": int(n_rs_rounds),
            "max_round_number": int(max_rs_round) if max_rs_round is not None else 0,
            "total_kills_all_rounds": int(rs_kills),
            "total_deaths_all_rounds": int(rs_deaths),
            "total_damage_all_rounds": round(float(rs_dmg), 1),
            "top_players_by_kills": rs_top,
            "note": (
                "Per-player CUMULATIVE stats from CS2 JSON_BEGIN/END log blocks; "
                "emitted at the start of each round. slot_index joins with "
                "biobase_cs2_player_snapshot.userid to get player name. "
                "Fields: kills, deaths, assists, dmg, hsp, kdr, adr, mvp, 3k/4k/5k, "
                "clutchk, firstk, pistolk, sniperk, dinks, firedmg, etc."
            ),
        },
        "column_catalog": COLUMNS,
    }


def _iso(t: Any) -> str | None:
    if t is None:
        return None
    if isinstance(t, datetime):
        return t.isoformat()
    return str(t)
