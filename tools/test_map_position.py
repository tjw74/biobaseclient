#!/usr/bin/env python3
"""
POC: start CS2 bots, pick one player name, insert map position samples every ~100 ms into bb_test.

**Continuous trajectory** requires in-server sampling: rebuild ``bb_cs2_server`` ships the
BiobasePosEmitter CounterStrikeSharp plugin, which prints ``BIOBASE_POS_JSON {...}`` to the dedicated
console every **100 ms** for every connected player.

This script tails ``docker logs`` for that prefix, maintains last-known XYZ for the chosen name, and
writes that pose at your sampling interval — so inserts track the streamed simulation state even
between BIOBASE lines (they typically arrive every ~100 ms per player anyway).

Legacy option ``--combat-log-fallback`` also parses HL kill/damage bracket positions (sparse,
event-driven) if you deliberately want that approximation.

Requirements:
  pip install psycopg2-binary

Run on the Docker host where bb_cs2_server / bb_postgres containers exist.

Targets **bb_postgres** only — never assumes localhost:5432 alone (another Postgres on :5432
often lacks Biobase's "biobase" role). By default the script resolves **bb_postgres** via Docker:
``docker port bb_postgres`` if 5432 is published, else the container IPv4 on Docker networks.

Override anytime: ``BB_TEST_PG_DSN``, ``BB_TEST_PG_DSN_ADMIN``, ``BB_POSTGRES_HOST`` / ``BB_POSTGRES_PORT``, or ``--pg-dsn-*``.

Example:
  python3 tools/test_map_position.py --duration 60

Example with explicit bb_postgres host:
  BB_POSTGRES_HOST=192.168.1.10 BB_POSTGRES_PORT=5433 python3 tools/test_map_position.py
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen


# --- HL / combat log patterns (subset of bb_data_collection/app/log_parser.py) ---
_TS_RE = re.compile(
    r"^L\s+(\d{2}/\d{2}/\d{4})\s+-\s+(\d{2}:\d{2}:\d{2}):\s+(.+)$",
    re.DOTALL,
)

_KILL_RE = re.compile(
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r"(?:\s+\[([-\d\s\.]+)\])?"
    r"\s+killed\s+"
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r"(?:\s+\[([-\d\s\.]+)\])?"
    r'\s+with\s+"([^"]+)"(.*)',
    re.IGNORECASE,
)

# Matches bb_data_collection/app/log_parser.py (mp_logdetail 3).
_ATTACK_RE = re.compile(
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r"\s+\[([-\d\s\.]+)\]"
    r"\s+attacked\s+"
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r"\s+\[([-\d\s\.]+)\]"
    r'\s+with\s+"([^"]+)"'
    r'\s+\(damage\s+"(\d+)"\)'
    r'(?:\s+\(damage_armor\s+"(\d+)"\))?'
    r'(?:\s+\(health\s+"(\d+)"\))?'
    r'(?:\s+\(armor\s+"(\d+)"\))?'
    r'(?:\s+\(hitgroup\s+"([^"]+)"\))?',
    re.IGNORECASE,
)

_BIOBASE_POS_PREFIX = "BIOBASE_POS_JSON "

_BB_PG_CONTAINER = "bb_postgres"


def _docker_bb_postgres_host_port() -> tuple[str, str] | None:
    """Prefer published host port mapping to bb_postgres (TCP 5432)."""
    try:
        proc = subprocess.run(
            ["docker", "port", _BB_PG_CONTAINER, "5432/tcp"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    for line in proc.stdout.strip().splitlines():
        rhs = line.split("->", 1)[-1].strip()
        if ":" not in rhs:
            continue
        host_part, port_str = rhs.rsplit(":", 1)
        host_part = host_part.strip().strip("[]")
        if port_str.isdigit():
            bind_host = "127.0.0.1" if host_part in ("0.0.0.0", "", "::") else host_part
            return bind_host, port_str
    return None


def _docker_bb_postgres_ipv4() -> str | None:
    """Use container IPv4 when not published (Linux host often can reach bridge IPs)."""
    try:
        proc = subprocess.run(
            [
                "docker",
                "inspect",
                "-f",
                "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}",
                _BB_PG_CONTAINER,
            ],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    for chunk in (proc.stdout or "").split():
        chunk = chunk.strip()
        if re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}", chunk):
            return chunk
    return None


def _resolve_bb_postgres_host_port() -> tuple[str, str, str]:
    """
    Returns (host, port, note) for connecting to bb_postgres as the biobase app user.

    Order: BB_POSTGRES_HOST (+ BB_POSTGRES_PORT / PGPORT), docker port map, docker IP,
    then PGHOST/PGPORT, then 127.0.0.1 with a warning.
    """
    bb_h = (os.environ.get("BB_POSTGRES_HOST") or "").strip()
    if bb_h:
        bb_p = (os.environ.get("BB_POSTGRES_PORT") or os.environ.get("PGPORT") or "5432").strip()
        return bb_h, bb_p, "from BB_POSTGRES_HOST / BB_POSTGRES_PORT (bb_postgres)"

    mapped = _docker_bb_postgres_host_port()
    if mapped:
        h, p = mapped
        return h, p, f"from docker port {_BB_PG_CONTAINER} (host publish)"

    dip = _docker_bb_postgres_ipv4()
    if dip:
        return dip, "5432", f"from docker inspect {_BB_PG_CONTAINER} (container IP)"

    ph = (os.environ.get("PGHOST") or "").strip()
    pp = (os.environ.get("PGPORT") or "5432").strip()
    if ph:
        return ph, pp, "from PGHOST/PGPORT (ensure this is bb_postgres, not another instance)"

    return (
        "127.0.0.1",
        "5432",
        "fallback 127.0.0.1 — likely wrong if bb_postgres is not published; set BB_POSTGRES_HOST "
        "or BB_TEST_PG_DSN",
    )


def _payload_from_line(line: str) -> str:
    m = _TS_RE.match(line.strip())
    return m.group(3) if m else line.strip()


def _entity_name(quoted_blob: str) -> str:
    mi = re.match(r'^"([^"]+)<', quoted_blob.strip())
    return mi.group(1).strip() if mi else ""


def _parse_vec(coords: str) -> tuple[float, float, float] | None:
    parts = coords.split()
    if len(parts) != 3:
        return None
    try:
        return float(parts[0]), float(parts[1]), float(parts[2])
    except ValueError:
        return None


@dataclass
class PositionState:
    pos_x: float | None = None
    pos_y: float | None = None
    pos_z: float | None = None
    source: str = "none"
    line_preview: str = ""
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False, compare=False)

    def update(
        self,
        xyz: tuple[float, float, float],
        *,
        src: str,
        preview: str,
    ) -> None:
        with self._lock:
            self.pos_x, self.pos_y, self.pos_z = xyz
            self.source = src
            self.line_preview = preview[:500]

    def snapshot(self) -> tuple[float | None, float | None, float | None, str, str]:
        with self._lock:
            return (
                self.pos_x,
                self.pos_y,
                self.pos_z,
                self.source,
                self.line_preview,
            )


def ingest_line(
    payload: str,
    target: str,
    state: PositionState,
    raw_trim: str,
    *,
    combat_log_fallback: bool,
) -> None:
    marker = payload.find(_BIOBASE_POS_PREFIX)
    if marker >= 0:
        rest = payload[marker + len(_BIOBASE_POS_PREFIX) :].strip()
        try:
            data: dict[str, Any] = json.loads(rest)
        except json.JSONDecodeError:
            return
        pname = str(data.get("player", "")).strip()
        if pname != target.strip():
            return
        pos = data.get("pos")
        if isinstance(pos, list) and len(pos) == 3:
            try:
                xyz = float(pos[0]), float(pos[1]), float(pos[2])
            except (TypeError, ValueError):
                return
            state.update(xyz, src="biobase_pos_json", preview=raw_trim)
        return

    if not combat_log_fallback:
        return

    km = _KILL_RE.match(payload)
    if km:
        att_s, att_p, vic_s, vic_p, _weapon, _rest = km.groups()
        att_n = _entity_name(att_s)
        vic_n = _entity_name(vic_s)
        if att_n == target and att_p:
            xyz = _parse_vec(att_p)
            if xyz:
                state.update(xyz, src="kill_attacker_pos", preview=raw_trim)
                return
        if vic_n == target and vic_p:
            xyz = _parse_vec(vic_p)
            if xyz:
                state.update(xyz, src="kill_victim_pos", preview=raw_trim)
                return

    am = _ATTACK_RE.match(payload)
    if am:
        att_s, att_p, vic_s, vic_p, *_damage_meta = am.groups()
        att_n = _entity_name(att_s)
        vic_n = _entity_name(vic_s)
        if att_n == target and att_p:
            xyz = _parse_vec(att_p)
            if xyz:
                state.update(xyz, src="damage_attacker_pos", preview=raw_trim)
                return
        if vic_n == target and vic_p:
            xyz = _parse_vec(vic_p)
            if xyz:
                state.update(xyz, src="damage_victim_pos", preview=raw_trim)
                return


def _http_json(method: str, url: str, body: dict | None, token: str | None) -> Any:
    data = json.dumps(body or {}).encode("utf-8") if body is not None or method.upper() == "POST" else None
    hdr = {"Content-Type": "application/json", "Accept": "application/json"}
    if token:
        hdr["X-Api-Key"] = token
    req = Request(url, data=data if method.upper() == "POST" else None, headers=hdr, method=method)
    with urlopen(req, timeout=30) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw.strip() else {}


def _docker_log_follow(
    container: str,
    stop: threading.Event,
    state: PositionState,
    target: str,
    combat_log_fallback: bool,
) -> None:
    cmd = ["docker", "logs", "-f", "--tail", "0", container]
    proc: subprocess.Popen[str] | None = None
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert proc.stdout is not None
        while not stop.is_set():
            line = proc.stdout.readline()
            if not line:
                break
            pay = _payload_from_line(line)
            ingest_line(
                pay,
                target,
                state,
                line.strip(),
                combat_log_fallback=combat_log_fallback,
            )
    finally:
        if proc:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()


def _pick_random_bot_players(status_json: dict[str, Any]) -> str:
    players = status_json.get("players") or []
    bots = [p for p in players if str(p.get("steamid") or "").upper() == "BOT" and p.get("name")]
    if not bots:
        raise RuntimeError("No BOT players in /api/status — wait for bots to spawn or adjust bot_quota.")
    return str(random.choice(bots)["name"]).strip()


def _ensure_bb_test(ds_admin: str) -> None:
    import psycopg2

    conn = psycopg2.connect(ds_admin)
    conn.set_session(autocommit=True)
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT 1 FROM pg_database WHERE datname = %s LIMIT 1
            """,
            ("bb_test",),
        )
        if cur.fetchone() is None:
            cur.execute("CREATE DATABASE bb_test")
    conn.close()


