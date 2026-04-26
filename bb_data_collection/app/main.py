"""
Biobase data collection (client-shipped). Phase 1: ingest CS2 plugin / gameplay data
into Postgres — not server health. Expand with plugin-specific collectors in layers.
"""

import logging
import os
from contextlib import asynccontextmanager, contextmanager
from typing import Any

import psycopg2
from fastapi import FastAPI

DATABASE_URL = os.environ.get("DATABASE_URL", "")

log = logging.getLogger(__name__)


@contextmanager
def db_conn() -> Any:
    conn = psycopg2.connect(DATABASE_URL)
    try:
        yield conn
    finally:
        conn.close()


def db_ready() -> bool:
    if not DATABASE_URL:
        return False
    try:
        with db_conn() as c:
            with c.cursor() as cur:
                cur.execute("SELECT 1")
        return True
    except Exception:
        return False


def ensure_ingest_stub_table() -> None:
    """
    One idempotent public table + row so Grafana (and devs) have something to read.
    Safe to re-run. Replace with real migrations when ingest shape stabilizes.
    """
    if not DATABASE_URL:
        return
    try:
        with db_conn() as conn:
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS public.biobase_ingest_sample (
                        id         bigserial PRIMARY KEY,
                        created_at timestamptz NOT NULL DEFAULT now(),
                        note       text
                    );
                    """
                )
                cur.execute(
                    """
                    INSERT INTO public.biobase_ingest_sample (note)
                    SELECT 'stub: replace with real ingest rows'
                    WHERE NOT EXISTS (SELECT 1 FROM public.biobase_ingest_sample LIMIT 1);
                    """
                )
    except Exception as e:
        log.warning("ensure_ingest_stub_table failed (Grafana/DB checks may be empty): %s", e)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    ensure_ingest_stub_table()
    yield


app = FastAPI(
    title="bb_data_collection",
    description="Game and player data ingest for Biobase (not infra monitoring).",
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready")
def ready() -> dict[str, Any]:
    ok = db_ready()
    return {"ready": ok, "database": "connected" if ok else "unavailable"}


@app.get("/")
def root() -> dict[str, str]:
    return {
        "service": "bb_data_collection",
        "note": "Phase 1: add CS2 plugin → Postgres pipelines here",
    }
