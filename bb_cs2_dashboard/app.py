"""
bb_cs2_dashboard — admin UI + uploads. Talks to bb_cs2_control over HTTP only (no RCON).
Serves Vite-built SPA from ./static (shadcn dashboard).
"""

from __future__ import annotations

import asyncio
import logging
import mimetypes
import os
import re
import secrets
import socket
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import httpx
from fastapi import FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

CONTROL_URL = os.environ.get("CS2_CONTROL_URL", "http://bb_cs2_control:8765").rstrip("/")
CONTROL_TOKEN = os.environ.get("CS2_CONTROL_TOKEN", "").strip()
DASHBOARD_TOKEN = os.environ.get("BB_CS2_DASHBOARD_TOKEN", "").strip()
DASHBOARD_USER = os.environ.get("BB_CS2_DASHBOARD_USER", "").strip()


def _clips_upload_dir() -> Path:
    """Resolve upload dir: BB_CLIPS_UPLOAD_DIR, then legacy CLIPS_DIR, else container /data/clips."""
    bb = os.environ.get("BB_CLIPS_UPLOAD_DIR", "").strip()
    if bb:
        return Path(bb).resolve()
    legacy = os.environ.get("CLIPS_DIR", "").strip()
    if legacy:
        return Path(legacy).resolve()
    return Path("/data/clips").resolve()


CLIPS_UPLOAD_DIR = _clips_upload_dir()
BB_CLIPS_VM_PATH = os.environ.get("BB_CLIPS_VM_PATH", "").strip()
logger.info(
    "clips upload directory (resolved): %s uid=%s vm_path_hint=%s",
    CLIPS_UPLOAD_DIR,
    os.getuid(),
    BB_CLIPS_VM_PATH or "(unset)",
)
if not os.access(CLIPS_UPLOAD_DIR, os.W_OK):
    logger.warning(
        "clips upload directory is not writable — uploads will fail until the host bind "
        "mount is writable by this user (e.g. chown/chmod on VM path; container runs as "
        "non-root). path=%s",
        CLIPS_UPLOAD_DIR,
    )
MAX_UPLOAD_MB = int(os.environ.get("BB_DASHBOARD_MAX_UPLOAD_MB", "512"))
DEMO_PARSE_MAX_MB = int(os.environ.get("BB_DEMO_PARSE_MAX_MB", "256"))
DEMO_PARSE_ALLOW_URL_FETCH = os.environ.get("BB_DEMO_PARSE_ALLOW_URL_FETCH", "").lower() in (
    "1",
    "true",
    "yes",
)
# Comma-separated host suffixes (e.g. figshare.com matches ndownloader.files.figshare.com).
_DEMO_URL_HOSTS_RAW = os.environ.get(
    "BB_DEMO_PARSE_URL_HOSTS",
    "figshare.com,github.com,raw.githubusercontent.com,objects.githubusercontent.com",
)
DEMO_PARSE_URL_HOST_SUFFIXES = tuple(
    h.strip().lower().lstrip(".") for h in _DEMO_URL_HOSTS_RAW.split(",") if h.strip()
)
# Set true behind HTTPS (e.g. Caddy) so the session cookie is not sent over plain HTTP.
COOKIE_SECURE = os.environ.get("BB_DASHBOARD_COOKIE_SECURE", "").lower() in ("1", "true", "yes")
# When non-empty, dashboard lives under this URL prefix (e.g. /admin). Must match Vite build base.
DASHBOARD_ROOT_PATH = os.environ.get("BB_DASHBOARD_ROOT_PATH", "").strip().rstrip("/")
AUTH_COOKIE_PATH = DASHBOARD_ROOT_PATH if DASHBOARD_ROOT_PATH else "/"

AUTH_COOKIE = "bb_cs2_dashboard_auth"
COOKIE_MAX_AGE = 60 * 60 * 24 * 30  # 30 days

STATIC = Path(__file__).resolve().parent / "static"
dashboard = FastAPI(title="bb_cs2_dashboard", version="0.3.0")

