"""
bb_cs2_dashboard — admin UI + uploads. Talks to bb_cs2_control over HTTP only (no RCON).
Serves Vite-built SPA from ./static (shadcn dashboard).
"""

from __future__ import annotations

import os
import re
import secrets
import uuid
from pathlib import Path

import httpx
from fastapi import FastAPI, File, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

CONTROL_URL = os.environ.get("CS2_CONTROL_URL", "http://bb_cs2_control:8765").rstrip("/")
CONTROL_TOKEN = os.environ.get("CS2_CONTROL_TOKEN", "").strip()
DASHBOARD_TOKEN = os.environ.get("BB_CS2_DASHBOARD_TOKEN", "").strip()
DASHBOARD_USER = os.environ.get("BB_CS2_DASHBOARD_USER", "").strip()
CLIPS_DIR = Path(os.environ.get("CLIPS_DIR", "/data/clips")).resolve()
MAX_UPLOAD_MB = int(os.environ.get("BB_DASHBOARD_MAX_UPLOAD_MB", "512"))
# Set true behind HTTPS (e.g. Caddy) so the session cookie is not sent over plain HTTP.
COOKIE_SECURE = os.environ.get("BB_DASHBOARD_COOKIE_SECURE", "").lower() in ("1", "true", "yes")

AUTH_COOKIE = "bb_cs2_dashboard_auth"
COOKIE_MAX_AGE = 60 * 60 * 24 * 30  # 30 days

STATIC = Path(__file__).resolve().parent / "static"
app = FastAPI(title="bb_cs2_dashboard", version="0.3.0")

_UNSAFE_NAME = re.compile(r"[^a-zA-Z0-9._-]+")


class LoginBody(BaseModel):
    username: str = ""
    password: str = ""
    token: str = ""

    def effective_password(self) -> str:
        return (self.password or self.token or "").strip()


class MapChangeBody(BaseModel):
    map: str = Field(..., min_length=1, max_length=96)


def _tokens_match(received: str, expected: str) -> bool:
    if len(received) != len(expected):
        return False
    return secrets.compare_digest(received.encode("utf-8"), expected.encode("utf-8"))


def _request_authenticated(
    request: Request,
    authorization: str | None,
    x_dashboard_key: str | None,
) -> bool:
    if not DASHBOARD_TOKEN:
        return True
    cookie = request.cookies.get(AUTH_COOKIE)
    if cookie is not None and _tokens_match(cookie, DASHBOARD_TOKEN):
        return True
    if x_dashboard_key is not None and _tokens_match(x_dashboard_key, DASHBOARD_TOKEN):
        return True
    if authorization and authorization.startswith("Bearer ") and _tokens_match(
        authorization[7:],
        DASHBOARD_TOKEN,
    ):
        return True
    return False


def require_dashboard_auth(
    request: Request,
    authorization: str | None = None,
    x_dashboard_key: str | None = None,
) -> None:
    if not _request_authenticated(request, authorization, x_dashboard_key):
        raise HTTPException(status_code=401, detail="Unauthorized")


def _control_headers() -> dict[str, str]:
    h: dict[str, str] = {}
    if CONTROL_TOKEN:
        h["X-Api-Key"] = CONTROL_TOKEN
    return h


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "bb_cs2_dashboard"}


@app.get("/api/auth/me")
def auth_me(request: Request) -> dict[str, bool]:
    if not DASHBOARD_TOKEN:
        return {"authenticated": True, "login_required": False}
    cookie = request.cookies.get(AUTH_COOKIE)
    ok = cookie is not None and _tokens_match(cookie, DASHBOARD_TOKEN)
    return {"authenticated": ok, "login_required": True}


@app.post("/api/auth/login")
def auth_login(body: LoginBody) -> JSONResponse:
    if not DASHBOARD_TOKEN:
        return JSONResponse({"ok": True})
    pwd = body.effective_password()
    user_ok = True
    if DASHBOARD_USER:
        user_ok = _tokens_match(body.username.strip(), DASHBOARD_USER)
    pass_ok = bool(pwd) and _tokens_match(pwd, DASHBOARD_TOKEN)
    if not user_ok or not pass_ok:
        raise HTTPException(status_code=401, detail="Invalid username or password")
    resp = JSONResponse({"ok": True})
    resp.set_cookie(
        AUTH_COOKIE,
        DASHBOARD_TOKEN,
        max_age=COOKIE_MAX_AGE,
        httponly=True,
        samesite="lax",
        secure=COOKIE_SECURE,
        path="/",
    )
    return resp


@app.post("/api/auth/logout")
def auth_logout() -> JSONResponse:
    resp = JSONResponse({"ok": True})
    resp.delete_cookie(
        AUTH_COOKIE,
        path="/",
        httponly=True,
        samesite="lax",
        secure=COOKIE_SECURE,
    )
    return resp


@app.get("/api/status")
def api_status(
    request: Request,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
) -> JSONResponse:
    require_dashboard_auth(request, authorization, x_dashboard_key)
    try:
        r = httpx.get(f"{CONTROL_URL}/api/status", headers=_control_headers(), timeout=30.0)
    except httpx.RequestError as e:
        return JSONResponse(
            {"error": "control_unreachable", "detail": str(e)[:500]},
            status_code=502,
        )
    try:
        data = r.json()
    except Exception:
        data = {"error": "bad_json", "raw": (r.text or "")[:2000]}
    return JSONResponse(data, status_code=r.status_code if 200 <= r.status_code < 500 else 502)


