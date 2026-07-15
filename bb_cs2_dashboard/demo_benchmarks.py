"""Pro benchmark distributions computed from the parsed demo library.

Rendering old demos rots with every CS2 update, but parsing does not — so
benchmarks derived here stay valid regardless of game version. One pass over
every parsed demo JSON produces per-player match metrics and per-player-round
samples; percentiles of those populations feed the client's radar knots and
chart benchmark bands. Results are cached next to the parsed demos and only
recomputed when the library changes.
"""

from __future__ import annotations

import hashlib
import json
import math
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TRADE_WINDOW_SEC = 5.0
UTILITY_WEAPONS = {"hegrenade", "inferno", "molotov", "incgrenade"}
GUN_EXCLUDE = ("knife", "grenade", "molotov", "flashbang", "smoke", "decoy")
MIN_ROUNDS_PRESENT = 8
MIN_OPENING_ATTEMPTS = 5
KNOT_QUANTILES = (0.05, 0.25, 0.50, 0.75, 0.95)

_lock = threading.Lock()


def _percentiles(values: list[float], quantiles=KNOT_QUANTILES) -> list[float] | None:
    clean = sorted(v for v in values if isinstance(v, (int, float)) and math.isfinite(v))
    if len(clean) < 8:
        return None
    result = []
    for q in quantiles:
        idx = q * (len(clean) - 1)
        lo = int(math.floor(idx))
        hi = int(math.ceil(idx))
        frac = idx - lo
        result.append(round(clean[lo] + (clean[hi] - clean[lo]) * frac, 4))
    return result


def _fingerprint(parsed_dir: Path) -> str:
    h = hashlib.sha256()
    for f in sorted(parsed_dir.glob("*.json")):
        h.update(f.name.encode())
        h.update(str(f.stat().st_size).encode())
    return h.hexdigest()[:32]


def _real_kill(e: dict[str, Any]) -> bool:
    d = e.get("data") or {}
    a, v = d.get("attacker_steamid"), d.get("user_steamid")
    return (
        e.get("type") == "player_death"
        and a
        and v
        and a != v
        and d.get("weapon") != "world"
    )


