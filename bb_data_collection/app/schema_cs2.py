"""Idempotent CS2 session ingest tables (also in bb_client/initdb/002-004_*.sql)."""


def statements() -> list[str]:
    return [
        """
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
        """,
        """
        CREATE TABLE IF NOT EXISTS public.biobase_cs2_rcon_sample (
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
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_rcon_sample_session_time
        ON public.biobase_cs2_rcon_sample (session_id, sampled_at);
        """,
        """
        CREATE TABLE IF NOT EXISTS public.biobase_cs2_log_line (
            id              bigserial PRIMARY KEY,
            session_id      uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
            ingested_at     timestamptz NOT NULL DEFAULT now(),
            loki_ts_ns      bigint,
            line            text NOT NULL
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_log_line_session
        ON public.biobase_cs2_log_line (session_id);
        """,
        """
        ALTER TABLE public.biobase_cs2_match_session
          ADD COLUMN IF NOT EXISTS cancel_requested boolean NOT NULL DEFAULT false;
        """,
        # --- Granular telemetry (004_granular_telemetry.sql) ---
        """
        CREATE TABLE IF NOT EXISTS public.biobase_cs2_player_snapshot (
            id              bigserial PRIMARY KEY,
            session_id      uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
            rcon_sample_id  bigint REFERENCES public.biobase_cs2_rcon_sample (id) ON DELETE CASCADE,
            sampled_at      timestamptz NOT NULL DEFAULT now(),
            userid          integer,
            player_name     text,
            steamid         text,
            connected       text,
            ping            integer,
            loss            integer,
            state           text
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_player_snapshot_session_time
            ON public.biobase_cs2_player_snapshot (session_id, sampled_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_player_snapshot_player
            ON public.biobase_cs2_player_snapshot (player_name, steamid);
        """,
        """
        CREATE TABLE IF NOT EXISTS public.biobase_cs2_game_event (
            id               bigserial PRIMARY KEY,
            session_id       uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
            log_line_id      bigint REFERENCES public.biobase_cs2_log_line (id) ON DELETE SET NULL,
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
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_game_event_session_type
            ON public.biobase_cs2_game_event (session_id, event_type);
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_game_event_session_ts
            ON public.biobase_cs2_game_event (session_id, event_ts);
        """,
        """
        CREATE TABLE IF NOT EXISTS public.biobase_cs2_movement_sample (
            id          bigserial PRIMARY KEY,
            session_id  uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
            log_line_id bigint REFERENCES public.biobase_cs2_log_line (id) ON DELETE SET NULL,
            sampled_at  timestamptz NOT NULL DEFAULT now(),
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
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_movement_sample_session_time
            ON public.biobase_cs2_movement_sample (session_id, sampled_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_movement_sample_player
            ON public.biobase_cs2_movement_sample (player_name, steamid);
        """,
        # --- Round stats (per-player cumulative stats from JSON_BEGIN/END blocks) ---
        """
        CREATE TABLE IF NOT EXISTS public.biobase_cs2_round_stats (
            id           bigserial PRIMARY KEY,
            session_id   uuid NOT NULL REFERENCES public.biobase_cs2_match_session (id) ON DELETE CASCADE,
            recorded_at  timestamptz NOT NULL DEFAULT now(),
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
        """,
        """
        CREATE INDEX IF NOT EXISTS biobase_cs2_round_stats_session_round
            ON public.biobase_cs2_round_stats (session_id, round_number);
        """,
    ]
