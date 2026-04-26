"""Plain-text report for a session summary (CLI / curl -f)."""

from __future__ import annotations

import json
from typing import Any


def format_summary_text(s: dict[str, Any]) -> str:
    lines = [
        "=== Biobase CS2 session data summary ===",
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

    rc = s.get("rcon_samples") or {}
    lines.extend(
        [
            f"Table `{rc.get('table')}` (game / RCON state via bb_cs2_control):",
            f"  Rows:            {rc.get('row_count')}",
            f"  Columns:         {rc.get('column_count')}  {rc.get('column_names')}",
            f"  RCON ok / fail:  {rc.get('rcon_ok_count')} / {rc.get('rcon_fail_count')}",
            f"  First/last:      {rc.get('time_range', {}).get('first_sample')}  →  {rc.get('time_range', {}).get('last_sample')}",
            f"  Granularity:     {rc.get('sampling_granularity') or 'n/a'}",
            "",
        ]
    )

    lg = s.get("log_lines") or {}
    lines.extend(
        [
            f"Table `{lg.get('table')}` (Docker log lines from `bb_cs2_server`, via Loki):",
            f"  Rows:              {lg.get('row_count')}",
            f"  Columns:           {lg.get('column_count')}  {lg.get('column_names')}",
            f"  Approx size (raw): {lg.get('approx_total_bytes_utf8')} bytes UTF-8 in DB",
            f"  Ingest range:      {lg.get('ingest_time_range', {}).get('first')}  →  {lg.get('ingest_time_range', {}).get('last')}",
            f"  KZ/keyword hits:  {lg.get('heuristic_kz_plugin_hits')}",
            f"  Note: {lg.get('heuristic_note')}",
            "",
        ]
    )

    lines.append("--- JSON (same payload) ---")
    lines.append(json.dumps(s, indent=2, default=str))
    return "\n".join(lines)
