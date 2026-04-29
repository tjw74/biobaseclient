"""Mirror CS2KZ local SQLite (Players, Times, Jumpstats) into Postgres.

CS2KZ writes gameplay data to ``addons/cs2kz/data/<database>.sqlite3`` when the
server runs Metamod **sql_mm** and ``cs2kz-server-config`` enables the ``db`` block.

Incremental ingest uses SQLite ``rowid`` cursors per ingest session.
"""

from __future__ import annotations

import logging
import os
import shutil
import sqlite3
import tempfile
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import psycopg2
from psycopg2.extras import execute_values

log = logging.getLogger(__name__)

MAX_ROWS_PER_POLL = int(os.environ.get("BIOBASE_CS2KZ_SQLITE_CHUNK", "2000"))


def _sqlite_table_exists(conn: sqlite3.Connection, name: str) -> bool:
    cur = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        (name,),
    )
    return cur.fetchone() is not None


def _open_sqlite_snapshot(src_path: str) -> tuple[sqlite3.Connection | None, str | None]:
    """Open a temp read-only copy of the DB (avoids WAL locks while server runs)."""
    if not os.path.isfile(src_path):
        return None, None
    fd, tmp = tempfile.mkstemp(suffix=".sqlite3")
    os.close(fd)
    try:
        shutil.copy2(src_path, tmp)
        conn = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
        return conn, tmp
    except Exception:  # noqa: BLE001
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return None, None


def _dt_from_cell(val: Any) -> datetime | None:
    if val is None:
        return None
    if isinstance(val, datetime):
        if val.tzinfo is None:
            return val.replace(tzinfo=UTC)
        return val
    if isinstance(val, (int, float)):
        try:
            i = int(val)
            return datetime.fromtimestamp(i, tz=UTC)
        except (ValueError, OSError, OverflowError):
            return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%S.%f",
    ):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=UTC)
        except ValueError:
            continue
    return None


def _load_modes(conn: sqlite3.Connection) -> dict[int, tuple[str, str]]:
    if not _sqlite_table_exists(conn, "Modes"):
        return {}
    out: dict[int, tuple[str, str]] = {}
    for row in conn.execute("SELECT ID, Name, ShortName FROM Modes"):
        out[int(row[0])] = (str(row[1]), str(row[2]))
    return out


def _load_map_courses(conn: sqlite3.Connection) -> dict[int, tuple[str, str]]:
    if not _sqlite_table_exists(conn, "MapCourses") or not _sqlite_table_exists(conn, "Maps"):
        return {}
    out: dict[int, tuple[str, str]] = {}
    for row in conn.execute(
        """
        SELECT mc.ID, m.Name, mc.Name
        FROM MapCourses mc
        INNER JOIN Maps m ON m.ID = mc.MapID
        """
    ):
        out[int(row[0])] = (str(row[1]), str(row[2]))
    return out


def _get_cursor(cur: Any, session_id: str, table_name: str) -> int:
    cur.execute(
        """
        SELECT last_rowid FROM public.biobase_cs2kz_sqlite_cursor
        WHERE session_id = %s AND table_name = %s
        """,
        (session_id, table_name),
    )
    row = cur.fetchone()
    return int(row[0]) if row else 0


def _set_cursor(cur: Any, session_id: str, table_name: str, last_rowid: int) -> None:
    cur.execute(
        """
        INSERT INTO public.biobase_cs2kz_sqlite_cursor (session_id, table_name, last_rowid)
        VALUES (%s, %s, %s)
        ON CONFLICT (session_id, table_name) DO UPDATE SET last_rowid = EXCLUDED.last_rowid
        """,
        (session_id, table_name, last_rowid),
    )


