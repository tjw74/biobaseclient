const cred: RequestCredentials = "include"

/** Vite `base` (e.g. `/admin/`) so API paths work when hosted under a URL prefix on the same host. */
function apiPrefix(): string {
  const raw = import.meta.env.BASE_URL
  if (raw && raw !== "/") {
    return raw.endsWith("/") ? raw : `${raw}/`
  }
  // Built with base `/`: infer prefix from `<base href>` (Vite injects it) or from the browser path.
  if (typeof document !== "undefined") {
    const href = document.querySelector("base")?.getAttribute("href")
    if (href) {
      try {
        const path = new URL(href, window.location.origin).pathname
        if (path && path !== "/") {
          return path.endsWith("/") ? path : `${path}/`
        }
      } catch {
        /* ignore */
      }
    }
  }
  if (typeof window !== "undefined") {
    const p = window.location.pathname
    if (p === "/admin" || p.startsWith("/admin/")) {
      return "/admin/"
    }
  }
  return "/"
}

function apiUrl(subpath: string): string {
  const p = subpath.startsWith("/") ? subpath.slice(1) : subpath
  return `${apiPrefix()}${p}`
}

function headers(json = false): HeadersInit {
  const h: Record<string, string> = {}
  if (json) {
    h.Accept = "application/json"
  }
  return h
}

function fastApiDetailString(detail: unknown): string | undefined {
  if (typeof detail === "string") {
    return detail
  }
  if (Array.isArray(detail) && detail[0] != null) {
    const row = detail[0] as { msg?: string }
    if (typeof row.msg === "string") {
      return row.msg
    }
  }
  return undefined
}

export type StatusResponse = {
  headline?: string
  humans?: number | null
  bots?: number | null
  map?: string | null
  hostname?: string | null
  rcon_ok?: boolean
  error?: string
  detail?: string
  raw?: string
}

export async function fetchAuthMe(): Promise<{
  authenticated: boolean
  login_required: boolean
}> {
  const r = await fetch(apiUrl("/api/auth/me"), { credentials: cred })
  return (await r.json()) as { authenticated: boolean; login_required: boolean }
}

export async function postLogin(username: string, password: string): Promise<boolean> {
  const r = await fetch(apiUrl("/api/auth/login"), {
    method: "POST",
    credentials: cred,
    headers: {
      ...headers(true),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ username, password }),
  })
  return r.ok
}

export async function postLogout(): Promise<void> {
  await fetch(apiUrl("/api/auth/logout"), { method: "POST", credentials: cred })
}

export async function fetchStatus(): Promise<{
  httpStatus: number
  data: StatusResponse
}> {
  const r = await fetch(apiUrl("/api/status"), { credentials: cred, headers: headers(true) })
  const d = (await r.json()) as StatusResponse
  if (r.status === 401) {
    return {
      httpStatus: 401,
      data: { ...d, headline: "Unauthorized — sign in again", rcon_ok: false },
    }
  }
  return { httpStatus: r.status, data: d }
}

export async function postChangeMap(map: string): Promise<{
  httpStatus: number
  ok?: boolean
  message?: string
  error?: string
}> {
  const r = await fetch(apiUrl("/api/map"), {
    method: "POST",
    credentials: cred,
    headers: {
      ...headers(true),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ map }),
  })
  const d = (await r.json().catch(() => ({}))) as {
    ok?: boolean
    message?: string
    error?: string
    detail?: string | unknown
  }
  let detailMsg: string | undefined
  if (typeof d.detail === "string") {
    detailMsg = d.detail
  } else if (Array.isArray(d.detail) && d.detail[0] != null) {
    const row = d.detail[0] as { msg?: string }
    if (typeof row.msg === "string") {
      detailMsg = row.msg
    }
  }
  if (r.status === 404 && !d.error) {
    return {
      httpStatus: r.status,
      ok: false,
      error:
        detailMsg ??
        "Control service missing /api/map — rebuild bb_cs2_control image and recreate the container.",
    }
  }
  return {
    httpStatus: r.status,
    ...d,
    ...(detailMsg && !d.error ? { error: detailMsg } : {}),
  }
}

export async function postBots(
  action: "start" | "stop",
): Promise<{
  httpStatus: number
  ok?: boolean
  message?: string
  error?: string
}> {
  const r = await fetch(apiUrl(`/api/bots/${action}`), {
    method: "POST",
    credentials: cred,
    headers: headers(true),
  })
  const d = (await r.json().catch(() => ({}))) as {
    ok?: boolean
    message?: string
    error?: string
  }
  return { httpStatus: r.status, ...d }
}

