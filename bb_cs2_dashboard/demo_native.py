"""Native in-app CS2 demo playback artifacts for BioBase Replay.

This module intentionally does not launch Steam/CS2. It parses `.dem` files into
compact 2D tactical frames that the BioBase UI can render in-app.
"""

from __future__ import annotations

import hashlib
import importlib.metadata
import json
import math
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_TICK_RATE = 64
SAMPLE_EVERY_TICKS = 12
MAX_FRAMES = 6000
EVENT_NAMES = (
    "player_death",
    "player_hurt",
    "weapon_fire",
    "bomb_planted",
    "bomb_defused",
    "bomb_exploded",
    "round_start",
    "round_end",
)


def _pkg_version(name: str) -> str | None:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return None


def hash_file(path: Path) -> tuple[str, int]:
    h = hashlib.sha256()
    n = 0
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            n += len(chunk)
            h.update(chunk)
    return h.hexdigest(), n


def _num(v: Any) -> float | None:
    if v is None:
        return None
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    if math.isnan(x) or math.isinf(x):
        return None
    return x


def _int(v: Any) -> int | None:
    x = _num(v)
    return int(x) if x is not None else None


def _bool(v: Any) -> bool | None:
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return bool(v)
    s = str(v).strip().lower()
    if s in {"1", "true", "yes", "y"}:
        return True
    if s in {"0", "false", "no", "n"}:
        return False
    return None


def _str(v: Any, fallback: str = "") -> str:
    if v is None:
        return fallback
    return str(v)


def _records(table: Any) -> list[dict[str, Any]]:
    if table is None:
        return []
    if isinstance(table, list):
        return [x for x in table if isinstance(x, dict)]
    if hasattr(table, "to_dicts"):
        return list(table.to_dicts())
    if hasattr(table, "to_dict"):
        try:
            rows = table.to_dict("records")
            if isinstance(rows, list):
                return [x for x in rows if isinstance(x, dict)]
        except TypeError:
            pass
    return []


def _select_columns(table: Any, names: list[str]) -> Any:
    cols = set(str(c) for c in getattr(table, "columns", []) or [])
    keep = [name for name in names if name in cols]
    if not keep:
        return table
    if hasattr(table, "select"):
        return table.select(keep)
    try:
        return table[keep]
    except Exception:  # noqa: BLE001
        return table


def _team_from_row(row: dict[str, Any]) -> str:
    team_num = _int(row.get("team_num") or row.get("team_number") or row.get("teamNumber"))
    if team_num == 2:
        return "T"
    if team_num == 3:
        return "CT"
    team = _str(row.get("team_name") or row.get("team") or "").lower()
    if "terrorist" in team or team == "t" or team == "team_t":
        return "T"
    if "counter" in team or team == "ct" or team == "team_ct":
        return "CT"
    return "UNKNOWN"


def _player_state(row: dict[str, Any]) -> dict[str, Any] | None:
    x = _num(row.get("X") if "X" in row else row.get("x"))
    y = _num(row.get("Y") if "Y" in row else row.get("y"))
    if x is None or y is None:
        return None
    steamid = _str(
        row.get("steamid")
        or row.get("steam_id")
        or row.get("user_steamid")
        or row.get("player_steamid")
        or row.get("userid"),
        "unknown",
    )
    name = _str(row.get("name") or row.get("player_name"), steamid)
    state: dict[str, Any] = {
        "steamid": steamid,
        "name": name,
        "team": _team_from_row(row),
        "x": x,
        "y": y,
    }
    optional_numbers = {
        "z": row.get("Z") if "Z" in row else row.get("z"),
        "yaw": row.get("yaw") or row.get("eye_yaw"),
        "pitch": row.get("pitch") or row.get("eye_pitch"),
        "health": row.get("health") or row.get("hp"),
    }
    for key, value in optional_numbers.items():
        n = _num(value)
        if n is not None:
            state[key] = n
    optional_bools = {
        "isAlive": row.get("is_alive") if "is_alive" in row else row.get("isAlive"),
        "hasHelmet": row.get("has_helmet") if "has_helmet" in row else row.get("hasHelmet"),
        "hasDefuser": row.get("has_defuser") if "has_defuser" in row else row.get("hasDefuser"),
        "isScoped": row.get("is_scoped") if "is_scoped" in row else row.get("isScoped"),
    }
    for key, value in optional_bools.items():
        b = _bool(value)
        if b is not None:
            state[key] = b
    if "isAlive" not in state and "health" in state:
        state["isAlive"] = float(state["health"]) > 0
    active_weapon = row.get("active_weapon") or row.get("weapon_name") or row.get("weapon")
    if active_weapon is not None:
        state["activeWeapon"] = active_weapon if isinstance(active_weapon, (str, int, float)) else str(active_weapon)
    return state


def _header_map_name(header: dict[str, Any], fallback: str) -> str:
    return _str(header.get("map_name") or header.get("mapName") or header.get("map") or header.get("MapName"), fallback)


def _tick_rate(header: dict[str, Any]) -> int:
    raw = _int(header.get("tickrate") or header.get("tick_rate") or header.get("tickRate"))
    return raw if raw and raw > 0 else DEFAULT_TICK_RATE


def _read_header(demo: Any, path: Path) -> dict[str, Any]:
    header = getattr(demo, "header", None)
    if isinstance(header, dict):
        return header
    try:
        from demoparser2 import DemoParser

        parser = DemoParser(str(path))
        parsed = getattr(parser, "parse_header", lambda: None)()
        if isinstance(parsed, dict):
            return parsed
    except Exception:  # noqa: BLE001
        pass
    return {}


