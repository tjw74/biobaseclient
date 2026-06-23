-- Shadow Move capture and comparison schema (reference — runtime uses SQLite)

CREATE TABLE IF NOT EXISTS game.shadow_move (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_user_id TEXT DEFAULT '',
    creator_steam_id TEXT DEFAULT '',
    name            TEXT NOT NULL,
    description     TEXT DEFAULT '',
    map_name        TEXT DEFAULT '',
    move_type       TEXT DEFAULT 'general',
    difficulty      TEXT DEFAULT 'medium',
    tags            JSONB DEFAULT '[]',
    start_tick      INTEGER DEFAULT 0,
    end_tick        INTEGER DEFAULT 0,
    duration_ticks  INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    visibility      TEXT DEFAULT 'private',
    status          TEXT DEFAULT 'draft'
);

CREATE TABLE IF NOT EXISTS game.shadow_move_tick (
    id              BIGSERIAL PRIMARY KEY,
    shadow_move_id  UUID NOT NULL REFERENCES game.shadow_move(id) ON DELETE CASCADE,
    tick_offset     INTEGER NOT NULL,
    x               DOUBLE PRECISION NOT NULL,
    y               DOUBLE PRECISION NOT NULL,
    z               DOUBLE PRECISION NOT NULL,
    vel_x           DOUBLE PRECISION DEFAULT 0,
    vel_y           DOUBLE PRECISION DEFAULT 0,
    vel_z           DOUBLE PRECISION DEFAULT 0,
    speed           DOUBLE PRECISION DEFAULT 0,
    yaw             DOUBLE PRECISION DEFAULT 0,
    pitch           DOUBLE PRECISION DEFAULT 0,
    on_ground       BOOLEAN DEFAULT TRUE,
    ducking         BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_shadow_move_tick_move ON game.shadow_move_tick(shadow_move_id);
CREATE INDEX IF NOT EXISTS idx_shadow_move_tick_offset ON game.shadow_move_tick(shadow_move_id, tick_offset);

CREATE TABLE IF NOT EXISTS game.shadow_attempt (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         TEXT DEFAULT '',
    steam_id        TEXT DEFAULT '',
    shadow_move_id  UUID NOT NULL REFERENCES game.shadow_move(id),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at    TIMESTAMPTZ,
    score_overall   DOUBLE PRECISION DEFAULT 0,
    score_path      DOUBLE PRECISION DEFAULT 0,
    score_speed     DOUBLE PRECISION DEFAULT 0,
    score_timing    DOUBLE PRECISION DEFAULT 0,
    status          TEXT DEFAULT 'completed'
);

CREATE INDEX IF NOT EXISTS idx_shadow_attempt_move ON game.shadow_attempt(shadow_move_id);

CREATE TABLE IF NOT EXISTS game.shadow_attempt_tick (
    id              BIGSERIAL PRIMARY KEY,
    attempt_id      UUID NOT NULL REFERENCES game.shadow_attempt(id) ON DELETE CASCADE,
    tick_offset     INTEGER NOT NULL,
    x               DOUBLE PRECISION NOT NULL,
    y               DOUBLE PRECISION NOT NULL,
    z               DOUBLE PRECISION NOT NULL,
    vel_x           DOUBLE PRECISION DEFAULT 0,
    vel_y           DOUBLE PRECISION DEFAULT 0,
    vel_z           DOUBLE PRECISION DEFAULT 0,
    speed           DOUBLE PRECISION DEFAULT 0,
    yaw             DOUBLE PRECISION DEFAULT 0,
    pitch           DOUBLE PRECISION DEFAULT 0,
    on_ground       BOOLEAN DEFAULT TRUE,
    ducking         BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_shadow_attempt_tick_attempt ON game.shadow_attempt_tick(attempt_id);
CREATE INDEX IF NOT EXISTS idx_shadow_attempt_tick_offset ON game.shadow_attempt_tick(attempt_id, tick_offset);