def _analyze_demo(parsed: dict[str, Any], out: dict[str, Any]) -> None:
    events = parsed.get("events") or []
    frames = parsed.get("frames") or []
    rate = parsed.get("tickRateGuess") or 64
    if rate <= 0:
        rate = 64
    trade_ticks = int(TRADE_WINDOW_SEC * rate)

    round_starts = [e["tick"] for e in events if e.get("type") == "round_start"]
    if not round_starts:
        round_starts = [parsed.get("startTick") or 0]
    end_tick = parsed.get("endTick") or (round_starts[-1] + 1)

    def round_index(tick: int) -> int | None:
        idx = None
        for i, start in enumerate(round_starts):
            if tick >= start:
                idx = i
            else:
                break
        return idx

    n_rounds = len(round_starts)

    # Deaths grouped per round, in tick order (openings + trades).
    deaths_by_round: dict[int, list[dict[str, Any]]] = {}
    for e in events:
        if e.get("type") != "player_death":
            continue
        r = round_index(e["tick"])
        if r is None:
            continue
        deaths_by_round.setdefault(r, []).append(e)
    for lst in deaths_by_round.values():
        lst.sort(key=lambda x: x["tick"])

    # Per-player per-round tallies.
    stats: dict[str, dict[str, Any]] = {}

    def player(steamid: str) -> dict[str, Any]:
        return stats.setdefault(
            steamid,
            {
                "kills": [0] * n_rounds,
                "deaths": [0] * n_rounds,
                "assists": [0] * n_rounds,
                "damage": [0.0] * n_rounds,
                "utility": [0.0] * n_rounds,
                "flash_assists": 0,
                "trade_kills": 0,
                "traded_deaths": 0,
                "open_k": 0,
                "open_d": 0,
                "dist": [0.0] * n_rounds,
                "move_time": [0.0] * n_rounds,
                "present": set(),
            },
        )

    for r, deaths in deaths_by_round.items():
        real = [e for e in deaths if _real_kill(e)]
        if real:
            first = real[0]["data"]
            player(first["attacker_steamid"])["open_k"] += 1
            player(first["user_steamid"])["open_d"] += 1
        for e in deaths:
            d = e.get("data") or {}
            victim = d.get("user_steamid")
            killer = d.get("attacker_steamid")
            if victim:
                player(victim)["deaths"][r] += 1
                # Traded: the killer dies within the window (only the victim's
                # side can kill the killer, so no side data needed).
                if killer and killer != victim:
                    for later in real:
                        if later["tick"] <= e["tick"]:
                            continue
                        if later["tick"] - e["tick"] > trade_ticks:
                            break
                        ld = later["data"]
                        if ld.get("user_steamid") == killer:
                            player(victim)["traded_deaths"] += 1
                            if ld.get("attacker_steamid"):
                                player(ld["attacker_steamid"])["trade_kills"] += 1
                            break
            if _real_kill(e):
                player(killer)["kills"][r] += 1
            assister = d.get("assister_steamid")
            if assister and assister != victim:
                player(assister)["assists"][r] += 1
                if d.get("assistedflash"):
                    player(assister)["flash_assists"] += 1

    for e in events:
        if e.get("type") != "player_hurt":
            continue
        d = e.get("data") or {}
        attacker, victim = d.get("attacker_steamid"), d.get("user_steamid")
        if not attacker or attacker == victim:
            continue
        r = round_index(e["tick"])
        if r is None:
            continue
        dmg = max(0, min(100, d.get("dmg_health") or 0))
        p = player(attacker)
        p["damage"][r] += dmg
        if d.get("weapon") in UTILITY_WEAPONS:
            p["utility"][r] += dmg

    # Movement pass over frames.
    last: dict[str, tuple[float, float, float]] = {}
    for frame in frames:
        t = frame.get("timeSec") or 0.0
        r = round_index(frame.get("tick") or 0)
        for pl in frame.get("players") or []:
            sid = pl.get("steamid")
            if not sid:
                continue
            x, y = pl.get("x"), pl.get("y")
            if x is None or y is None:
                continue
            prev = last.get(sid)
            last[sid] = (x, y, t)
            if r is None:
                continue
            player(sid)["present"].add(r)
            if prev is None:
                continue
            px, py, pt = prev
            dt = t - pt
            if dt <= 0 or dt > 3:
                continue
            d = math.hypot(x - px, y - py)
            if d / dt >= 1200:
                continue
            p = player(sid)
            p["dist"][r] += d
            p["move_time"][r] += dt

    # Fold into population samples.
    for sid, p in stats.items():
        rounds_present = sorted(p["present"])
        n = len(rounds_present)
        if n < MIN_ROUNDS_PRESENT:
            continue
        kills = sum(p["kills"][r] for r in rounds_present)
        deaths = sum(p["deaths"][r] for r in rounds_present)
        assists = sum(p["assists"][r] for r in rounds_present)
        damage = sum(p["damage"][r] for r in rounds_present)
        utility = sum(p["utility"][r] for r in rounds_present)

        kast_rounds = 0
        for r in rounds_present:
            if p["kills"][r] > 0 or p["assists"][r] > 0 or p["deaths"][r] == 0:
                kast_rounds += 1
        # Traded rounds approximate the T of KAST; add them conservatively by
        # counting traded deaths in rounds where the player got nothing else.
        kast = min(100.0, (kast_rounds + min(p["traded_deaths"], n - kast_rounds)) / n * 100)

        kpr, dpr, apr, adr = kills / n, deaths / n, assists / n, damage / n
        impact = 2.13 * kpr + 0.42 * apr - 0.41
        rating = 0.0073 * kast + 0.3591 * kpr - 0.5329 * dpr + 0.2372 * impact + 0.0032 * adr + 0.1587

        m = out["metrics"]
        m["rating"].append(rating)
        m["adr"].append(adr)
        m["kpr"].append(kpr)
        m["kd"].append(kills / deaths if deaths else float(kills))
        m["dpr"].append(dpr)
        m["kast"].append(kast)
        m["traded_deaths_pr"].append(p["traded_deaths"] / n)
        m["trade_kills_pr"].append(p["trade_kills"] / n)
        attempts = p["open_k"] + p["open_d"]
        m["opening_attempts_pr"].append(attempts / n)
        if attempts >= MIN_OPENING_ATTEMPTS:
            m["opening_kd"].append(p["open_k"] / p["open_d"] if p["open_d"] else float(p["open_k"]))
        m["flash_assists_pr"].append(p["flash_assists"] / n)
        m["udr"].append(utility / n)

        rounds_sampled = out["per_round"]
        for r in rounds_present:
            rounds_sampled["damage"].append(p["damage"][r])
            rounds_sampled["kills"].append(float(p["kills"][r]))
            rounds_sampled["deaths"].append(float(p["deaths"][r]))
            rounds_sampled["distance"].append(p["dist"][r])
            if p["move_time"][r] > 0:
                rounds_sampled["avg_speed"].append(p["dist"][r] / p["move_time"][r])

        out["population"]["players"] += 1
        out["population"]["player_rounds"] += n


def compute_benchmarks(parsed_dir: Path) -> dict[str, Any]:
    """Compute (or load cached) benchmark distributions for the library."""
    cache_path = parsed_dir.parent / "benchmarks_cache.json"
    fingerprint = _fingerprint(parsed_dir)
    with _lock:
        try:
            cached = json.loads(cache_path.read_text())
            if cached.get("fingerprint") == fingerprint:
                return cached["result"]
        except Exception:  # noqa: BLE001
            pass

        started = time.time()
        acc: dict[str, Any] = {
            "metrics": {
                k: []
                for k in (
                    "rating adr kpr kd dpr kast traded_deaths_pr trade_kills_pr "
                    "opening_attempts_pr opening_kd flash_assists_pr udr".split()
                )
            },
            "per_round": {k: [] for k in ("damage", "kills", "deaths", "distance", "avg_speed")},
            "population": {"players": 0, "player_rounds": 0, "demos": 0},
        }
        for f in sorted(parsed_dir.glob("*.json")):
            try:
                parsed = json.loads(f.read_text())
                _analyze_demo(parsed, acc)
                acc["population"]["demos"] += 1
            except Exception:  # noqa: BLE001
                continue

        result = {
            "population": acc["population"],
            "quantiles": list(KNOT_QUANTILES),
            "metrics": {
                k: p for k, v in acc["metrics"].items() if (p := _percentiles(v)) is not None
            },
            "perRound": {
                k: p for k, v in acc["per_round"].items() if (p := _percentiles(v)) is not None
            },
            "computedAt": datetime.now(timezone.utc).isoformat(),
            "computeSeconds": round(time.time() - started, 1),
        }
        try:
            tmp = cache_path.with_suffix(".tmp")
            tmp.write_text(json.dumps({"fingerprint": fingerprint, "result": result}))
            tmp.replace(cache_path)
        except OSError:
            pass  # caching is best-effort; recompute next time
        return result
