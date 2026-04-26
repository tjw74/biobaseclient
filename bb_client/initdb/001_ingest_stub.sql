-- Shipped with first boot of bb_postgres (docker-entrypoint-initdb.d). Idempotent
-- for safety if re-applied; bb_data_collection also runs the same on startup.
CREATE TABLE IF NOT EXISTS public.biobase_ingest_sample (
    id         bigserial PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    note       text
);

INSERT INTO public.biobase_ingest_sample (note)
SELECT 'stub: replace with real ingest rows'
WHERE NOT EXISTS (SELECT 1 FROM public.biobase_ingest_sample LIMIT 1);
