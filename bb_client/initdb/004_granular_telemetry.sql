-- Granular CS2 telemetry: ops = RCON-derived snapshots + raw log storage anchor;
-- game = parsed gameplay derived from ops.biobase_cs2_log_line.

-- Per-player data captured on every RCON status poll
CREATE TABLE IF NOT EXISTS ops.biobase_cs2_player_snapshot (
    id              bigserial PRIMARY KEY,
    session_id      uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    rcon_sample_id  bigint REFERENCES ops.biobase_cs2_rcon_sample (id) ON DELETE CASCADE,
    sampled_at      timestamptz NOT NULL DEFAULT now(),
    userid          integer,
    player_name     text,
    steamid         text,
    connected       text,
    ping            integer,
    loss            integer,
    state           text
);

CREATE INDEX IF NOT EXISTS biobase_cs2_player_snapshot_session_time
    ON ops.biobase_cs2_player_snapshot (session_id, sampled_at);

CREATE INDEX IF NOT EXISTS biobase_cs2_player_snapshot_player
    ON ops.biobase_cs2_player_snapshot (player_name, steamid);

-- Parsed structured game events from CS2 server logs
-- event_type: kill | round_start | round_end | team_score | connect |
--             disconnect | say | say_team | game_over | game_commencing |
--             world_<trigger> | biobase_pos | biobase_event
CREATE TABLE IF NOT EXISTS game.biobase_cs2_game_event (
    id               bigserial PRIMARY KEY,
    session_id       uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    log_line_id      bigint REFERENCES ops.biobase_cs2_log_line (id) ON DELETE SET NULL,
    event_ts         timestamptz,
    event_type       text NOT NULL,
    round_num        integer,
    attacker_name    text,
    attacker_steamid text,
    attacker_team    text,
    victim_name      text,
    victim_steamid   text,
    victim_team      text,
    weapon           text,
    headshot         boolean,
    extra_json       jsonb,
    raw_line         text NOT NULL
);

CREATE INDEX IF NOT EXISTS biobase_cs2_game_event_session_type
    ON game.biobase_cs2_game_event (session_id, event_type);

CREATE INDEX IF NOT EXISTS biobase_cs2_game_event_session_ts
    ON game.biobase_cs2_game_event (session_id, event_ts);

-- Plugin-emitted structured position / movement data
-- Populated when a server plugin prints: BIOBASE_POS_JSON {"player":...,"pos":[x,y,z],...}
CREATE TABLE IF NOT EXISTS game.biobase_cs2_movement_sample (
    id          bigserial PRIMARY KEY,
    session_id  uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    log_line_id bigint REFERENCES ops.biobase_cs2_log_line (id) ON DELETE SET NULL,
    sampled_at  timestamptz NOT NULL DEFAULT now(),
    event_ts    timestamptz,
    tick        bigint,
    player_name text,
    steamid     text,
    pos_x       double precision,
    pos_y       double precision,
    pos_z       double precision,
    vel_x       double precision,
    vel_y       double precision,
    vel_z       double precision,
    speed       double precision,
    yaw         double precision,
    pitch       double precision,
    on_ground   boolean,
    extra_json  jsonb
);

CREATE INDEX IF NOT EXISTS biobase_cs2_movement_sample_session_time
    ON game.biobase_cs2_movement_sample (session_id, sampled_at);

CREATE INDEX IF NOT EXISTS biobase_cs2_movement_sample_player
    ON game.biobase_cs2_movement_sample (player_name, steamid);

-- Per-player cumulative stats at the END of each round.
-- Populated from CS2 JSON_BEGIN...JSON_END round_stats log blocks.
-- The slot_index correlates with userid in ops.biobase_cs2_player_snapshot.
CREATE TABLE IF NOT EXISTS game.biobase_cs2_round_stats (
    id           bigserial PRIMARY KEY,
    session_id   uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    recorded_at  timestamptz NOT NULL DEFAULT now(),
    event_ts     timestamptz,
    round_number integer,
    score_t      integer,
    score_ct     integer,
    map          text,
    slot_index   integer,
    accountid    bigint,
    team         integer,
    money        integer,
    kills        integer,
    deaths       integer,
    assists      integer,
    dmg          double precision,
    hsp          double precision,
    kdr          double precision,
    adr          integer,
    mvp          integer,
    ef           integer,
    ud           integer,
    kills_3k     integer,
    kills_4k     integer,
    kills_5k     integer,
    clutchk      integer,
    firstk       integer,
    pistolk      integer,
    sniperk      integer,
    blindk       integer,
    bombk        integer,
    firedmg      double precision,
    uniquek      integer,
    dinks        integer,
    chickenk     integer
);

CREATE INDEX IF NOT EXISTS biobase_cs2_round_stats_session_round
    ON game.biobase_cs2_round_stats (session_id, round_number);
