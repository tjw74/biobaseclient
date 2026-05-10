"use client"

import { useState } from "react"

import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { useAuth } from "@/context/auth-context"
import { uploadClip } from "@/lib/dashboard-api"
import { toast } from "sonner"

export function ClipsUploadPanel() {
  const [file, setFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const { refresh } = useAuth()

  async function onUpload() {
    if (!file) {
      return
    }
    setBusy(true)
    try {
      const d = await uploadClip(file)
      if (d.httpStatus === 401) {
        await refresh()
        toast.error("Session expired — sign in again")
        return
      }
      if (d.ok && d.saved_as) {
        toast.success(`Saved: ${d.saved_as} (${d.bytes ?? 0} B)`)
        setFile(null)
      } else {
        toast.error(d.detail ?? "Upload failed")
      }
    } catch {
      toast.error("Upload failed")
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card size="sm" className="ring-foreground/10">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">Clips</CardTitle>
        <CardDescription className="text-xs leading-snug">
          Upload to server volume (UUID prefix + original name).
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <Input
          type="file"
          className="h-8 max-w-md cursor-pointer text-sm file:mr-2 file:text-xs"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
        />
        <Button type="button" size="sm" className="h-7 w-fit shrink-0" disabled={busy || !file} onClick={() => void onUpload()}>
          Upload
        </Button>
      </CardContent>
      <CardFooter className="text-muted-foreground border-t py-2 text-[0.65rem] leading-snug">
        Production: bind host path to <code className="text-muted-foreground">/data/clips</code>.
      </CardFooter>
    </Card>
  )
}
