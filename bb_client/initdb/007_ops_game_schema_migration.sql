-- One-time migration for volumes that created CS2 ingest tables in public before ops/game split.
-- Safe to re-run: only moves when the target schema has no table of that name yet.

CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS game;

DO $$
BEGIN
  IF to_regclass('public.biobase_ingest_sample') IS NOT NULL
     AND to_regclass('ops.biobase_ingest_sample') IS NULL THEN
    ALTER TABLE public.biobase_ingest_sample SET SCHEMA ops;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2_rcon_sample') IS NOT NULL
     AND to_regclass('ops.biobase_cs2_rcon_sample') IS NULL THEN
    ALTER TABLE public.biobase_cs2_rcon_sample SET SCHEMA ops;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2_log_line') IS NOT NULL
     AND to_regclass('ops.biobase_cs2_log_line') IS NULL THEN
    ALTER TABLE public.biobase_cs2_log_line SET SCHEMA ops;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2_player_snapshot') IS NOT NULL
     AND to_regclass('ops.biobase_cs2_player_snapshot') IS NULL THEN
    ALTER TABLE public.biobase_cs2_player_snapshot SET SCHEMA ops;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2_game_event') IS NOT NULL
     AND to_regclass('game.biobase_cs2_game_event') IS NULL THEN
    ALTER TABLE public.biobase_cs2_game_event SET SCHEMA game;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2_movement_sample') IS NOT NULL
     AND to_regclass('game.biobase_cs2_movement_sample') IS NULL THEN
    ALTER TABLE public.biobase_cs2_movement_sample SET SCHEMA game;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2_round_stats') IS NOT NULL
     AND to_regclass('game.biobase_cs2_round_stats') IS NULL THEN
    ALTER TABLE public.biobase_cs2_round_stats SET SCHEMA game;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2kz_sqlite_cursor') IS NOT NULL
     AND to_regclass('game.biobase_cs2kz_sqlite_cursor') IS NULL THEN
    ALTER TABLE public.biobase_cs2kz_sqlite_cursor SET SCHEMA game;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2kz_player') IS NOT NULL
     AND to_regclass('game.biobase_cs2kz_player') IS NULL THEN
    ALTER TABLE public.biobase_cs2kz_player SET SCHEMA game;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2kz_run') IS NOT NULL
     AND to_regclass('game.biobase_cs2kz_run') IS NULL THEN
    ALTER TABLE public.biobase_cs2kz_run SET SCHEMA game;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.biobase_cs2kz_jumpstat') IS NOT NULL
     AND to_regclass('game.biobase_cs2kz_jumpstat') IS NULL THEN
    ALTER TABLE public.biobase_cs2kz_jumpstat SET SCHEMA game;
  END IF;
END $$;
