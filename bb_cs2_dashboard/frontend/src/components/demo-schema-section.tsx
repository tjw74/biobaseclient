"use client"

import { useEffect, useMemo, useState } from "react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  fetchDemoExtractableFields,
  postDemoParsePreview,
  type DemoFieldCatalogResponse,
  type DemoParsePreviewResponse,
} from "@/lib/dashboard-api"
import { Loader2Icon } from "lucide-react"

function DiscoveredFromDemoPanel({ authBlocked }: { authBlocked: boolean }) {
  const [file, setFile] = useState<File | null>(null)
  const [demoUrl, setDemoUrl] = useState("")
  const [eventScanMax, setEventScanMax] = useState(80)
  const [busy, setBusy] = useState(false)
  const [preview, setPreview] = useState<DemoParsePreviewResponse | null>(null)
  const [previewStatus, setPreviewStatus] = useState(0)
  const [filter, setFilter] = useState("")

  const rows = preview?.discovery_rows ?? []
  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase()
    if (!q) {
      return rows
    }
    return rows.filter((r) => {
      return (
        r.group.toLowerCase().includes(q) ||
        r.key.toLowerCase().includes(q) ||
        (r.detail ?? "").toLowerCase().includes(q)
      )
    })
  }, [rows, filter])

  async function runParse() {
    const hasFile = Boolean(file)
    const hasUrl = demoUrl.trim().length > 0
    if (!hasFile && !hasUrl) {
      setPreview({ error: "missing_input", detail: "Choose a .dem file or enter demo_url." })
      setPreviewStatus(400)
      return
    }
    if (hasFile && hasUrl) {
      setPreview({ error: "too_many_inputs", detail: "Use either file upload or demo_url, not both." })
      setPreviewStatus(400)
      return
    }
    setBusy(true)
    setPreview(null)
    setPreviewStatus(0)
    try {
      const { httpStatus, data } = await postDemoParsePreview({
        file: hasFile ? file : undefined,
        demoUrl: hasUrl ? demoUrl : undefined,
        eventScanMax,
      })
      setPreview(data)
      setPreviewStatus(httpStatus)
    } finally {
      setBusy(false)
    }
  }

  if (authBlocked) {
    return null
  }

  const m = preview?.meta

  return (
    <Card size="sm" className="bg-card/80 ring-foreground/10">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">Discovered from demo</CardTitle>
        <p className="text-muted-foreground text-xs leading-snug">
          Upload a <code className="text-foreground rounded bg-muted px-1 py-0.5 text-[0.7rem]">.dem</code> —
          the server parses it with awpy and lists columns/keys actually returned (deep{" "}
          <code className="text-foreground rounded bg-muted px-1 py-0.5 text-[0.7rem]">parse_event</code> scan capped
          by <span className="text-foreground font-mono">event_scan_max</span>). Keys vary by demo and build;
          compare with the static catalog below.
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor="demo-file" className="text-xs">
              Demo file (.dem)
            </Label>
            <Input
              id="demo-file"
              type="file"
              accept=".dem,application/octet-stream"
              className="cursor-pointer text-xs"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
              disabled={busy}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="demo-url" className="text-xs">
              demo_url (dev — requires server env)
            </Label>
            <Input
              id="demo-url"
              placeholder="https://… (BB_DEMO_PARSE_ALLOW_URL_FETCH=1)"
              value={demoUrl}
              onChange={(e) => setDemoUrl(e.target.value)}
              className="text-xs"
              disabled={busy}
              autoComplete="off"
            />
          </div>
        </div>
        <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
          <div className="space-y-1">
            <Label htmlFor="event-scan-max" className="text-xs">
              event_scan_max
            </Label>
            <Input
              id="event-scan-max"
              type="number"
              min={0}
              max={200}
              value={eventScanMax}
              onChange={(e) => setEventScanMax(Number(e.target.value) || 0)}
              className="w-full sm:w-28 text-xs"
              disabled={busy}
            />
          </div>
          <Button
            type="button"
            variant="secondary"
            disabled={busy}
            onClick={() => void runParse()}
            className="inline-flex w-fit items-center gap-2"
          >
            {busy ? (
              <>
                <Loader2Icon className="size-4 animate-spin" />
                Parsing…
              </>
            ) : (
              "Parse demo"
            )}
          </Button>
        </div>

        {previewStatus === 401 ? (
          <p className="text-muted-foreground text-xs">Unauthorized — sign in again.</p>
        ) : null}

        {preview?.error ? (
          <p className="text-destructive text-xs">
            {preview.error}
            {preview.detail ? ` — ${preview.detail}` : ""}
            {previewStatus ? ` (HTTP ${previewStatus})` : ""}
          </p>
        ) : null}

        {m && !preview?.error ? (
          <div className="border-border bg-muted/30 space-y-2 rounded-md border p-3 text-xs">
            <p className="text-foreground font-medium">Last parse</p>
            <dl className="grid gap-1 sm:grid-cols-2">
              <div>
                <dt className="text-muted-foreground">File</dt>
                <dd className="font-mono break-all">{m.source_filename ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">Bytes</dt>
                <dd>{m.bytes ?? "—"}</dd>
              </div>
              <div className="sm:col-span-2">
                <dt className="text-muted-foreground">SHA-256</dt>
                <dd className="font-mono break-all">{m.sha256 ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">awpy</dt>
                <dd className="font-mono">{m.awpy_version ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">demoparser2</dt>
                <dd className="font-mono">{m.demoparser2_version ?? "—"}</dd>
              </div>
            </dl>
            {m.disclaimer ? (
              <p className="text-muted-foreground leading-snug">{m.disclaimer}</p>
            ) : null}
          </div>
        ) : null}

        {rows.length > 0 ? (
          <>
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <p className="text-muted-foreground text-xs">
                {filtered.length} of {rows.length} rows
                {filter.trim() ? " (filtered)" : ""}
              </p>
              <Input
                placeholder="Filter group / key / detail…"
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                className="sm:max-w-sm text-xs"
                aria-label="Filter discovered rows"
              />
            </div>
            <div className="max-h-[min(40vh,24rem)] overflow-auto rounded-lg border border-border">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead className="w-[22%]">Group</TableHead>
                    <TableHead className="w-[38%]">Key</TableHead>
                    <TableHead>Detail</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map((r, i) => (
                    <TableRow key={`${r.group}:${r.key}:${i}`}>
                      <TableCell className="text-xs">{r.group}</TableCell>
                      <TableCell className="font-mono text-xs break-all">{r.key}</TableCell>
                      <TableCell className="text-muted-foreground text-xs">{r.detail ?? ""}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </>
        ) : null}
      </CardContent>
    </Card>
  )
}

export function DemoSchemaSection() {
  const [catalogLoading, setCatalogLoading] = useState(true)
  const [catalog, setCatalog] = useState<DemoFieldCatalogResponse | null>(null)
  const [catalogHttpStatus, setCatalogHttpStatus] = useState(0)
  const [filter, setFilter] = useState("")

  useEffect(() => {
    let cancelled = false
    void (async () => {
      setCatalogLoading(true)
      const { httpStatus: st, data } = await fetchDemoExtractableFields()
      if (!cancelled) {
        setCatalogHttpStatus(st)
        setCatalog(data)
        setCatalogLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  const rows = catalog?.fields ?? []
  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase()
    if (!q) {
      return rows
    }
    return rows.filter((r) => {
      return (
        r.path.toLowerCase().includes(q) ||
        r.group.toLowerCase().includes(q) ||
        r.brief_type.toLowerCase().includes(q) ||
        r.notes.toLowerCase().includes(q)
      )
    })
  }, [rows, filter])

  const authBlocked = catalogHttpStatus === 401

  if (catalogLoading) {
    return (
      <div className="space-y-4">
        <DiscoveredFromDemoPanel authBlocked={false} />
        <div
          className="text-muted-foreground flex items-center gap-2 py-8"
          aria-busy="true"
          aria-label="Loading demo field catalog"
        >
          <Loader2Icon className="size-5 animate-spin" />
          <span className="text-sm">Loading demo field catalog…</span>
        </div>
      </div>
    )
  }

  if (authBlocked) {
    return (
      <div className="space-y-4">
        <DiscoveredFromDemoPanel authBlocked />
        <p className="text-muted-foreground text-sm">
          Session expired — sign out and sign in again to load the catalog.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <DiscoveredFromDemoPanel authBlocked={false} />

      {catalog?.error || !catalog?.fields?.length ? (
        <Card size="sm" className="bg-card/80 ring-foreground/10">
          <CardHeader>
            <CardTitle className="text-sm">Demo extractable fields — unavailable</CardTitle>
            <p className="text-muted-foreground text-xs leading-snug">
              The catalog requires awpy in the dashboard image. Build with{" "}
              <code className="text-foreground rounded bg-muted px-1 py-0.5 text-[0.7rem]">
                bb_cs2_dashboard/requirements.txt
              </code>{" "}
              (includes awpy). Response: {catalog?.error ?? "empty"}
              {catalog?.detail ? ` — ${catalog.detail}` : ""}
            </p>
          </CardHeader>
          <CardContent className="text-muted-foreground space-y-2 text-xs leading-relaxed">
            <p className="text-foreground font-medium">Verification checklist</p>
            <ol className="list-decimal space-y-1 pl-4">
              <li>Rebuild the dashboard image after updating Python requirements.</li>
              <li>Confirm the container imports awpy (no slimmed runtime stripping deps).</li>
              <li>
                Use &quot;Discovered from demo&quot; above for per-demo columns (
                <code className="text-foreground rounded bg-muted px-1 py-0.5 text-[0.7rem]">
                  list_game_events
                </code>
                , parse_event).
              </li>
            </ol>
          </CardContent>
        </Card>
      ) : (
        <>
          <Card size="sm" className="bg-card/80 ring-foreground/10">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Static catalog (awpy stack)</CardTitle>
              <p className="text-muted-foreground text-xs leading-snug">{catalog.meta?.disclaimer}</p>
              <dl className="text-foreground mt-2 grid gap-1 text-xs sm:grid-cols-2">
                <div>
                  <dt className="text-muted-foreground">Awpy</dt>
                  <dd className="font-mono">{catalog.meta?.awpy_version ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">demoparser2</dt>
                  <dd className="font-mono">{catalog.meta?.demoparser2_version ?? "—"}</dd>
                </div>
                <div className="sm:col-span-2">
                  <dt className="text-muted-foreground">Wiring</dt>
                  <dd>{catalog.meta?.extraction}</dd>
                </div>
              </dl>
            </CardHeader>
          </Card>

          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-muted-foreground text-xs">
              {filtered.length} of {rows.length} paths
              {filter.trim() ? " (filtered)" : ""}
            </p>
            <Input
              placeholder="Filter by path, group, type, notes…"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              className="sm:max-w-sm"
              aria-label="Filter fields"
            />
          </div>

          <div className="max-h-[min(60vh,32rem)] overflow-auto rounded-lg border border-border">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead className="w-[40%]">Path</TableHead>
                  <TableHead className="w-[12%]">Type</TableHead>
                  <TableHead className="w-[18%]">Group</TableHead>
                  <TableHead>Notes</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((r) => (
                  <TableRow key={r.path}>
                    <TableCell className="font-mono text-xs break-all">{r.path}</TableCell>
                    <TableCell className="text-xs">{r.brief_type}</TableCell>
                    <TableCell className="text-xs">{r.group}</TableCell>
                    <TableCell className="text-muted-foreground text-xs">{r.notes}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </>
      )}
    </div>
  )
}
