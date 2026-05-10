const cred: RequestCredentials = "include"

function headers(json = false): HeadersInit {
  const h: Record<string, string> = {}
  if (json) {
    h.Accept = "application/json"
  }
  return h
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
  const r = await fetch("/api/auth/me", { credentials: cred })
  return (await r.json()) as { authenticated: boolean; login_required: boolean }
}

export async function postLogin(username: string, password: string): Promise<boolean> {
  const r = await fetch("/api/auth/login", {
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
  await fetch("/api/auth/logout", { method: "POST", credentials: cred })
}

export async function fetchStatus(): Promise<{
  httpStatus: number
  data: StatusResponse
}> {
  const r = await fetch("/api/status", { credentials: cred, headers: headers(true) })
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
  const r = await fetch("/api/map", {
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
  const r = await fetch(`/api/bots/${action}`, {
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

export async function uploadClip(file: File): Promise<{
  httpStatus: number
  ok?: boolean
  saved_as?: string
  bytes?: number
  detail?: string
}> {
  const fd = new FormData()
  fd.append("file", file, file.name)
  const r = await fetch("/api/uploads", {
    method: "POST",
    credentials: cred,
    body: fd,
  })
  const d = (await r.json().catch(() => ({}))) as {
    ok?: boolean
    saved_as?: string
    bytes?: number
    detail?: string
  }
  return { httpStatus: r.status, ...d }
}
