"""
Parse CS2 server log lines into structured game events, round stats, and movement samples.

CS2 server logs (with sv_logecho 1) use the standard HL/Source engine log format:
  L MM/DD/YYYY - HH:MM:SS: <payload>

Supported event_type values in biobase_cs2_game_event:
  kill            — player killed player  (when logged via plugin)
  round_start     — World triggered "Round_Start"
  round_end       — World triggered "Round_End"
  game_over       — World triggered "Game_Over"
  game_commencing — World triggered "Game_Commencing"
  world_<x>       — any other World triggered event
  team_score      — Team "X" scored "N" with "M" players
  connect         — player connected
  disconnect      — player disconnected
  say / say_team  — player chat
  freeze_period   — Starting Freeze period
  match_status    — MatchStatus: Score: ... line
  player_reset    — "Name<slot><BOT><team>" OnPreResetRound
  team_change     — "Name<slot><BOT><team>" ChangeTeam()
  biobase_pos     — BIOBASE_POS_JSON structured plugin line
  biobase_event   — BIOBASE_EVENT_JSON structured plugin line

Round stats (biobase_cs2_round_stats) come from CS2 JSON_BEGIN...JSON_END blocks
emitted at the start of each round with cumulative per-player stats from prior rounds.

Fields: accountid, team, money, kills, deaths, assists, dmg, hsp, kdr, adr, mvp,
        ef, ud, 3k, 4k, 5k, clutchk, firstk, pistolk, sniperk, blindk, bombk,
        firedmg, uniquek, dinks, chickenk

BIOBASE plugin protocol (CS2 plugin emits to console):
  BIOBASE_POS_JSON   {"player":"...","steamid":"BOT","tick":N,
                      "pos":[x,y,z],"vel":[vx,vy,vz],"speed":s,
                      "yaw":y,"pitch":p,"on_ground":bool}
  BIOBASE_EVENT_JSON {"type":"jump","player":"...","steamid":"...", ...}
"""
from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone
from typing import Any

log = logging.getLogger(__name__)

# HL/Source log timestamp prefix: L MM/DD/YYYY - HH:MM:SS: <rest>
_TS_RE = re.compile(
    r"^L\s+(\d{2}/\d{2}/\d{4})\s+-\s+(\d{2}:\d{2}:\d{2}):\s+(.+)$",
    re.DOTALL,
)

# CS2 player entity in angle brackets: "Name<slot><steamid><team>"
_ENTITY_RE = re.compile(r'^"([^"]+)<(\d+)><([^>]*)><([^>]*)>"$')

# Kill: "att<slot><steam><team>" [ax ay az] killed "vic<slot><steam><team>" [vx vy vz] with "weapon" [(headshot)]
# CS2 includes [x y z] coords after both entities; brackets are optional for compatibility.
_KILL_RE = re.compile(
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r'(?:\s+\[([-\d\s\.]+)\])?'      # optional attacker position [x y z]
    r'\s+killed\s+'
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r'(?:\s+\[([-\d\s\.]+)\])?'      # optional victim position [x y z]
    r'\s+with\s+"([^"]+)"(.*)',
    re.IGNORECASE,
)