_UNSAFE_NAME = re.compile(r"[^a-zA-Z0-9._-]+")
_CLIP_UUID_PREFIX = re.compile(r"^[0-9a-f]{32}_(.+)$")


def _clip_display_name(storage_name: str) -> str:
    m = _CLIP_UUID_PREFIX.match(storage_name)
    if m:
        return m.group(1)
    return storage_name


def _resolve_stored_clip_file(storage_name: str, *, root: Path | None = None) -> Path:
    """Resolve a basename under the clips directory; raise HTTPException on traversal or missing file."""
    raw = storage_name.strip()
    if not raw:
        raise HTTPException(status_code=400, detail="missing_filename")
    base = Path(raw).name
    if base != raw or base in (".", ".."):
        raise HTTPException(status_code=400, detail="bad_filename")
    base_dir = (root if root is not None else CLIPS_UPLOAD_DIR).resolve()
    candidate = base_dir / base
    try:
        path = candidate.resolve()
    except OSError as e:
        raise HTTPException(status_code=404, detail="not_found") from e
    try:
        if not path.is_file():
            raise HTTPException(status_code=404, detail="not_found")
        if not path.is_relative_to(base_dir):
            raise HTTPException(status_code=400, detail="bad_filename")
    except HTTPException:
        raise
    except OSError as e:
        raise HTTPException(status_code=404, detail="not_found") from e
    return path


def _list_clip_uploads(*, root: Path | None = None) -> list[dict[str, str | int]]:
    base_dir = (root if root is not None else CLIPS_UPLOAD_DIR).resolve()
    if not base_dir.is_dir():
        return []
    items: list[dict[str, str | int]] = []
    try:
        for p in base_dir.iterdir():
            if not p.is_file():
                continue
            name = p.name
            if name.startswith("."):
                continue
            try:
                rp = p.resolve()
                if not rp.is_relative_to(base_dir):
                    continue
                st = p.stat()
            except OSError:
                continue
            mime, _enc = mimetypes.guess_type(name)
            modified = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc)
            items.append(
                {
                    "name": name,
                    "display_name": _clip_display_name(name),
                    "bytes": int(st.st_size),
                    "modified_unix": int(st.st_mtime),
                    "modified_iso": modified.isoformat(),
                    "content_type": mime or "application/octet-stream",
                }
            )
    except OSError:
        return []
    items.sort(key=lambda r: int(r["modified_unix"]), reverse=True)
    return items


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


def _demo_host_allowed(host: str) -> bool:
    h = host.lower().strip(".")
    for suf in DEMO_PARSE_URL_HOST_SUFFIXES:
        if h == suf or h.endswith("." + suf):
            return True
    return False


def _validate_demo_fetch_url(url: str) -> str:
    parsed = urlparse(url.strip())
    if parsed.scheme not in ("https", "http"):
        raise HTTPException(status_code=400, detail="demo_url_scheme_not_allowed")
    host = (parsed.hostname or "").lower()
    if not host:
        raise HTTPException(status_code=400, detail="demo_url_missing_host")
    if parsed.scheme == "http" and host not in ("127.0.0.1", "localhost"):
        raise HTTPException(status_code=400, detail="demo_url_http_only_localhost")
    if not _demo_host_allowed(host):
        raise HTTPException(status_code=400, detail="demo_url_host_not_allowed")
    if not parsed.path and not parsed.netloc:
        raise HTTPException(status_code=400, detail="demo_url_invalid")
    return url.strip()


async def _stream_download_demo(url: str, dest: Path, max_bytes: int) -> None:
    timeout = httpx.Timeout(120.0, connect=30.0)
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
        async with client.stream("GET", url) as resp:
            if resp.status_code >= 400:
                raise HTTPException(
                    status_code=502,
                    detail=f"demo_url_fetch_failed:{resp.status_code}",
                )
            written = 0
            with dest.open("wb") as out:
                async for chunk in resp.aiter_bytes():
                    written += len(chunk)
                    if written > max_bytes:
                        raise HTTPException(status_code=413, detail="demo_url_too_large")
                    out.write(chunk)


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


