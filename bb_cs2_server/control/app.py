"""
Web UI API for CS2 bot game start/stop and map change (RCON via mcrcon). Same commands as bots_*.sh.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

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
_MAP_WORKSHOP_ID = re.compile(r"^[0-9]{6,20}$")
_MAP_STOCK = re.compile(r"^[a-zA-Z0-9_]{1,64}$")

# Matches CS2 `status` player rows (format differs from CS:GO).
# Header:  id  time  ping  loss  state  rate  [adr]  name
# Bot row: "   0      BOT    0    0     active      0 'BotName '"
# Player:  "   2    12:45   45    0     active 196608 '1.2.3.4:27005' 'HumanName'"
# Strategy: capture id/time/ping/loss/state, then take the LAST single-quoted
# field on the line as the player name (backtracking handles optional address).
_PLAYER_ROW_RE = re.compile(
    r"^\s+(\d+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\w+)\s+\d+"  # id, time/BOT, ping, loss, state, rate
    r"(?:\s+'[^']*')?"                                     # optional address (e.g. '1.2.3.4:27005')
    r"\s+'([^']*)'",                                        # name (last single-quoted field)
    re.MULTILINE,
)


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


def parse_map_target(raw: str) -> tuple[str, str]:
    """Return (token, kind) where kind is 'stock' or 'workshop'."""
    s = raw.strip()
    if not s:
        raise ValueError("empty map")
    if _MAP_WORKSHOP_ID.fullmatch(s):
        return s, "workshop"
    if s.isdigit():
        raise ValueError("workshop map id must be 6-20 digits")
    if not _MAP_STOCK.fullmatch(s):
        raise ValueError("map name must be alphanumeric/underscore or a workshop id")
    return s, "stock"


def require_token(authorization: str | None, x_api_key: str | None) -> None:
    if not CONTROL_TOKEN:
        return
    if x_api_key == CONTROL_TOKEN:
        return
    if authorization and authorization.startswith("Bearer ") and authorization[7:] == CONTROL_TOKEN:
        return
    raise HTTPException(status_code=401, detail="Unauthorized")


def parse_players(text: str) -> list[dict]:
    """Extract per-player rows from `status` command output."""
    text = _strip_ansi(text)
    players = []
    for m in _PLAYER_ROW_RE.finditer(text):
        slot, time_or_bot, ping, loss, state, name = m.groups()
        is_bot = time_or_bot.upper() == "BOT"
        players.append(
            {
                "userid": int(slot),
                "name": name.strip(),
                "steamid": "BOT" if is_bot else None,
                "connected": None if is_bot else time_or_bot,
                "ping": int(ping),
                "loss": int(loss),
                "state": state,
            }
        )
    return players


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
        "players": parse_players(text),
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
        "log on",
        "sv_logecho 1",
        # Required for HL combat lines with attacker/victim [x y z] + damage fields (Docker logs ingest).
        "mp_logdetail 3",
        "mp_warmup_end",
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


class MapChangeBody(BaseModel):
    map: str = Field(..., min_length=1, max_length=96)


@app.post("/api/map")
def api_change_map(
    body: MapChangeBody,
    authorization: str | None = Header(None),
    x_api_key: str | None = Header(None, alias="X-Api-Key"),
) -> JSONResponse:
    require_token(authorization, x_api_key)
    try:
        target, kind = parse_map_target(body.map)
    except ValueError as e:
        return JSONResponse(
            {"ok": False, "error": str(e)},
            status_code=400,
        )
    if kind == "workshop":
        code, out = mcrcon_run("host_workshop_map", target)
        if code != 0:
            return JSONResponse(
                {
                    "ok": False,
                    "error": f"host_workshop_map {target!r} exit {code}: {out[:500]}",
                },
                status_code=502,
            )
        return JSONResponse({"ok": True, "message": f"Workshop map {target} requested."})

    # Stock maps: try `map` first (reliable on many CS2 dedicated setups), then `changelevel`.
    last_code, last_out = -1, ""
    for verb in ("map", "changelevel"):
        code, out = mcrcon_run(verb, target)
        last_code, last_out = code, out
        if code == 0:
            return JSONResponse({"ok": True, "message": f"Changing map to {target} ({verb})."})
    return JSONResponse(
        {
            "ok": False,
            "error": f"map/changelevel failed (last exit {last_code}): {last_out[:500]}",
        },
        status_code=502,
    )


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

