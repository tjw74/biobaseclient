"""Plain-text report for a session summary (CLI / curl -H 'Accept: text/plain')."""

from __future__ import annotations

import json
from typing import Any


def format_summary_text(s: dict[str, Any]) -> str:
    lines = [
        "=== Biobase CS2 session — granular telemetry summary ===",
        "",
        f"Session ID:   {s.get('session_id')}",
        f"Label:        {s.get('label')}",
        f"Status:       {s.get('status')}",
        f"Requested:    {s.get('duration_requested_seconds')} s wall-clock collection",
        "",
    ]

    ts = s.get("timestamps") or {}
    lines.extend(
        [
            "Time range:",
            f"  created: {ts.get('created_at')}",
            f"  started: {ts.get('started_at')}",
            f"  ended:   {ts.get('ended_at')}",
            f"  wall:    {ts.get('wall_clock_seconds')} s",
            "",
        ]
    )

    if s.get("error_message"):
        lines.extend(["Loki/ingest note:", f"  {s['error_message']}", ""])

    # RCON samples
    rc = s.get("rcon_samples") or {}
    lines.extend(
        [
            f"Table `{rc.get('table')}` — coarse game state (RCON status every ~5 s):",
            f"  Rows:         {rc.get('row_count')}",
            f"  Columns ({rc.get('column_count')}): {rc.get('column_names')}",
            f"  RCON ok/fail: {rc.get('rcon_ok_count')} / {rc.get('rcon_fail_count')}",
            f"  First/last:   {rc.get('time_range', {}).get('first_sample')}  →  {rc.get('time_range', {}).get('last_sample')}",
            f"  Granularity:  {rc.get('sampling_granularity') or 'n/a'}",
            "",
        ]
    )

    # Player snapshots
    ps = s.get("player_snapshots") or {}
    lines.extend(
        [
            f"Table `{ps.get('table')}` — per-player data on each RCON poll:",
            f"  Rows:             {ps.get('row_count')}",
            f"  Columns ({ps.get('column_count')}):  {ps.get('column_names')}",
            f"  Unique players:   {ps.get('unique_player_names')} names / {ps.get('unique_steamids')} SteamIDs",
            f"  Time range:       {ps.get('time_range', {}).get('first')}  →  {ps.get('time_range', {}).get('last')}",
            f"  Note: {ps.get('note')}",
            "",
        ]
    )

    # Log lines
    lg = s.get("log_lines") or {}
    lines.extend(
        [
            f"Table `{lg.get('table')}` — raw Docker log lines from `bb_cs2_server` via Loki:",
            f"  Rows:              {lg.get('row_count')}",
            f"  Columns ({lg.get('column_count')}):     {lg.get('column_names')}",
            f"  Approx size:       {lg.get('approx_total_bytes_utf8')} bytes UTF-8",
            f"  Ingest range:      {lg.get('ingest_time_range', {}).get('first')}  →  {lg.get('ingest_time_range', {}).get('last')}",
            f"  KZ/keyword hits:   {lg.get('heuristic_kz_plugin_hits')}",
            f"  Note: {lg.get('heuristic_note')}",
            "",
        ]
    )

    # Game events
    ge = s.get("game_events") or {}
    lines.extend(
        [
            f"Table `{ge.get('table')}` — structured game events parsed from log lines:",
            f"  Rows:             {ge.get('row_count')}",
            f"  Columns ({ge.get('column_count')}):  {ge.get('column_names')}",
            f"  Kills:            {ge.get('kills')}  (headshots: {ge.get('headshots')})",
            f"  Rounds played:    {ge.get('rounds_played')}",
            f"  round_start evts: {ge.get('round_start_events')}",
            f"  round_end evts:   {ge.get('round_end_events')}",
            f"  Note: {ge.get('note')}",
        ]
    )

    top_killers = ge.get("top_killers") or []
    if top_killers:
        lines.append("  Top killers:")
        for k in top_killers:
            hs_pct = (
                f"{k['headshots'] / k['kills'] * 100:.0f}% HS"
                if k["kills"] else "0% HS"
            )
            lines.append(
                f"    {k['name']:<24} {k['kills']:>3} kills  {hs_pct}"
            )

    weapon_stats = ge.get("weapon_kill_counts") or []
    if weapon_stats:
        lines.append("  Weapon kill counts:")
        for w in weapon_stats:
            lines.append(f"    {w['weapon']:<24} {w['kills']:>4} kills")
    lines.append("")

    # Movement samples
    mv = s.get("movement_samples") or {}
    lines.extend(
        [
            f"Table `{mv.get('table')}` — plugin-emitted position/velocity data:",
            f"  Rows:          {mv.get('row_count')}",
            f"  Columns ({mv.get('column_count')}): {mv.get('column_names')}",
            f"  Unique players:{mv.get('unique_players')}",
            f"  Time range:    {mv.get('time_range', {}).get('first')}  →  {mv.get('time_range', {}).get('last')}",
            f"  Note: {mv.get('note')}",
            "",
        ]
    )

    # Round stats
    rs = s.get("round_stats") or {}
    lines.extend(
        [
            f"Table `{rs.get('table')}` — per-player cumulative stats from JSON_BEGIN/END blocks:",
            f"  Rows:              {rs.get('row_count')}",
            f"  Columns ({rs.get('column_count')}): {rs.get('column_names')}",
            f"  Rounds with data:  {rs.get('rounds_with_data')}  (max round: {rs.get('max_round_number')})",
            f"  Total kills:       {rs.get('total_kills_all_rounds')}",
            f"  Total deaths:      {rs.get('total_deaths_all_rounds')}",
            f"  Total damage:      {rs.get('total_damage_all_rounds')}",
            f"  Note: {rs.get('note')}",
        ]
    )
    rs_top = rs.get("top_players_by_kills") or []
    if rs_top:
        lines.append("  Leaderboard (slot→name, kills, deaths, dmg, avg ADR):")
        for p in rs_top:
            lines.append(
                f"    {p['name']:<20} K:{p['kills']:>3}  D:{p['deaths']:>3}"
                f"  dmg:{p['total_damage']:>8.0f}  ADR:{p['avg_adr']:>5.1f}"
            )
    lines.append("")

    lines.append("--- JSON (same payload) ---")
    lines.append(json.dumps(s, indent=2, default=str))
    return "\n".join(lines)
