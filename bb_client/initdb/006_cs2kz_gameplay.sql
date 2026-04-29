-- CS2KZ local SQLite mirror: times (runs), jumpstats, players — see CS2KZ db schema in
-- https://github.com/KZGlobalTeam/cs2kz-metamod (src/kz/db/queries/*.h)

CREATE TABLE IF NOT EXISTS public.biobase_cs2kz_sqlite_cursor (
    session_id   uuid    NOT NULL
        REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    table_name   text    NOT NULL,
    last_rowid   bigint  NOT NULL DEFAULT 0,
    PRIMARY KEY (session_id, table_name)
);

CREATE TABLE IF NOT EXISTS public.biobase_cs2kz_player (
    id              bigserial PRIMARY KEY,
    session_id      uuid        NOT NULL
        REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    steamid64       bigint      NOT NULL,
    alias           text,
    ip              text,
    preferences     text,
    cheater         integer     NOT NULL DEFAULT 0,
    last_played     timestamptz,
    created_server  timestamptz,
    ingested_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, steamid64)
);

CREATE INDEX IF NOT EXISTS biobase_cs2kz_player_session_time
    ON public.biobase_cs2kz_player (session_id, ingested_at DESC);

CREATE TABLE IF NOT EXISTS public.biobase_cs2kz_run (
    id               bigserial PRIMARY KEY,
    session_id       uuid           NOT NULL
        REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    time_id          text           NOT NULL,
    steamid64        bigint         NOT NULL,
    map_course_id    integer,
    map_name         text,
    course_name      text,
    mode_id          integer,
    mode_name        text,
    mode_short       text,
    style_id_flags   bigint,
    run_time         double precision NOT NULL,
    teleports        bigint         NOT NULL,
    metadata         text,
    created_unix     bigint,
    sqlite_rowid     bigint,
    ingested_at      timestamptz    NOT NULL DEFAULT now(),
    UNIQUE (session_id, time_id)
);

CREATE INDEX IF NOT EXISTS biobase_cs2kz_run_session_time
    ON public.biobase_cs2kz_run (session_id, ingested_at DESC);

CREATE INDEX IF NOT EXISTS biobase_cs2kz_run_player
    ON public.biobase_cs2kz_run (session_id, steamid64);

CREATE TABLE IF NOT EXISTS public.biobase_cs2kz_jumpstat (
    id             bigserial PRIMARY KEY,
    session_id     uuid        NOT NULL
        REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
    jumpstat_id    integer     NOT NULL,
    steamid64      bigint      NOT NULL,
    jump_type      integer     NOT NULL,
    mode_id        integer     NOT NULL,
    mode_name      text,
    distance       integer     NOT NULL,
    is_block_jump  integer     NOT NULL,
    block          integer     NOT NULL,
    strafes        integer     NOT NULL,
    sync           integer     NOT NULL,
    pre            integer     NOT NULL,
    jump_air_max   integer     NOT NULL,
    airtime        integer     NOT NULL,
    created_unix   bigint,
    sqlite_rowid   bigint      NOT NULL,
    ingested_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, jumpstat_id)
);

CREATE INDEX IF NOT EXISTS biobase_cs2kz_jumpstat_session_time
    ON public.biobase_cs2kz_jumpstat (session_id, ingested_at DESC);

CREATE INDEX IF NOT EXISTS biobase_cs2kz_jumpstat_player
    ON public.biobase_cs2kz_jumpstat (session_id, steamid64);