export async function fetchDemoExtractableFields(): Promise<{
  httpStatus: number
  data: DemoFieldCatalogResponse
}> {
  const r = await fetch(apiUrl("/api/demo-extractable-fields"), {
    credentials: cred,
    headers: headers(true),
  })
  const d = (await r.json().catch(() => ({}))) as DemoFieldCatalogResponse
  return { httpStatus: r.status, data: d }
}

export type DemoFieldCatalogResponse = {
  meta?: {
    extraction?: string | null
    awpy_version?: string | null
    demoparser2_version?: string | null
    disclaimer?: string
  }
  fields?: Array<{
    path: string
    brief_type: string
    group: string
    notes: string
  }>
  error?: string
  detail?: string
}

export async function postDemoParsePreview(args: {
  file?: File | null
  demoUrl?: string
  eventScanMax?: number
}): Promise<{
  httpStatus: number
  data: DemoParsePreviewResponse
}> {
  const fd = new FormData()
  if (args.file) {
    fd.append("file", args.file, args.file.name)
  }
  const url = args.demoUrl?.trim()
  if (url) {
    fd.append("demo_url", url)
  }
  fd.append("event_scan_max", String(args.eventScanMax ?? 80))
  const r = await fetch(apiUrl("/api/demo-parse-preview"), {
    method: "POST",
    credentials: cred,
    body: fd,
  })
  const data = (await r.json().catch(() => ({}))) as DemoParsePreviewResponse
  return { httpStatus: r.status, data }
}

export type DemoParsePreviewMeta = {
  extraction?: string | null
  awpy_version?: string | null
  demoparser2_version?: string | null
  source_filename?: string
  bytes?: number
  sha256?: string
  disclaimer?: string
}

export type DemoParsePreviewDiscovered = {
  header_keys?: string[]
  list_game_events?: string[]
  list_updated_fields?: string[]
  event_columns_from_parse_event?: Record<string, string[] | { error?: string }>
  awpy_events_tables?: Record<string, string[]>
  ticks_columns?: string[]
  rounds_columns?: string[]
  grenades_columns?: string[]
  derived_tables?: Record<string, { columns?: string[]; error?: string }>
}

export type DemoParsePreviewResponse = {
  meta?: DemoParsePreviewMeta
  discovered?: DemoParsePreviewDiscovered
  discovery_rows?: Array<{ group: string; key: string; detail?: string }>
  error?: string
  detail?: string
}

export async function uploadClip(file: File): Promise<{
  httpStatus: number
  ok?: boolean
  saved_as?: string
  bytes?: number
  detail?: string
  vm_clips_path?: string | null
  host?: string
}> {
  const fd = new FormData()
  fd.append("file", file, file.name)
  const r = await fetch(apiUrl("/api/uploads"), {
    method: "POST",
    credentials: cred,
    body: fd,
  })
  const d = (await r.json().catch(() => ({}))) as {
    ok?: boolean
    saved_as?: string
    bytes?: number
    detail?: unknown
    vm_clips_path?: string | null
    host?: string
  }
  return {
    httpStatus: r.status,
    ok: d.ok,
    saved_as: d.saved_as,
    bytes: d.bytes,
    detail: fastApiDetailString(d.detail),
    vm_clips_path: d.vm_clips_path ?? null,
    host: typeof d.host === "string" ? d.host : undefined,
  }
}

export type UploadListItem = {
  name: string
  display_name: string
  bytes: number
  modified_unix: number
  modified_iso: string
  content_type: string
}

export async function fetchUploadsList(): Promise<{
  httpStatus: number
  ok?: boolean
  items?: UploadListItem[]
  vm_clips_path?: string | null
  detail?: string
}> {
  const r = await fetch(apiUrl("/api/uploads"), {
    method: "GET",
    credentials: cred,
    headers: headers(true),
  })
  const d = (await r.json().catch(() => ({}))) as {
    ok?: boolean
    items?: UploadListItem[]
    vm_clips_path?: string | null
    detail?: unknown
  }
  return {
    httpStatus: r.status,
    ok: d.ok,
    items: Array.isArray(d.items) ? d.items : undefined,
    vm_clips_path: d.vm_clips_path ?? null,
    detail: fastApiDetailString(d.detail),
  }
}

/** Same-origin URL for GET download (session cookie sent for logged-in users). */
export function clipDownloadUrl(storageName: string): string {
  const enc = encodeURIComponent(storageName)
  return apiUrl(`api/uploads/download/${enc}`)
}

/** Absolute download URL (for copying — requires session cookie when opened in-browser). */
export function clipUploadAbsoluteDownloadUrl(storageName: string): string {
  const path = clipDownloadUrl(storageName)
  if (typeof window === "undefined") {
    return path
  }
  return new URL(path, window.location.origin).href
}
