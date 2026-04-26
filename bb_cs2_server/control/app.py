"""
Web UI API for CS2 bot game start/stop (RCON via mcrcon). Same commands as bots_*.sh.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse, JSONResponse

RCON_HOST = os.environ.get("RCON_HOST", "bb_cs2_server")
RCON_PORT = int(os.environ.get("RCON_PORT", "27015"))
RCON_PASSWORD = os.environ.get("RCON_PASSWORD", os.environ.get("RCON_PW", "changeme"))
MCRCON_BIN = os.environ.get("MCRCON_BIN", "/usr/local/bin/mcrcon")
RCON_TIMEOUT = float(os.environ.get("RCON_TIMEOUT", "15"))

BOT_QUOTA = os.environ.get("CS2_BOT_QUOTA", "10")
BOT_MODE = os.environ.get("CS2_BOT_QUOTA_MODE", "fill")
BOT_DIFF = os.environ.get("CS2_BOT_DIFFICULTY", "1")
CONTROL_TOKEN = os.environ.get("BB_CS2_CONTROL_TOKEN", "").strip()

STATIC = Path(__file__).resolve().parent / "static"
app = FastAPI(title="bb_cs2_control", version="1.0.0")

_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _strip_ansi(s: str) -> str:
    return _ANSI.sub("", s)


def mcrcon_run(*command_parts: str) -> tuple[int, str]:
    cmd = [MCRCON_BIN, "-H", RCON_HOST, "-P", str(RCON_PORT), "-p", RCON_PASSWORD, *command_parts]
    p = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=RCON_TIMEOUT,
    )
    out = (p.stdout or "") + (p.stderr or "")
    return p.returncode, out.strip()


def require_token(authorization: str | None, x_api_key: str | None) -> None:
    if not CONTROL_TOKEN:
        return
    if x_api_key == CONTROL_TOKEN:
        return
    if authorization and authorization.startswith("Bearer ") and authorization[7:] == CONTROL_TOKEN:
        return
    raise HTTPException(status_code=401, detail="Unauthorized")


def parse_status(text: str) -> dict:
    text = _strip_ansi(text)
    humans: int | None = None
    bots: int | None = None
    m = re.search(
        r"players\s*:\s*(\d+)\s*humans,\s*(\d+)\s*bots",
        text,
        re.IGNORECASE,
    )
    if m:
        try:
            humans = int(m.group(1))
            bots = int(m.group(2))
        except ValueError:
            pass

    map_name = None
    m2 = re.search(r"\[1:\s*([a-z0-9_]+)\s*\|", text, re.IGNORECASE)
    if m2:
        map_name = m2.group(1)
    if not map_name:
        m3 = re.search(r"^map\s*:\s*(\S+)", text, re.IGNORECASE | re.MULTILINE)
        if m3:
            map_name = m3.group(1).strip()

    host_m = re.search(r"hostname\s*:\s*(.+)$", text, re.IGNORECASE | re.MULTILINE)
    hostname = host_m.group(1).strip() if host_m else None

    server_running = "Server:" in text and "Running" in text

    if not server_running and "Server:" in text:
        headline = "Server not responding as running"
    elif humans is not None and bots is not None and bots > 0:
        headline = "Bot game running"
    elif humans is not None and bots is not None and bots == 0:
        headline = "No bots in game"
    else:
        headline = "Status partially parsed"

    return {
        "headline": headline,
        "humans": humans,
        "bots": bots,
        "map": map_name,
        "hostname": hostname,
        "server_listed_running": server_running,
        "rcon_ok": True,
        "rcon_code": 0,
    }


@app.get("/api/status")
def api_status() -> JSONResponse:
    code, text = mcrcon_run("status")
    if code != 0:
        return JSONResponse(
            {
                "headline": "RCON failed",
                "humans": None,
                "bots": None,
                "map": None,
                "hostname": None,
                "server_listed_running": False,
                "rcon_ok": False,
                "rcon_code": code,
                "rcon_error": text[:2000] if text else None,
                "raw": text[:4000] if text else "",
            }
        )
    data = parse_status(text)
    return JSONResponse(data)


@app.post("/api/bots/start")
def api_bots_start(
    authorization: str | None = Header(None),
    x_api_key: str | None = Header(None, alias="X-Api-Key"),
) -> JSONResponse:
    require_token(authorization, x_api_key)
    steps = [
        "bot_join_after_player 0",
        f"bot_quota {BOT_QUOTA}",
        f"bot_quota_mode {BOT_MODE}",
        f"bot_difficulty {BOT_DIFF}",
        "mp_restartgame 1",
    ]
    last_err = None
    for s in steps:
        code, out = mcrcon_run(s)
        if code != 0:
            last_err = f"{s!r} exit {code}: {out[:500]}"
            return JSONResponse({"ok": False, "error": last_err, "step": s}, status_code=502)
    return JSONResponse({"ok": True, "message": "Bot game start commands sent."})


@app.post("/api/bots/stop")
def api_bots_stop(
    authorization: str | None = Header(None),
    x_api_key: str | None = Header(None, alias="X-Api-Key"),
) -> JSONResponse:
    require_token(authorization, x_api_key)
    for s in ("bot_kick", "bot_quota 0"):
        code, out = mcrcon_run(s)
        if code != 0:
            return JSONResponse(
                {"ok": False, "error": f"{s!r} exit {code}: {out[:500]}", "step": s},
                status_code=502,
            )
    return JSONResponse({"ok": True, "message": "Bots cleared."})


@app.get("/")
def index() -> FileResponse:
    p = STATIC / "bb_cs2_bot_game.html"
    if not p.is_file():
        raise HTTPException(status_code=500, detail="static UI missing")
    return FileResponse(p, media_type="text/html; charset=utf-8")


@app.get("/bb_cs2_bot_game.html", include_in_schema=False)
def ui_named() -> FileResponse:
    return index()


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}