# Assist: "att<slot><steam><team>" assisted killing "vic<slot><steam><team>"
_ASSIST_RE = re.compile(
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")\s+assisted\s+killing\s+("(?:[^"]+)<\d+><[^>]*><[^>]*>")',
    re.IGNORECASE,
)

# Damage (mp_logdetail 3): "att<..>" [ax ay az] attacked "vic<..>" [vx vy vz]
#   with "weapon" (damage "N") (damage_armor "N") (health "N") (armor "N") (hitgroup "X")
_ATTACK_RE = re.compile(
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r'\s+\[([-\d\s\.]+)\]'           # attacker position (required when logdetail >=1)
    r'\s+attacked\s+'
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")'
    r'\s+\[([-\d\s\.]+)\]'           # victim position
    r'\s+with\s+"([^"]+)"'
    r'\s+\(damage\s+"(\d+)"\)'
    r'(?:\s+\(damage_armor\s+"(\d+)"\))?'
    r'(?:\s+\(health\s+"(\d+)"\))?'
    r'(?:\s+\(armor\s+"(\d+)"\))?'
    r'(?:\s+\(hitgroup\s+"([^"]+)"\))?',
    re.IGNORECASE,
)

# World triggered "EventName"
_WORLD_TRIG_RE = re.compile(r'^World triggered\s+"([^"]+)"', re.IGNORECASE)

# Team "X" scored "N" with "M" players
_TEAM_SCORE_RE = re.compile(
    r'^Team\s+"([^"]+)"\s+scored\s+"(\d+)"\s+with\s+"(\d+)"\s+players',
    re.IGNORECASE,
)

# Connect / disconnect
_CONNECT_RE = re.compile(
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")\s+(connected|disconnected)'
    r'(?:[^(]*\(reason\s+"([^"]*)"\))?',
    re.IGNORECASE,
)

# Say / say_team
_SAY_RE = re.compile(
    r'("(?:[^"]+)<\d+><[^>]*><[^>]*>")\s+say(_team)?\s+"([^"]*)"',
    re.IGNORECASE,
)

# CS2-specific: Starting Freeze period
_FREEZE_RE = re.compile(r'^Starting Freeze period', re.IGNORECASE)

# CS2-specific: MatchStatus: Score: X:Y on map "MAP" RoundsPlayed: N
_MATCH_STATUS_RE = re.compile(
    r'^MatchStatus:\s+Score:\s+(\d+):(\d+)\s+on\s+map\s+"([^"]+)"\s+RoundsPlayed:\s+(\d+)',
    re.IGNORECASE,
)

# CS2-specific entity events (no HL prefix on entity line, line contains entity + event)
# "Name<slot><BOT><team>" OnPreResetRound => CTMDBG, team X  will switch Y Z
_RESET_ROUND_RE = re.compile(
    r'^"([^"]+)<(\d+)><([^>]*)><([^>]*)>"\s+OnPreResetRound\s*=>\s*CTMDBG,\s*team\s+(\d+)'
    r'\s+will switch\s+(\d+)',
    re.IGNORECASE,
)

# "Name<slot><BOT><team>" ChangeTeam() CTMDBG , team X, req team Y willSwitch Z, T
_CHANGE_TEAM_RE = re.compile(
    r'^"([^"]+)<(\d+)><([^>]*)><([^>]*)>"\s+ChangeTeam\(\)\s+CTMDBG\s*,\s*team\s+(\d+)'
    r',\s*req\s+team\s+(\d+)',
    re.IGNORECASE,
)

# BIOBASE structured JSON lines (plugin protocol)
_BIOBASE_POS_RE = re.compile(r"BIOBASE_POS_JSON\s+(\{.+\})\s*$")
_BIOBASE_EVENT_RE = re.compile(r"BIOBASE_EVENT_JSON\s+(\{.+\})\s*$")

# JSON_BEGIN / JSON_END block markers
_JSON_BEGIN_RE = re.compile(r"^JSON_BEGIN\{", re.IGNORECASE)
_JSON_END_RE = re.compile(r"^\}\}JSON_END", re.IGNORECASE)

_WORLD_TRIGGER_MAP = {
    "round_start": "round_start",
    "round_end": "round_end",
    "game_over": "game_over",
    "game_commencing": "game_commencing",
    "intermission_win_panel": "intermission",
    "match_start": "match_start",
}

# Field order in CS2 JSON_BEGIN round_stats block
_ROUND_STAT_FIELDS = [
    "accountid", "team", "money", "kills", "deaths", "assists",
    "dmg", "hsp", "kdr", "adr", "mvp", "ef", "ud",
    "kills_3k", "kills_4k", "kills_5k",
    "clutchk", "firstk", "pistolk", "sniperk", "blindk", "bombk",
    "firedmg", "uniquek", "dinks", "chickenk",
]

# Types for each field (index-aligned with _ROUND_STAT_FIELDS)
_ROUND_STAT_TYPES: list[type] = [
    int, int, int, int, int, int,
    float, float, float, int, int, int, int,
    int, int, int,
    int, int, int, int, int, int,
    float, int, int, int,
]


def _parse_ts(date_str: str, time_str: str) -> datetime | None:
    try:
        return datetime.strptime(
            f"{date_str} {time_str}", "%m/%d/%Y %H:%M:%S"
        ).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _parse_entity(s: str) -> tuple[str, str, str, str] | None:
    m = _ENTITY_RE.match(s.strip())
    if not m:
        return None
    return m.group(1).strip(), m.group(2), m.group(3), m.group(4)


def _strip_hl_prefix(line: str) -> tuple[datetime | None, str]:
    """Strip HL log prefix. Returns (event_ts, payload)."""
    m = _TS_RE.match(line.strip())
    if m:
        return _parse_ts(m.group(1), m.group(2)), m.group(3)
    return None, line.strip()


def parse_line(line: str) -> dict[str, Any] | None:
    """
    Parse a single CS2 log line into a structured event dict.
    Returns None if the line does not match any known event pattern.
    """
    event_ts, payload = _strip_hl_prefix(line)

    # --- Kill ---
    km = _KILL_RE.match(payload)
    if km:
        att_str, att_pos, vic_str, vic_pos, weapon, rest = km.groups()
        att = _parse_entity(att_str)
        vic = _parse_entity(vic_str)
        hs = "(headshot)" in rest.lower() if rest else False
        extra: dict = {}
        if att_pos:
            coords = att_pos.split()
            if len(coords) == 3:
                extra["attacker_pos"] = [float(c) for c in coords]
        if vic_pos:
            coords = vic_pos.split()
            if len(coords) == 3:
                extra["victim_pos"] = [float(c) for c in coords]
        return {
            "event_type": "kill",
            "event_ts": event_ts,
            "attacker_name": att[0].strip() if att else None,
            "attacker_steamid": att[2] if att else None,
            "attacker_team": att[3] if att else None,
            "victim_name": vic[0].strip() if vic else None,
            "victim_steamid": vic[2] if vic else None,
            "victim_team": vic[3] if vic else None,
            "weapon": weapon,
            "headshot": hs,
            "extra_json": extra or None,
        }

    # --- Damage (mp_logdetail 3) ---
    am = _ATTACK_RE.match(payload)
    if am:
        att_str, att_pos, vic_str, vic_pos, weapon, dmg, dmg_armor, hp, armor, hitgroup = am.groups()
        att = _parse_entity(att_str)
        vic = _parse_entity(vic_str)
        extra = {"weapon": weapon}
        if att_pos:
            coords = att_pos.split()
            if len(coords) == 3:
                extra["attacker_pos"] = [float(c) for c in coords]
        if vic_pos:
            coords = vic_pos.split()
            if len(coords) == 3:
                extra["victim_pos"] = [float(c) for c in coords]
        if dmg is not None:
            extra["damage"] = int(dmg)
        if dmg_armor is not None:
            extra["damage_armor"] = int(dmg_armor)
        if hp is not None:
            extra["health_remaining"] = int(hp)
        if armor is not None:
            extra["armor_remaining"] = int(armor)
        if hitgroup:
            extra["hitgroup"] = hitgroup
        return {
            "event_type": "damage",
            "event_ts": event_ts,
            "attacker_name": att[0].strip() if att else None,
            "attacker_steamid": att[2] if att else None,
            "attacker_team": att[3] if att else None,
            "victim_name": vic[0].strip() if vic else None,
            "victim_steamid": vic[2] if vic else None,
            "victim_team": vic[3] if vic else None,
            "weapon": weapon,
            "headshot": False,
            "extra_json": extra,
        }

    # --- Assist ---
    asm = _ASSIST_RE.match(payload)
    if asm:
        att_str, vic_str = asm.groups()
        att = _parse_entity(att_str)
        vic = _parse_entity(vic_str)
        return {
            "event_type": "assist",
            "event_ts": event_ts,
            "attacker_name": att[0].strip() if att else None,
            "attacker_steamid": att[2] if att else None,
            "attacker_team": att[3] if att else None,
            "victim_name": vic[0].strip() if vic else None,
            "victim_steamid": vic[2] if vic else None,
            "victim_team": vic[3] if vic else None,
            "weapon": None,
            "headshot": False,
            "extra_json": None,
        }

    # --- World triggered ---
    wm = _WORLD_TRIG_RE.match(payload)
    if wm:
        trigger_raw = wm.group(1)
        event_type = _WORLD_TRIGGER_MAP.get(
            trigger_raw.lower(), f"world_{trigger_raw.lower()}"
        )
        return {
            "event_type": event_type,
            "event_ts": event_ts,
            "extra_json": {"trigger": trigger_raw},
        }

    # --- Team score ---
    tsm = _TEAM_SCORE_RE.match(payload)
    if tsm:
        team, score, num_players = tsm.groups()
        return {
            "event_type": "team_score",
            "event_ts": event_ts,
            "attacker_team": team,
            "extra_json": {
                "team": team,
                "score": int(score),
                "num_players": int(num_players),
            },
        }

    # --- Connect / disconnect ---
    cm = _CONNECT_RE.match(payload)
    if cm:
        player_str, action, reason = cm.groups()
        player = _parse_entity(player_str)
        event_type = "connect" if action.lower() == "connected" else "disconnect"
        return {
            "event_type": event_type,
            "event_ts": event_ts,
            "attacker_name": player[0] if player else None,
            "attacker_steamid": player[2] if player else None,
            "attacker_team": player[3] if player else None,
            "extra_json": {"reason": reason} if reason else None,
        }

    # --- Say / say_team ---
    sm = _SAY_RE.match(payload)
    if sm:
        player_str, team_suffix, message = sm.groups()
        player = _parse_entity(player_str)
        return {
            "event_type": "say_team" if team_suffix else "say",
            "event_ts": event_ts,
            "attacker_name": player[0] if player else None,
            "attacker_steamid": player[2] if player else None,
            "attacker_team": player[3] if player else None,
            "extra_json": {"message": message},
        }

    # --- CS2: Freeze period ---
    if _FREEZE_RE.match(payload):
        return {
            "event_type": "freeze_period",
            "event_ts": event_ts,
            "extra_json": None,
        }

    # --- CS2: MatchStatus score line ---
    msm = _MATCH_STATUS_RE.match(payload)
    if msm:
        score_ct, score_t, map_name, rounds_played = msm.groups()
        return {
            "event_type": "match_status",
            "event_ts": event_ts,
            "extra_json": {
                "score_ct": int(score_ct),
                "score_t": int(score_t),
                "map": map_name,
                "rounds_played": int(rounds_played),
            },
        }

    # --- CS2: OnPreResetRound (player entity event, may lack HL prefix) ---
    rrm = _RESET_ROUND_RE.match(payload)
    if rrm:
        name, slot, steamid, team, new_team, will_switch = rrm.groups()
        return {
            "event_type": "player_reset",
            "event_ts": event_ts,
            "attacker_name": name,
            "attacker_steamid": steamid,
            "attacker_team": team,
            "extra_json": {
                "slot": int(slot),
                "current_team": team,
                "new_team": int(new_team),
                "will_switch": int(will_switch),
            },
        }

    # --- CS2: ChangeTeam (player entity event) ---
    ctm = _CHANGE_TEAM_RE.match(payload)
    if ctm:
        name, slot, steamid, team, from_team, req_team = ctm.groups()
        return {
            "event_type": "team_change",
            "event_ts": event_ts,
            "attacker_name": name,
            "attacker_steamid": steamid,
            "attacker_team": team,
            "extra_json": {
                "slot": int(slot),
                "from_team": int(from_team),
                "req_team": int(req_team),
            },
        }

    # --- BIOBASE structured position (plugin) ---
    bpm = _BIOBASE_POS_RE.search(payload)
    if bpm:
        try:
            data = json.loads(bpm.group(1))
            return {
                "event_type": "biobase_pos",
                "event_ts": event_ts,
                "attacker_name": data.get("player"),
                "attacker_steamid": data.get("steamid"),
                "extra_json": data,
            }
        except (json.JSONDecodeError, KeyError):
            pass

    # --- BIOBASE structured event (plugin) ---
    bem = _BIOBASE_EVENT_RE.search(payload)
    if bem:
        try:
            data = json.loads(bem.group(1))
            return {
                "event_type": data.get("type", "biobase_event"),
                "event_ts": event_ts,
                "attacker_name": data.get("player"),
                "attacker_steamid": data.get("steamid"),
                "extra_json": data,
            }
        except (json.JSONDecodeError, KeyError):
            pass

    return None


def parse_movement(line: str) -> dict[str, Any] | None:
    """
    Parse a BIOBASE_POS_JSON line into a movement sample dict.
    Returns None if the line is not a BIOBASE_POS_JSON line or is malformed.
    """
    m = _BIOBASE_POS_RE.search(line)
    if not m:
        return None
    try:
        data = json.loads(m.group(1))
        pos = data.get("pos") or []
        vel = data.get("vel") or []
        return {
            "tick": data.get("tick"),
            "player_name": data.get("player"),
            "steamid": data.get("steamid"),
            "pos_x": pos[0] if len(pos) > 0 else None,
            "pos_y": pos[1] if len(pos) > 1 else None,
            "pos_z": pos[2] if len(pos) > 2 else None,
            "vel_x": vel[0] if len(vel) > 0 else None,
            "vel_y": vel[1] if len(vel) > 1 else None,
            "vel_z": vel[2] if len(vel) > 2 else None,
            "speed": data.get("speed"),
            "yaw": data.get("yaw"),
            "pitch": data.get("pitch"),
            "on_ground": data.get("on_ground"),
            "extra_json": data,
        }
    except (json.JSONDecodeError, IndexError, TypeError, KeyError):
        log.debug("BIOBASE_POS_JSON parse failed: %s", line[:200])
        return None


def _parse_round_stats_block(block_lines: list[str]) -> dict[str, Any] | None:
    """
    Parse a JSON_BEGIN...JSON_END block into a structured round_stats dict.

    CS2 emits the block WITHOUT commas between lines, so we use regex extraction
    rather than stdlib JSON parsing which would fail on the missing commas.

    block_lines: raw payload strings (HL prefix already stripped), from
                 the line after JSON_BEGIN{ up to (but not including) }}JSON_END.
    """
    full_text = "\n".join(block_lines)

    # Quick guard — must be a round_stats block
    if '"round_stats"' not in full_text and "round_stats" not in full_text:
        return None

    def _extract_str(key: str) -> str | None:
        m = re.search(r'"' + re.escape(key) + r'"\s*:\s*"([^"]*)"', full_text)
        return m.group(1) if m else None

    round_number = _safe_int(_extract_str("round_number"))
    score_t = _safe_int(_extract_str("score_t"))
    score_ct = _safe_int(_extract_str("score_ct"))
    map_name = _extract_str("map")

    fields_str = _extract_str("fields") or ""
    field_names_raw = [f.strip() for f in fields_str.split(",") if f.strip()]
    field_names = [
        {"3k": "kills_3k", "4k": "kills_4k", "5k": "kills_5k"}.get(fn, fn)
        for fn in field_names_raw
    ] or _ROUND_STAT_FIELDS

    # Extract per-player rows: "player_N" : "..."
    player_rows: list[dict[str, Any]] = []
    for pm in re.finditer(r'"player_(\d+)"\s*:\s*"([^"]*)"', full_text):
        slot = int(pm.group(1))
        raw_vals = [v.strip() for v in pm.group(2).split(",")]
        row: dict[str, Any] = {"slot_index": slot}

        for i, col in enumerate(field_names):
            if i >= len(raw_vals):
                break
            raw = raw_vals[i]
            try:
                idx = _ROUND_STAT_FIELDS.index(col) if col in _ROUND_STAT_FIELDS else -1
                t = _ROUND_STAT_TYPES[idx] if idx >= 0 else float
                row[col] = t(raw)
            except (ValueError, IndexError):
                row[col] = None

        player_rows.append(row)

    if not player_rows:
        return None

    return {
        "round_number": round_number,
        "score_t": score_t,
        "score_ct": score_ct,
        "map": map_name,
        "player_rows": player_rows,
    }


def _safe_int(v: Any) -> int | None:
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def parse_events_from_lines(
    lines: list[tuple[str, str]],  # [(session_id_str, raw_line), ...]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """
    Bulk-parse a list of (session_id, raw_line) tuples.

    Returns:
      (game_events, movement_samples, round_stats_rows)

    game_events      — list of dicts for biobase_cs2_game_event
    movement_samples — list of dicts for biobase_cs2_movement_sample
    round_stats_rows — list of dicts for biobase_cs2_round_stats (one row per player per round)
    """
    game_events: list[dict[str, Any]] = []
    movement_samples: list[dict[str, Any]] = []
    round_stats_rows: list[dict[str, Any]] = []
    round_num = 0

    # State for multi-line JSON block accumulation
    in_json_block = False
    json_block_lines: list[str] = []
    block_session_id: str = ""
    block_ts: datetime | None = None

    for session_id_str, raw_line in lines:
        _, payload = _strip_hl_prefix(raw_line)
        event_ts, _ = _strip_hl_prefix(raw_line)

        # --- Multi-line JSON_BEGIN / JSON_END block ---
        if _JSON_BEGIN_RE.match(payload):
            in_json_block = True
            json_block_lines = []
            block_session_id = session_id_str
            block_ts = event_ts
            continue

        if in_json_block:
            if _JSON_END_RE.match(payload):
                in_json_block = False
                block = _parse_round_stats_block(json_block_lines)
                if block:
                    for prow in block["player_rows"]:
                        prow["session_id"] = block_session_id
                        prow["round_number"] = block["round_number"]
                        prow["score_t"] = block["score_t"]
                        prow["score_ct"] = block["score_ct"]
                        prow["map"] = block["map"]
                        round_stats_rows.append(prow)
                json_block_lines = []
            else:
                json_block_lines.append(payload)
            continue

        # --- Single-line event parsing ---
        ev = parse_line(raw_line)
        if ev is None:
            continue

        if ev["event_type"] == "round_start":
            round_num += 1

        ev["session_id"] = session_id_str
        ev["raw_line"] = raw_line
        ev["round_num"] = round_num if round_num > 0 else None

        if ev["event_type"] == "biobase_pos":
            ms = parse_movement(raw_line)
            if ms:
                ms["session_id"] = session_id_str
                movement_samples.append(ms)
        else:
            game_events.append(ev)

    return game_events, movement_samples, round_stats_rows


__all__ = [
    "parse_line",
    "parse_movement",
    "parse_events_from_lines",
]
