"""
Biobase data collection: CS2 + KZ session ingest to Postgres, API for summaries.
"""

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from contextlib import contextmanager
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

import psycopg2
from fastapi import Body, FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.schema_cs2 import statements as cs2_table_statements
from app.session_ingest import run_session
from app.summary import load_summary
from app.summary_text import format_summary_text

log = logging.getLogger(__name__)

DATABASE_URL = os.environ.get("DATABASE_URL", "")
LOKI_URL = os.environ.get("LOKI_URL", "http://bb_monitor_loki:3100")
CS2_CONTROL_URL = os.environ.get("CS2_CONTROL_URL", "http://bb_cs2_control:8765")
CS2_CONTROL_TOKEN = os.environ.get("CS2_CONTROL_TOKEN", "").strip()

logging.basicConfig(level=logging.INFO)


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
    except Exception:  # noqa: BLE001
        return False


def ensure_ingest_stub_table() -> None:
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
    except Exception as e:  # noqa: BLE001
        log.warning("ensure_ingest_stub_table failed: %s", e)


def ensure_cs2_tables() -> None:
    if not DATABASE_URL:
        return
    try:
        with db_conn() as conn:
            conn.autocommit = True
            with conn.cursor() as cur:
                for stmt in cs2_table_statements():
                    cur.execute(stmt)
    except Exception as e:  # noqa: BLE001
        log.warning("ensure_cs2_tables failed: %s", e)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    ensure_ingest_stub_table()
    ensure_cs2_tables()
    yield


app = FastAPI(
    title="bb_data_collection",
    description="CS2 / KZ gameplay and log ingest into Postgres; session summaries.",
    version="0.2.0",
    lifespan=lifespan,
)


class SessionStartRequest(BaseModel):
    duration_seconds: int = Field(default=300, ge=10, le=86_400)
    rcon_interval_seconds: float = Field(default=5.0, ge=1.0, le=120.0)
    label: str | None = Field(default=None, max_length=200)


class HubSessionRequest(BaseModel):
    """Defaults tuned for hub: long window, cancel via hub Stop."""

    duration_seconds: int = Field(default=86_400, ge=120, le=86_400)
    rcon_interval_seconds: float = Field(default=5.0, ge=1.0, le=120.0)


def _insert_pending_session(
    session_id: UUID,
    label: str | None,
    duration_sec: int,
) -> None:
    with db_conn() as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO public.biobase_cs2_match_session
                (id, label, status, duration_requested)
                VALUES (%s, %s, 'pending', %s)
                """,
                (str(session_id), label, duration_sec),
            )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready")
def ready() -> dict[str, Any]:
    ok = db_ready()
    return {"ready": ok, "database": "connected" if ok else "unavailable"}


@app.get("/")
def root() -> dict[str, str | list[str]]:
    return {
        "service": "bb_data_collection",
        "v1": "POST /v1/sessions  —  start a timed collection session (RCON + Loki from bb_cs2_server logs)",
    }


@app.post("/v1/sessions", status_code=202)
async def start_session(body: SessionStartRequest) -> dict[str, Any]:
    if not DATABASE_URL:
        raise HTTPException(503, "DATABASE_URL not set")
    ensure_cs2_tables()
    session_id = uuid4()
    _insert_pending_session(session_id, body.label, body.duration_seconds)
    coro = run_session(
        database_url=DATABASE_URL,
        loki_url=LOKI_URL,
        control_url=CS2_CONTROL_URL,
        control_token=CS2_CONTROL_TOKEN,
        session_id=session_id,
        duration_sec=body.duration_seconds,
        label=body.label,
        rcon_interval_sec=body.rcon_interval_seconds,
    )
    asyncio.create_task(coro)
    return {
        "session_id": str(session_id),
        "status": "accepted",
        "duration_seconds": body.duration_seconds,
        "rcon_interval_seconds": body.rcon_interval_seconds,
    }


def _running_hub_session_id() -> UUID | None:
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id FROM public.biobase_cs2_match_session
                WHERE status = 'running' AND label LIKE 'hub-auto%%'
                ORDER BY coalesce(started_at, created_at) DESC
                LIMIT 1
                """
            )
            row = cur.fetchone()
    if not row:
        return None
    return UUID(str(row[0]))


