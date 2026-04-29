-- Shipped with first boot of bb_postgres (docker-entrypoint-initdb.d). Idempotent
-- for safety if re-applied; bb_data_collection also runs the same on startup.
-- Stub table lives in ops (not game); session anchor remains in public.
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.biobase_ingest_sample (
    id         bigserial PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    note       text
);

INSERT INTO ops.biobase_ingest_sample (note)
SELECT 'stub: replace with real ingest rows'
WHERE NOT EXISTS (SELECT 1 FROM ops.biobase_ingest_sample LIMIT 1);
