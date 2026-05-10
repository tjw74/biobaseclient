"use client"

import { useState } from "react"

import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useAuth } from "@/context/auth-context"

export function LoginPage() {
  const { login } = useAuth()
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setErr(null)
    const ok = await login(username.trim(), password)
    setBusy(false)
    if (!ok) {
      setErr("Invalid username or password.")
    }
  }

  return (
    <div className="bg-background flex min-h-svh items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>BioBase · CS2 admin</CardTitle>
          <CardDescription>
            Shared team login. Use the operator name and password configured on the server (same style
            as a simple Grafana login).
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={(e) => void onSubmit(e)} className="grid gap-4">
            <div className="grid gap-2">
              <Label htmlFor="dash-user">Username</Label>
              <Input
                id="dash-user"
                type="text"
                name="username"
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                disabled={busy}
              />
              <p className="text-muted-foreground text-[0.7rem] leading-snug">
                If the server sets no fixed username, any username is accepted; the password is still
                required.
              </p>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="dash-pass">Password</Label>
              <Input
                id="dash-pass"
                type="password"
                name="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={busy}
              />
              <p className="text-muted-foreground text-[0.7rem] leading-snug">
                This is the shared dashboard secret (<code className="text-muted-foreground">BB_CS2_DASHBOARD_TOKEN</code>
                ).
              </p>
            </div>
            {err ? <p className="text-destructive text-sm">{err}</p> : null}
            <Button type="submit" disabled={busy}>
              {busy ? "Signing in…" : "Sign in"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