@dashboard.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "bb_cs2_dashboard"}


@dashboard.get("/api/auth/me")
def auth_me(request: Request) -> dict[str, bool]:
    if not DASHBOARD_TOKEN:
        return {"authenticated": True, "login_required": False}
    cookie = request.cookies.get(AUTH_COOKIE)
    ok = cookie is not None and _tokens_match(cookie, DASHBOARD_TOKEN)
    return {"authenticated": ok, "login_required": True}


@dashboard.post("/api/auth/login")
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
        path=AUTH_COOKIE_PATH,
    )
    return resp


@dashboard.post("/api/auth/logout")
def auth_logout() -> JSONResponse:
    resp = JSONResponse({"ok": True})
    resp.delete_cookie(
        AUTH_COOKIE,
        path=AUTH_COOKIE_PATH,
        httponly=True,
        samesite="lax",
        secure=COOKIE_SECURE,
    )
    return resp


@dashboard.get("/api/demo-extractable-fields")
def api_demo_extractable_fields(
    request: Request,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
) -> JSONResponse:
    """Catalog of demo fields surfaced by awpy/demoparser2 (see demo_field_catalog)."""
    require_dashboard_auth(request, authorization, x_dashboard_key)
    try:
        from demo_field_catalog import build_catalog

        return JSONResponse(build_catalog())
    except ImportError as e:
        logger.exception("demo catalog import failed")
        return JSONResponse(
            {
                "error": "catalog_unavailable",
                "detail": str(e),
                "fields": [],
                "meta": {
                    "extraction": None,
                    "awpy_version": None,
                    "demoparser2_version": None,
                    "disclaimer": "Install awpy in this image (see bb_cs2_dashboard/requirements.txt).",
                },
            },
            status_code=503,
        )


@dashboard.post("/api/demo-parse-preview")
async def api_demo_parse_preview(
    request: Request,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
    file: UploadFile | None = File(None),
    demo_url: str | None = Form(None),
    event_scan_max: int = Form(80),
) -> JSONResponse:
    """
    Upload a .dem or (dev) fetch from demo_url, parse with awpy, return discovered columns/keys.
    """
    require_dashboard_auth(request, authorization, x_dashboard_key)
    has_file = bool(file and file.filename)
    url_raw = (demo_url or "").strip()
    if has_file and url_raw:
        raise HTTPException(status_code=400, detail="provide_file_or_demo_url_not_both")
    if not has_file and not url_raw:
        raise HTTPException(status_code=400, detail="missing_file_or_demo_url")

    max_bytes = DEMO_PARSE_MAX_MB * 1024 * 1024
    scan_cap = max(0, min(int(event_scan_max), 200))

    tmp_path: Path | None = None
    source_name = "demo.dem"

    try:
        if has_file:
            assert file is not None
            if not file.filename or not str(file.filename).lower().endswith(".dem"):
                raise HTTPException(status_code=400, detail="expected_dem_extension")
            source_name = _UNSAFE_NAME.sub("_", Path(file.filename).name)[:200]
            tmp = tempfile.NamedTemporaryFile(suffix=".dem", delete=False)
            tmp_path = Path(tmp.name)
            written = 0
            try:
                while True:
                    chunk = await file.read(1024 * 1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > max_bytes:
                        raise HTTPException(status_code=413, detail="file_too_large")
                    tmp.write(chunk)
            finally:
                tmp.close()
        else:
            if not DEMO_PARSE_ALLOW_URL_FETCH:
                raise HTTPException(
                    status_code=403,
                    detail="demo_url_disabled_set_BB_DEMO_PARSE_ALLOW_URL_FETCH",
                )
            validated = _validate_demo_fetch_url(url_raw)
            derived_name = Path(urlparse(validated).path).name
            if derived_name.lower().endswith(".dem"):
                source_name = _UNSAFE_NAME.sub("_", derived_name)[:200]
            tmp = tempfile.NamedTemporaryFile(suffix=".dem", delete=False)
            tmp_path = Path(tmp.name)
            tmp.close()
            await _stream_download_demo(validated, tmp_path, max_bytes)

        try:
            from demo_parse_preview import build_discovery_from_path

            result = await asyncio.to_thread(
                build_discovery_from_path,
                tmp_path,
                source_filename=source_name,
                event_scan_max=scan_cap,
            )
        except ImportError as e:
            logger.exception("demo parse preview import failed")
            return JSONResponse(
                {
                    "error": "awpy_unavailable",
                    "detail": str(e),
                    "meta": {
                        "disclaimer": "Install awpy in this image (bb_cs2_dashboard/requirements.txt).",
                    },
                },
                status_code=503,
            )
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
        except FileNotFoundError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
        except HTTPException:
            raise
        except Exception as e:  # noqa: BLE001
            logger.exception("demo parse failed")
            return JSONResponse(
                {"error": "parse_failed", "detail": str(e)[:1200]},
                status_code=422,
            )
        return JSONResponse(result)
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)