def _parse_ticks_with_awpy(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]], Any]:
    from awpy.demo import Demo

    demo = Demo(path)
    header = _read_header(demo, path)
    demo.parse()
    ticks = demo.ticks
    wanted = [
        "tick",
        "steamid",
        "steam_id",
        "user_steamid",
        "player_steamid",
        "userid",
        "name",
        "player_name",
        "team_name",
        "team_num",
        "team_number",
        "X",
        "Y",
        "Z",
        "yaw",
        "pitch",
        "eye_yaw",
        "eye_pitch",
        "health",
        "hp",
        "is_alive",
        "life_state",
        "has_helmet",
        "has_defuser",
        "is_scoped",
        "is_walking",
        "active_weapon",
        "weapon_name",
    ]
    return header, _records(_select_columns(ticks, wanted)), demo


def _parse_events(demo: Any, parser: Any, start_tick: int, tick_rate: int) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for event_name in EVENT_NAMES:
        rows: list[dict[str, Any]] = []
        try:
            if parser is not None and hasattr(parser, "parse_event"):
                rows = _records(parser.parse_event(event_name))
        except Exception:  # noqa: BLE001
            rows = []
        if not rows:
            table = getattr(demo, "events", {}).get(event_name) if getattr(demo, "events", None) else None
            rows = _records(table)
        for row in rows:
            tick = _int(row.get("tick"))
            if tick is None:
                continue
            payload = dict(row)
            payload.setdefault("event_name", event_name)
            events.append(
                {
                    "tick": tick,
                    "timeSec": max(0, (tick - start_tick) / tick_rate),
                    "type": _str(row.get("event_name") or row.get("eventName") or row.get("type"), event_name),
                    "data": payload,
                }
            )
    events.sort(key=lambda x: int(x["tick"]))
    return events


def parse_cs2_demo(demo_path: Path | str, *, source_filename: str | None = None) -> dict[str, Any]:
    path = Path(demo_path).resolve()
    if not path.is_file():
        raise FileNotFoundError(str(path))
    if path.stat().st_size < 4096:
        raise ValueError(f"demo_too_small_bytes:{path.stat().st_size}")

    started = time.time()
    sha256, nbytes = hash_file(path)
    demo_id = sha256[:24]

    header, raw_rows, demo = _parse_ticks_with_awpy(path)
    parser = getattr(demo, "parser", None)
    rows = []
    for row in raw_rows:
        tick = _int(row.get("tick"))
        if tick is None:
            continue
        copied = dict(row)
        copied["tick"] = tick
        rows.append(copied)
    rows.sort(key=lambda x: int(x["tick"]))
    if not rows:
        raise ValueError("parser_returned_no_tick_data")

    tick_rate = _tick_rate(header)
    start_tick = int(rows[0]["tick"])
    end_tick = int(rows[-1]["tick"])
    map_name = _header_map_name(header, path.stem)

    grouped: dict[int, dict[str, dict[str, Any]]] = {}
    for row in rows:
        tick = int(row["tick"])
        if tick not in (start_tick, end_tick) and (tick - start_tick) % SAMPLE_EVERY_TICKS != 0:
            continue
        player = _player_state(row)
        if not player:
            continue
        grouped.setdefault(tick, {})[player["steamid"]] = player

    frame_ticks = sorted(grouped)
    if len(frame_ticks) > MAX_FRAMES:
        stride = max(1, math.ceil(len(frame_ticks) / MAX_FRAMES))
        keep = set(frame_ticks[::stride])
        keep.add(frame_ticks[-1])
        frame_ticks = [tick for tick in frame_ticks if tick in keep]

    frames = [
        {
            "tick": tick,
            "timeSec": max(0, (tick - start_tick) / tick_rate),
            "players": list(grouped[tick].values()),
        }
        for tick in frame_ticks
        if grouped[tick]
    ]
    events = _parse_events(demo, parser, start_tick, tick_rate)

    return {
        "demoId": demo_id,
        "demoPath": str(path),
        "sourceFilename": source_filename or path.name,
        "mapName": map_name,
        "tickRateGuess": tick_rate,
        "startTick": start_tick,
        "endTick": end_tick,
        "frames": frames,
        "events": events,
        "meta": {
            "parser": "awpy-demoparser2",
            "awpy_version": _pkg_version("awpy"),
            "demoparser2_version": _pkg_version("demoparser2"),
            "sha256": sha256,
            "bytes": nbytes,
            "sample_every_ticks": SAMPLE_EVERY_TICKS,
            "frame_count": len(frames),
            "event_count": len(events),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "parse_elapsed_sec": round(time.time() - started, 2),
        },
    }


def parsed_demo_path(output_dir: Path, demo_id: str) -> Path:
    return output_dir / f"{demo_id}.json"


def write_parsed_demo(parsed: dict[str, Any], output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    out = parsed_demo_path(output_dir, str(parsed["demoId"]))
    tmp = out.with_suffix(out.suffix + ".tmp")
    tmp.write_text(json.dumps(parsed, separators=(",", ":")))
    tmp.replace(out)
    return out


def parse_and_save_demo(demo_path: Path | str, output_dir: Path, *, source_filename: str | None = None) -> tuple[dict[str, Any], Path]:
    parsed = parse_cs2_demo(demo_path, source_filename=source_filename)
    return parsed, write_parsed_demo(parsed, output_dir)


def read_parsed_demo(output_dir: Path, demo_id: str) -> dict[str, Any]:
    path = parsed_demo_path(output_dir, demo_id)
    return json.loads(path.read_text())
