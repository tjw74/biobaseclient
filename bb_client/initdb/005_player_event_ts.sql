-- Game-time column: server log timestamp for movement and round-stat blocks (not ingest-only).

ALTER TABLE public.biobase_cs2_movement_sample
  ADD COLUMN IF NOT EXISTS event_ts timestamptz;

CREATE INDEX IF NOT EXISTS biobase_cs2_movement_sample_session_event_ts
  ON public.biobase_cs2_movement_sample (session_id, event_ts);

ALTER TABLE public.biobase_cs2_round_stats
  ADD COLUMN IF NOT EXISTS event_ts timestamptz;

CREATE INDEX IF NOT EXISTS biobase_cs2_round_stats_session_event_ts
  ON public.biobase_cs2_round_stats (session_id, event_ts);