@app.post("/v1/sessions/hub/start", status_code=202)
async def hub_start_collection(
    body: HubSessionRequest | None = Body(default=None),
) -> dict[str, Any]:
    """Start (or reuse) a long-lived ingest session for the operator hub."""
    if not DATABASE_URL:
        raise HTTPException(503, "DATABASE_URL not set")
    ensure_cs2_tables()
    if body is None:
        body = HubSessionRequest()
    existing = _running_hub_session_id()
    if existing:
        return {
            "session_id": str(existing),
            "status": "already_running",
            "duration_seconds": body.duration_seconds,
            "rcon_interval_seconds": body.rcon_interval_seconds,
        }
    session_id = uuid4()
    label = f"hub-auto-{datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ')}"
    _insert_pending_session(session_id, label, body.duration_seconds)
    coro = run_session(
        database_url=DATABASE_URL,
        loki_url=LOKI_URL,
        control_url=CS2_CONTROL_URL,
        control_token=CS2_CONTROL_TOKEN,
        session_id=session_id,
        duration_sec=body.duration_seconds,
        label=label,
        rcon_interval_sec=body.rcon_interval_seconds,
    )
    asyncio.create_task(coro)
    return {
        "session_id": str(session_id),
        "status": "accepted",
        "duration_seconds": body.duration_seconds,
        "rcon_interval_seconds": body.rcon_interval_seconds,
        "label": label,
    }


@app.post("/v1/sessions/hub/stop")
def hub_stop_collection() -> dict[str, Any]:
    """Signal all running hub-auto sessions to stop sampling and flush Loki to Postgres."""
    if not DATABASE_URL:
        raise HTTPException(503, "DATABASE_URL not set")
    ensure_cs2_tables()
    with db_conn() as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE public.biobase_cs2_match_session
                SET cancel_requested = true
                WHERE status = 'running' AND label LIKE 'hub-auto%%'
                """
            )
            n = cur.rowcount
    return {"cancel_requested_rows": n}


@app.post("/v1/sessions/{session_id}/cancel")
def cancel_session(session_id: UUID) -> dict[str, Any]:
    if not DATABASE_URL:
        raise HTTPException(503, "DATABASE_URL not set")
    ensure_cs2_tables()
    with db_conn() as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE public.biobase_cs2_match_session
                SET cancel_requested = true
                WHERE id = %s AND status = 'running'
                """,
                (str(session_id),),
            )
            n = cur.rowcount
    if n == 0:
        raise HTTPException(404, "no running session with that id")
    return {"session_id": str(session_id), "cancel_requested": True}


@app.get("/v1/sessions/{session_id}")
def get_session(session_id: UUID) -> dict[str, Any]:
    if not DATABASE_URL:
        raise HTTPException(503, "DATABASE_URL not set")
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id, label, status, duration_requested, created_at, started_at, ended_at,
                       loki_start_ns, loki_end_ns, error_message, cancel_requested
                FROM public.biobase_cs2_match_session
                WHERE id = %s
                """,
                (str(session_id),),
            )
            row = cur.fetchone()
    if not row:
        raise HTTPException(404, "session not found")
    return {
        "session_id": str(row[0]),
        "label": row[1],
        "status": row[2],
        "duration_requested": row[3],
        "created_at": row[4].isoformat() if row[4] else None,
        "started_at": row[5].isoformat() if row[5] else None,
        "ended_at": row[6].isoformat() if row[6] else None,
        "loki_start_ns": row[7],
        "loki_end_ns": row[8],
        "error_message": row[9],
        "cancel_requested": row[10],
    }


@app.get("/v1/sessions/{session_id}/summary")
def get_summary(
    request: Request,
    session_id: UUID,
) -> Any:
    if not DATABASE_URL:
        raise HTTPException(503, "DATABASE_URL not set")
    s = load_summary(DATABASE_URL, session_id)
    if s is None:
        raise HTTPException(404, "session not found")
    accept = request.headers.get("accept", "")
    if "text/plain" in accept and "application/json" not in accept:
        return Response(
            content=format_summary_text(s),
            media_type="text/plain; charset=utf-8",
        )
    return s
