"""
PostgreSQL schema layout: ops (RCON / raw log capture) vs game (parsed gameplay + CS2KZ).

Session anchor stays in public so both pipelines share one session_id FK.
"""

SCHEMA_SESSION = "public"
SCHEMA_OPS = "ops"
SCHEMA_GAME = "game"

MATCH_SESSION = f"{SCHEMA_SESSION}.biobase_cs2_match_session"
INGEST_SAMPLE = f"{SCHEMA_OPS}.biobase_ingest_sample"

RCON_SAMPLE = f"{SCHEMA_OPS}.biobase_cs2_rcon_sample"
LOG_LINE = f"{SCHEMA_OPS}.biobase_cs2_log_line"
PLAYER_SNAPSHOT = f"{SCHEMA_OPS}.biobase_cs2_player_snapshot"

GAME_EVENT = f"{SCHEMA_GAME}.biobase_cs2_game_event"
MOVEMENT_SAMPLE = f"{SCHEMA_GAME}.biobase_cs2_movement_sample"
ROUND_STATS = f"{SCHEMA_GAME}.biobase_cs2_round_stats"

KZ_SQLITE_CURSOR = f"{SCHEMA_GAME}.biobase_cs2kz_sqlite_cursor"
KZ_PLAYER = f"{SCHEMA_GAME}.biobase_cs2kz_player"
KZ_RUN = f"{SCHEMA_GAME}.biobase_cs2kz_run"
KZ_JUMPSTAT = f"{SCHEMA_GAME}.biobase_cs2kz_jumpstat"
