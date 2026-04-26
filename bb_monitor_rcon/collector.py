#!/usr/bin/env python3
"""
bb_monitor_rcon: Source RCON poller (mcrcon) + Prometheus /metrics.
"""

from __future__ import annotations

import logging
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from prometheus_client import Counter, Gauge, generate_latest

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("bb_monitor_rcon")

# --- Prometheus ----------------------------------------------------------------

rcon_mcrcon_total = Counter("rcon_mcrcon_runs_total", "mcrcon status runs", ["result"])

rcon_up = Gauge("rcon_up", "1 if last mcrcon for status returned exit 0")
rcon_status_players = Gauge(
    "rcon_status_players",
    "Parsed player/human count from status (-1 if unknown)",
)
rcon_status_max_players = Gauge(
    "rcon_status_max_players",
    "Parsed max players from status (-1 if unknown)",
)
rcon_status_bots = Gauge(
    "rcon_status_bots",
    "Parsed bot count from status (-1 if unknown)",
)
rcon_status_parse_ok = Gauge(
    "rcon_status_parse_ok",
    "1 if status text was parsed (map/hostname/players/...)",
)
rcon_last_scrape_duration_seconds = Gauge(
    "rcon_last_scrape_duration_seconds",
    "Wall time of last mcrcon status run",
)

# --- status parsing (Source / CS2, best effort) ----------------------------------

_RE_MAP = re.compile(r"^map\s*:\s*(\S+)", re.IGNORECASE | re.MULTILINE)
_RE_HOST = re.compile(r"^hostname\s*:\s*(.+)$", re.IGNORECASE | re.MULTILINE)
# "players : 2 (2 max) (0 humans)" (CS2-style)
_RE_PLAYERS_MAX = re.compile(
    r"players\s*:\s*(\d+)(?:\s*active)?\s*\((\d+)\s*max\)[^\n]*\((\d+)\s*humans\)",
    re.IGNORECASE,
)


def parse_status_text(text: str) -> dict[str, Any]:
    out: dict[str, Any] = {
        "hostname": "",
        "map": "",
        "players": None,
        "max": None,
        "bots": None,
        "parse_ok": False,
    }
    if not (text and text.strip()):
        return out
    m = _RE_MAP.search(text)
    if m:
        out["map"] = m.group(1).strip()
    h = _RE_HOST.search(text)
    if h:
        out["hostname"] = h.group(1).strip()
    pm = _RE_PLAYERS_MAX.search(text)
    if pm:
        try:
            out["max"] = int(pm.group(2))
            out["players"] = int(pm.group(3))
            out["parse_ok"] = True
        except (ValueError, IndexError):
            pass
    if not out["parse_ok"]:
        m2 = re.search(
            r"players\s*:\s*(\d+)(?:\s*active)?\s*\((\d+)\s*max\)",
            text,
            re.IGNORECASE,
        )
        if m2:
            try:
                out["players"] = int(m2.group(1))
                out["max"] = int(m2.group(2))
                out["parse_ok"] = True
            except (ValueError, IndexError):
                pass
    if out.get("map") or out.get("hostname"):
        out["parse_ok"] = True
    if "# userid" in text or "#     userid" in text:
        if out.get("players") is None and "#" in text:
            body = text[text.find("#") :]
            n = len(re.findall(r"^\d+\s+", body, re.MULTILINE))
            if n > 0:
                out["players"] = n
                out["parse_ok"] = True
    return out


def mcrcon_run(
    mcrcon_bin: str, host: str, port: int, password: str, *command_parts: str
) -> tuple[int, str, float]:
    t0 = time.perf_counter()
    cmd = [
        mcrcon_bin,
        "-H",
        host,
        "-P",
        str(port),
        "-p",
        password,
        *command_parts,
    ]
    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=float(os.environ.get("RCON_TIMEOUT", "8")),
        )
        out = (p.stdout or "") + (p.stderr or "")
        elapsed = time.perf_counter() - t0
        label = "ok" if p.returncode == 0 else f"err_{p.returncode}"
        rcon_mcrcon_total.labels(label).inc()
        return p.returncode, out.strip(), elapsed
    except subprocess.TimeoutExpired as e:
        elapsed = time.perf_counter() - t0
        rcon_mcrcon_total.labels("timeout").inc()
        err = (e.stdout or "") + (e.stderr or "")
        return -1, (err or "timeout").strip(), elapsed
    except OSError as e:
        elapsed = time.perf_counter() - t0
        rcon_mcrcon_total.labels("oserror").inc()
        return -1, str(e), elapsed


def one_poll() -> None:
    host = os.environ.get("RCON_HOST", "bb_cs2_server")
    port = int(os.environ.get("RCON_PORT", "27015"))
    pw = os.environ.get("RCON_PASSWORD", "changeme")
    mcp = os.environ.get("MCRCON_BIN", "/usr/local/bin/mcrcon")
    code, text, elapsed = mcrcon_run(mcp, host, port, pw, "status")
    rcon_up.set(1.0 if code == 0 else 0.0)
    rcon_last_scrape_duration_seconds.set(elapsed)
    parsed = parse_status_text(text)
    rcon_status_parse_ok.set(1.0 if parsed.get("parse_ok") else 0.0)
    p = parsed.get("players")
    m = parsed.get("max")
    b = parsed.get("bots")
    rcon_status_players.set(p if p is not None else -1.0)
    rcon_status_max_players.set(m if m is not None else -1.0)
    rcon_status_bots.set(b if b is not None else -1.0)
    if code == 0 and text and parsed.get("parse_ok"):
        log.info(
            "rcon map=%r hostname=%r players=%s max=%s",
            (parsed.get("map") or "")[:120],
            (parsed.get("hostname") or "")[:120],
            parsed.get("players"),
            parsed.get("max"),
        )
    if code != 0:
        log.warning("mcrcon status exit=%s", code)
    else:
        log.debug("status parsed in %.3fs: %s", elapsed, {**parsed, "text": text[:200]})


def poller_thread(interval: float) -> None:
    while True:
        try:
            one_poll()
        except Exception as e:
            log.exception("poll: %s", e)
            rcon_up.set(0.0)
        time.sleep(max(1.0, interval))


def main() -> None:
    interval = float(os.environ.get("RCON_POLL_INTERVAL", "10"))
    mport = int(os.environ.get("METRICS_PORT", "9105"))
    t = threading.Thread(
        target=poller_thread, args=(interval,), daemon=True, name="rcon-poll"
    )
    t.start()

    class H(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path in ("/", "/health"):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok\n")
                return
            if self.path == "/metrics":
                data = generate_latest() + b"\n"
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; version=0.0.4")
                self.end_headers()
                self.wfile.write(data)
                return
            self.send_error(404)

        def log_message(self, fmt: str, *a: Any) -> None:
            return

    log.info(
        "metrics :%s poll=%.1fs rcon %s:%s",
        mport,
        interval,
        os.environ.get("RCON_HOST", "bb_cs2_server"),
        os.environ.get("RCON_PORT", "27015"),
    )
    httpd = ThreadingHTTPServer(("0.0.0.0", mport), H)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