def ingest_cs2kz_sqlite_for_session(
    database_url: str,
    session_id: UUID,
    sqlite_path: str,
) -> dict[str, Any]:
    stats: dict[str, Any] = {
        "sqlite_path": sqlite_path,
        "players_upserted": 0,
        "runs_inserted": 0,
        "jumpstats_inserted": 0,
        "skipped": False,
        "error": None,
    }
    sid = str(session_id)
    sl_conn, tmp_path = _open_sqlite_snapshot(sqlite_path)
    if sl_conn is None:
        stats["skipped"] = True
        return stats

    try:
        if not _sqlite_table_exists(sl_conn, "Players"):
            stats["skipped"] = True
            stats["error"] = "sqlite_has_no_kz_tables"
            return stats

        modes = _load_modes(sl_conn)
        courses = _load_map_courses(sl_conn)

        with psycopg2.connect(database_url) as pg:
            pg.autocommit = True
            with pg.cursor() as cur:
                # --- Players: full upsert each poll (small table) ---
                player_rows: list[tuple[Any, ...]] = []
                for row in sl_conn.execute(
                    "SELECT SteamID64, Alias, IP, Preferences, Cheater, LastPlayed, Created FROM Players"
                ):
                    steam = int(row[0])
                    alias, ip, prefs = row[1], row[2], row[3]
                    cheater = int(row[4] or 0)
                    lp = _dt_from_cell(row[5])
                    cr = _dt_from_cell(row[6])
                    player_rows.append(
                        (sid, steam, alias, ip, prefs, cheater, lp, cr),
                    )
                if player_rows:
                    execute_values(
                        cur,
                        """
                        INSERT INTO public.biobase_cs2kz_player
                        (session_id, steamid64, alias, ip, preferences, cheater, last_played, created_server)
                        VALUES %s
                        ON CONFLICT (session_id, steamid64) DO UPDATE SET
                          alias = EXCLUDED.alias,
                          ip = EXCLUDED.ip,
                          preferences = EXCLUDED.preferences,
                          cheater = EXCLUDED.cheater,
                          last_played = EXCLUDED.last_played,
                          created_server = EXCLUDED.created_server,
                          ingested_at = now()
                        """,
                        player_rows,
                        page_size=1000,
                    )
                stats["players_upserted"] = len(player_rows)

                # --- Times (runs) ---
                if _sqlite_table_exists(sl_conn, "Times"):
                    last_r = _get_cursor(cur, sid, "Times")
                    tcur = sl_conn.execute(
                        """
                        SELECT rowid, ID, SteamID64, MapCourseID, ModeID, StyleIDFlags,
                               RunTime, Teleports, Metadata, Created
                        FROM Times
                        WHERE rowid > ?
                        ORDER BY rowid
                        LIMIT ?
                        """,
                        (last_r, MAX_ROWS_PER_POLL),
                    )
                    run_batch = tcur.fetchall()
                    max_rowid = last_r
                    run_ins: list[tuple[Any, ...]] = []
                    for r in run_batch:
                        rid = int(r[0])
                        max_rowid = max(max_rowid, rid)
                        tid = r[1]
                        time_id = tid if isinstance(tid, str) else str(tid)
                        sid64 = int(r[2])
                        mcid = int(r[3])
                        mode_id = int(r[4])
                        style_flags = int(r[5])
                        runtime = float(r[6])
                        teleports = int(r[7])
                        meta = r[8]
                        created_u = r[9]
                        cu = int(created_u) if created_u is not None else None
                        mn, cn = courses.get(mcid, (None, None))
                        mode_t = modes.get(mode_id, (None, None))
                        run_ins.append(
                            (
                                sid,
                                time_id,
                                sid64,
                                mcid,
                                mn,
                                cn,
                                mode_id,
                                mode_t[0],
                                mode_t[1],
                                style_flags,
                                runtime,
                                teleports,
                                meta,
                                cu,
                                rid,
                            ),
                        )
                    if run_ins:
                        execute_values(
                            cur,
                            """
                            INSERT INTO public.biobase_cs2kz_run
                            (session_id, time_id, steamid64, map_course_id, map_name, course_name,
                             mode_id, mode_name, mode_short, style_id_flags, run_time, teleports,
                             metadata, created_unix, sqlite_rowid)
                            VALUES %s
                            ON CONFLICT (session_id, time_id) DO NOTHING
                            """,
                            run_ins,
                            page_size=500,
                        )
                        rc = cur.rowcount
                        stats["runs_inserted"] = rc if rc is not None and rc >= 0 else len(run_ins)
                    if run_batch:
                        _set_cursor(cur, sid, "Times", max_rowid)

                # --- Jumpstats ---
                if _sqlite_table_exists(sl_conn, "Jumpstats"):
                    last_j = _get_cursor(cur, sid, "Jumpstats")
                    jcur = sl_conn.execute(
                        """
                        SELECT rowid, ID, SteamID64, JumpType, Mode, Distance, IsBlockJump,
                               Block, Strafes, Sync, Pre, Max, Airtime, Created
                        FROM Jumpstats
                        WHERE rowid > ?
                        ORDER BY rowid
                        LIMIT ?
                        """,
                        (last_j, MAX_ROWS_PER_POLL),
                    )
                    js_batch = jcur.fetchall()
                    max_j = last_j
                    js_ins: list[tuple[Any, ...]] = []
                    for r in js_batch:
                        rid = int(r[0])
                        max_j = max(max_j, rid)
                        js_id = int(r[1])
                        sid64 = int(r[2])
                        jt = int(r[3])
                        mode_id = int(r[4])
                        dist = int(r[5])
                        ibj = int(r[6])
                        blk = int(r[7])
                        strafes = int(r[8])
                        sync = int(r[9])
                        pre = int(r[10])
                        jump_air_max = int(r[11])
                        air = int(r[12])
                        created_u = r[13]
                        cu = int(created_u) if created_u is not None else None
                        mname = modes.get(mode_id, (None, None))[0]
                        js_ins.append(
                            (
                                sid,
                                js_id,
                                sid64,
                                jt,
                                mode_id,
                                mname,
                                dist,
                                ibj,
                                blk,
                                strafes,
                                sync,
                                pre,
                                jump_air_max,
                                air,
                                cu,
                                rid,
                            ),
                        )
                    if js_ins:
                        execute_values(
                            cur,
                            """
                            INSERT INTO public.biobase_cs2kz_jumpstat
                            (session_id, jumpstat_id, steamid64, jump_type, mode_id, mode_name,
                             distance, is_block_jump, block, strafes, sync, pre, jump_air_max, airtime,
                             created_unix, sqlite_rowid)
                            VALUES %s
                            ON CONFLICT (session_id, jumpstat_id) DO NOTHING
                            """,
                            js_ins,
                            page_size=500,
                        )
                        rc = cur.rowcount
                        stats["jumpstats_inserted"] = rc if rc is not None and rc >= 0 else len(js_ins)
                    if js_batch:
                        _set_cursor(cur, sid, "Jumpstats", max_j)

    except Exception as e:  # noqa: BLE001
        log.warning("CS2KZ sqlite ingest failed: %s", e)
        stats["error"] = str(e)[:2000]
    finally:
        sl_conn.close()
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    return stats


__all__ = ["ingest_cs2kz_sqlite_for_session", "MAX_ROWS_PER_POLL"]