@app.post("/api/bots/start")
def api_bots_start(
    request: Request,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
) -> JSONResponse:
    require_dashboard_auth(request, authorization, x_dashboard_key)
    try:
        r = httpx.post(
            f"{CONTROL_URL}/api/bots/start",
            headers=_control_headers(),
            timeout=60.0,
        )
    except httpx.RequestError as e:
        return JSONResponse({"ok": False, "error": str(e)[:500]}, status_code=502)
    try:
        data = r.json()
    except Exception:
        data = {"ok": False, "raw": (r.text or "")[:2000]}
    return JSONResponse(data, status_code=r.status_code)


@app.post("/api/bots/stop")
def api_bots_stop(
    request: Request,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
) -> JSONResponse:
    require_dashboard_auth(request, authorization, x_dashboard_key)
    try:
        r = httpx.post(
            f"{CONTROL_URL}/api/bots/stop",
            headers=_control_headers(),
            timeout=60.0,
        )
    except httpx.RequestError as e:
        return JSONResponse({"ok": False, "error": str(e)[:500]}, status_code=502)
    try:
        data = r.json()
    except Exception:
        data = {"ok": False, "raw": (r.text or "")[:2000]}
    return JSONResponse(data, status_code=r.status_code)


@app.post("/api/map")
def api_map_change(
    request: Request,
    body: MapChangeBody,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
) -> JSONResponse:
    require_dashboard_auth(request, authorization, x_dashboard_key)
    hdr = {**_control_headers(), "Content-Type": "application/json"}
    try:
        r = httpx.post(
            f"{CONTROL_URL}/api/map",
            headers=hdr,
            json={"map": body.map},
            timeout=60.0,
        )
    except httpx.RequestError as e:
        return JSONResponse({"ok": False, "error": str(e)[:500]}, status_code=502)
    try:
        data = r.json()
    except Exception:
        data = {"ok": False, "raw": (r.text or "")[:2000]}
    # Control auth uses a different token; don't surface as dashboard session 401.
    if r.status_code == 401:
        return JSONResponse(
            {
                "ok": False,
                "error": "Control API rejected the key — set BB_CS2_CONTROL_TOKEN the same on bb_cs2_control and dashboard (CS2_CONTROL_TOKEN).",
            },
            status_code=502,
        )
    if r.status_code == 404:
        return JSONResponse(
            {
                "ok": False,
                "error": "Control has no /api/map — rebuild & recreate bb_cs2_control (docker compose build bb_cs2_control && up -d).",
            },
            status_code=502,
        )
    return JSONResponse(data, status_code=r.status_code)


@app.post("/api/uploads")
async def api_uploads(
    request: Request,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
    file: UploadFile = File(...),
) -> JSONResponse:
    require_dashboard_auth(request, authorization, x_dashboard_key)
    if not file.filename:
        raise HTTPException(status_code=400, detail="missing_filename")
    safe = _UNSAFE_NAME.sub("_", Path(file.filename).name)[:200]
    if not safe or safe in (".", ".."):
        raise HTTPException(status_code=400, detail="bad_filename")
    dest_name = f"{uuid.uuid4().hex}_{safe}"
    dest = CLIPS_DIR / dest_name
    CLIPS_DIR.mkdir(parents=True, exist_ok=True)
    max_bytes = MAX_UPLOAD_MB * 1024 * 1024
    written = 0
    try:
        with dest.open("wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                written += len(chunk)
                if written > max_bytes:
                    out.close()
                    dest.unlink(missing_ok=True)
                    raise HTTPException(status_code=413, detail="file_too_large")
                out.write(chunk)
    except HTTPException:
        dest.unlink(missing_ok=True)
        raise
    except OSError as e:
        dest.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail=str(e)[:200]) from e
    return JSONResponse({"ok": True, "saved_as": dest_name, "bytes": written})


def _spa_index() -> FileResponse:
    p = STATIC / "index.html"
    if not p.is_file():
        raise HTTPException(
            status_code=500,
            detail="Dashboard UI missing — run frontend build (see Dockerfile).",
        )
    return FileResponse(p, media_type="text/html; charset=utf-8")


_assets_dir = STATIC / "assets"
if _assets_dir.is_dir():
    app.mount(
        "/assets",
        StaticFiles(directory=_assets_dir),
        name="assets",
    )


@app.get("/")
def index() -> FileResponse:
    return _spa_index()


@app.get("/favicon.svg", include_in_schema=False)
def favicon() -> FileResponse:
    p = STATIC / "favicon.svg"
    if p.is_file():
        return FileResponse(p, media_type="image/svg+xml")
    raise HTTPException(status_code=404)


@app.get("/{full_path:path}", include_in_schema=False)
def spa_fallback(full_path: str) -> FileResponse:
    if full_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="Not Found")
    if full_path.startswith("assets/"):
        raise HTTPException(status_code=404)
    candidate = STATIC / full_path
    if candidate.is_file() and candidate.resolve().is_relative_to(STATIC.resolve()):
        return FileResponse(candidate)
    return _spa_index()