@dashboard.get("/api/status")
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


@dashboard.post("/api/bots/start")
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


@dashboard.post("/api/bots/stop")
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


@dashboard.post("/api/map")
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


@dashboard.get("/api/uploads")
@dashboard.get("/api/uploads/")
def api_uploads_list(
    request: Request,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
) -> JSONResponse:
    require_dashboard_auth(request, authorization, x_dashboard_key)
    items = _list_clip_uploads()
    return JSONResponse({"ok": True, "items": items, "vm_clips_path": BB_CLIPS_VM_PATH or None})


@dashboard.get("/api/uploads/download/{storage_name}")
def api_uploads_download(
    request: Request,
    storage_name: str,
    authorization: str | None = Header(None),
    x_dashboard_key: str | None = Header(None, alias="X-Dashboard-Key"),
) -> FileResponse:
    require_dashboard_auth(request, authorization, x_dashboard_key)
    path = _resolve_stored_clip_file(storage_name)
    basename = path.name
    media = mimetypes.guess_type(basename)[0] or "application/octet-stream"
    return FileResponse(
        path,
        media_type=media,
        filename=_clip_display_name(basename),
    )


@dashboard.post("/api/uploads")
@dashboard.post("/api/uploads/")
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
    dest = CLIPS_UPLOAD_DIR / dest_name
    CLIPS_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
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
    return JSONResponse(
        {
            "ok": True,
            "saved_as": dest_name,
            "bytes": written,
            "vm_clips_path": BB_CLIPS_VM_PATH or None,
            "host": socket.gethostname(),
        }
    )


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
    dashboard.mount(
        "/assets",
        StaticFiles(directory=_assets_dir),
        name="assets",
    )


@dashboard.get("/")
def index() -> FileResponse:
    return _spa_index()


@dashboard.get("/favicon.svg", include_in_schema=False)
def favicon() -> FileResponse:
    p = STATIC / "favicon.svg"
    if p.is_file():
        return FileResponse(p, media_type="image/svg+xml")
    raise HTTPException(status_code=404)


@dashboard.get("/{full_path:path}", include_in_schema=False)
def spa_fallback(full_path: str) -> FileResponse:
    if full_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="Not Found")
    if full_path.startswith("assets/"):
        raise HTTPException(status_code=404)
    candidate = STATIC / full_path
    if candidate.is_file() and candidate.resolve().is_relative_to(STATIC.resolve()):
        return FileResponse(candidate)
    return _spa_index()


if DASHBOARD_ROOT_PATH:

    def _admin_redirect_trailing_slash() -> RedirectResponse:
        return RedirectResponse(url=f"{DASHBOARD_ROOT_PATH}/", status_code=307)

    app = FastAPI()
    app.add_api_route(
        DASHBOARD_ROOT_PATH,
        _admin_redirect_trailing_slash,
        methods=["GET"],
        include_in_schema=False,
    )
    app.mount(DASHBOARD_ROOT_PATH, dashboard)
else:
    app = dashboard
