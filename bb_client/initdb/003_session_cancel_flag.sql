-- Allow hub / operator to end ingest early (still flush Loki window to Postgres)
ALTER TABLE public.biobase_cs2_match_session
  ADD COLUMN IF NOT EXISTS cancel_requested boolean NOT NULL DEFAULT false;