def _ensure_table(ds_bb_test: str) -> None:
    import psycopg2

    ddl = """
    CREATE TABLE IF NOT EXISTS test_map_position (
      id               bigserial primary key,
      sampled_at       timestamptz NOT NULL DEFAULT now(),
      player_name      text NOT NULL,
      pos_x double precision,
      pos_y double precision,
      pos_z double precision,
      pos_source       text NOT NULL DEFAULT 'none',
      line_preview     text,
      ingest_note      text
    );
    """
    conn = psycopg2.connect(ds_bb_test)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(ddl)
    conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="POC map position sampler → bb_test.test_map_position")
    parser.add_argument(
        "--cs2-url",
        default=os.environ.get("CS2_CONTROL_URL", "http://127.0.0.1:8765"),
        help="bb_cs2_control base URL",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=60.0,
        help="Run this many seconds then exit (Ctrl+C anytime)",
    )
    parser.add_argument(
        "--interval-ms",
        type=int,
        default=100,
        help="Sampling / insert cadence",
    )
    parser.add_argument(
        "--docker-container",
        default=os.environ.get("CS2_CONTAINER", "bb_cs2_server"),
        help="Container name passed to docker logs -f",
    )
    parser.add_argument(
        "--combat-log-fallback",
        action="store_true",
        help=(
            "Parse HL combat kill/damage lines for [x y z]. Default relies on BIOBASE_POS_JSON from "
            "BiobasePosEmitter (included with bb_cs2_server image rebuild)."
        ),
    )

    rp_host, rp_port, rp_src = _resolve_bb_postgres_host_port()
    pg_user = os.environ.get("POSTGRES_USER", "biobase")
    pg_pass = os.environ.get("POSTGRES_PASSWORD", "biobase")
    dsn_bb_test_default = (
        os.environ.get("BB_TEST_PG_DSN")
        or f"postgresql://{quote(pg_user)}:{quote(pg_pass)}@{rp_host}:{rp_port}/bb_test"
    )
    dsn_admin_default = (
        os.environ.get("BB_TEST_PG_DSN_ADMIN")
        or f"postgresql://{quote(pg_user)}:{quote(pg_pass)}@{rp_host}:{rp_port}/postgres"
    )

    parser.add_argument(
        "--pg-dsn-admin",
        default=dsn_admin_default,
        help="Used only to CREATE DATABASE bb_test when missing",
    )
    parser.add_argument(
        "--pg-dsn-bb-test",
        default=dsn_bb_test_default,
        help="Connection string for INSERTs into bb_test",
    )
    ns = parser.parse_args()

    try:
        import psycopg2  # noqa: F401  # pylint: disable=unused-import
    except ImportError:
        print("Install dependency: pip install psycopg2-binary", file=sys.stderr)
        return 1

    interval_s = max(0.005, ns.interval_ms / 1000.0)
    tok = (
        os.environ.get("BB_CS2_CONTROL_TOKEN")
        or os.environ.get("CS2_CONTROL_TOKEN")
        or ""
    ).strip()

    print("Posting /api/bots/start …")
    try:
        r = _http_json("POST", ns.cs2_url.rstrip("/") + "/api/bots/start", {}, tok or None)
    except (HTTPError, URLError, TimeoutError, ConnectionError, OSError) as e:
        print(f"Bots start failed: {e}", file=sys.stderr)
        return 1
    print(f"Bots API: {json.dumps(r)}")

    print("Waiting for bots to spawn (up to 30s) …")
    pname: str | None = None
    sj: dict[str, Any] = {}
    bot_deadline = time.monotonic() + 30.0
    while time.monotonic() < bot_deadline:
        time.sleep(2.5)
        try:
            sj = _http_json("GET", ns.cs2_url.rstrip("/") + "/api/status", None, tok or None)
        except (HTTPError, URLError, TimeoutError, ConnectionError, OSError):
            continue
        try:
            pname = _pick_random_bot_players(sj)
            break
        except RuntimeError:
            pass
    if pname is None:
        print("No BOT players after 30s — check bot_quota and server status.", file=sys.stderr)
        return 1
    headline = sj.get("headline")
    pmap = sj.get("map")
    print(f"Picked BOT player: <<{pname}>> map={pmap} ({headline})")
    if ns.combat_log_fallback:
        print("Position ingest: BIOBASE_POS_JSON plus HL combat (--combat-log-fallback)")
    else:
        print(
            "Position ingest: BIOBASE_POS_JSON (~100 ms) from BiobasePosEmitter "
            "(rebuild bb_cs2_server if BIOBASE_POS_JSON never appears)",
        )

    pu = urlparse(ns.pg_dsn_bb_test)
    phost = pu.hostname or "?"
    pport = pu.port or 5432
    if not os.environ.get("BB_TEST_PG_DSN"):
        print(f"Postgres bb_test → {phost}:{pport} (resolved: {rp_src})")
    else:
        print(f"Postgres bb_test → {phost}:{pport} (from BB_TEST_PG_DSN)")

    if (
        not os.environ.get("BB_TEST_PG_DSN")
        and phost == "127.0.0.1"
        and "fallback" in rp_src
        and pport == 5432
    ):
        print(
            "Warning: connecting to localhost:5432 — if you see errors about missing role "
            "\"biobase\", set BB_POSTGRES_HOST / BB_POSTGRES_PORT or BB_TEST_PG_DSN to bb_postgres.",
            file=sys.stderr,
        )

    stop = threading.Event()
    pos_state = PositionState()

    thr = threading.Thread(
        target=_docker_log_follow,
        args=(ns.docker_container, stop, pos_state, pname, ns.combat_log_fallback),
        daemon=True,
    )
    thr.start()

    print("Ensuring bb_test + test_map_position …")
    try:
        _ensure_bb_test(ns.pg_dsn_admin)
        _ensure_table(ns.pg_dsn_bb_test)
    except Exception as e:  # noqa: BLE001
        print(f"Postgres DDL failed ({e})", file=sys.stderr)
        print(
            "Hint: use bb_postgres only — BB_POSTGRES_HOST, BB_TEST_PG_DSN, or rely on Docker "
            "resolution (docker port / container IP for bb_postgres).",
            file=sys.stderr,
        )
        stop.set()
        return 1

    import psycopg2

    t_end = time.monotonic() + ns.duration

    def _shutdown(_sig: int, _frame: object) -> None:
        stop.set()

    signal.signal(signal.SIGINT, _shutdown)

    print(f"Tailing docker logs container={ns.docker_container!r} inserting every {ns.interval_ms} ms …")

    inserted = 0
    conn = psycopg2.connect(ns.pg_dsn_bb_test)
    conn.autocommit = True
    try:
        while not stop.is_set() and time.monotonic() < t_end:
            t0 = time.monotonic()
            px, py, pz, src, preview = pos_state.snapshot()
            note = (
                None
                if src != "none"
                else (
                    "waiting for BIOBASE_POS_JSON from BiobasePosEmitter (~100 ms) — rebuild bb_cs2_server"
                    if not ns.combat_log_fallback
                    else (
                        "still no coords — BIOBASE absent and no HL bracket positions yet "
                        "(mp_logdetail 3 + engagements)"
                    )
                )
            )
            sampled = datetime.now(UTC)

            sql = """
            INSERT INTO test_map_position
              (sampled_at, player_name, pos_x, pos_y, pos_z, pos_source, line_preview, ingest_note)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
            """
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        sql,
                        (
                            sampled,
                            pname,
                            px,
                            py,
                            pz,
                            src,
                            preview if preview else None,
                            note,
                        ),
                    )
                inserted += 1
            except Exception as e:  # noqa: BLE001
                print(f"INSERT error: {e}", file=sys.stderr)

            xyz_s = ",".join("" if v is None else f"{v:.2f}" for v in (px, py, pz))
            print(f"{sampled.isoformat()}  {pname:12}  ({xyz_s})  [{src}]")

            drift = interval_s - (time.monotonic() - t0)
            if drift > 0:
                time.sleep(drift)

    finally:
        conn.close()

    stop.set()
    thr.join(timeout=6)
    print(f"Done. Rows inserted ~{inserted}. DB=bb_test table=test_map_position")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
