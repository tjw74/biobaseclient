-- CS2 + KZ session capture: shared session row (public), RCON + raw Loki lines (ops).
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS game;

CREATE TABLE IF NOT EXISTS public.biobase_cs2_match_session (
    id                 uuid PRIMARY KEY,
    label              text,
    status             text NOT NULL DEFAULT 'pending',
    duration_requested integer NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    started_at         timestamptz,
    ended_at           timestamptz,
    loki_start_ns      bigint,
    loki_end_ns        bigint,
    error_message      text
);

CREATE TABLE IF NOT EXISTS ops.biobase_cs2_rcon_sample (
    id           bigserial PRIMARY KEY,
    session_id   uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    sampled_at   timestamptz NOT NULL DEFAULT now(),
    rcon_ok      boolean,
    headline     text,
    humans       integer,
    bots         integer,
    map          text,
    hostname     text,
    raw_json     jsonb
);

CREATE INDEX IF NOT EXISTS biobase_cs2_rcon_sample_session_time
  ON ops.biobase_cs2_rcon_sample (session_id, sampled_at);

CREATE TABLE IF NOT EXISTS ops.biobase_cs2_log_line (
    id              bigserial PRIMARY KEY,
    session_id      uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    ingested_at     timestamptz NOT NULL DEFAULT now(),
    loki_ts_ns      bigint,
    line            text NOT NULL
);

CREATE INDEX IF NOT EXISTS biobase_cs2_log_line_session
  ON ops.biobase_cs2_log_line (session_id);
