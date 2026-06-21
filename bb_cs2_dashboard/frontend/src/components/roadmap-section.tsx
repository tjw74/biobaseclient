"use client"

import { useEffect, useRef, useState } from "react"
import {
  ArrowUpCircle,
  HeartPulse,
  Layers,
  Monitor,
  Server,
  Smartphone,
  Sparkles,
} from "lucide-react"

interface Chapter {
  id: string
  phase: string
  title: string
  focus: string
  priority: "now" | "next" | "future"
  features: number
  status: string
  icon: typeof Monitor
  body: string[]
}

const chapters: Chapter[] = [
  {
    id: "vision",
    phase: "Phase 0",
    title: "The Vision",
    focus: "Platform",
    priority: "now",
    features: 2,
    status: "Active",
    icon: Sparkles,
    body: [
      "BioBase is a CS2 performance platform with two pillars: the BioBase Client App that players install on their machine, and the BioBase CS2 Server that powers the data pipeline.",
      "Players install the client to get deep in-game analytics — movement quality, shooting precision, decision-making patterns — all tracked in real time. The platform also integrates with bio-sensor hardware so players can see their physiological state synced to the game clock.",
      "The client app is the primary experience. The companion web app is a phone-side mirror accessed via a secret QR code — same data, optimized for glancing at while you play.",
    ],
  },
  {
    id: "client",
    phase: "Phase 1",
    title: "BioBase Client App",
    focus: "Client",
    priority: "now",
    features: 6,
    status: "In Progress",
    icon: Monitor,
    body: [
      "The client is the player’s home base. It opens and immediately makes sense — no digging through menus, no learning curve. Every control and piece of information lives where the user is already looking.",
      "Core features: one-click Play on Biobase to launch CS2 and connect to the server. Live movement stats updating in real time. Server status showing who’s online. Game overlay rendering stats directly on the CS2 screen.",
      "The design principle is extreme friction reduction. Updates install automatically with a single click on the version number. The companion QR generates instantly. Player tracking auto-detects from Steam. Every interaction that can be eliminated, is eliminated.",
    ],
  },
  {
    id: "companion",
    phase: "Phase 1",
    title: "Phone Companion",
    focus: "Companion",
    priority: "now",
    features: 4,
    status: "In Progress",
    icon: Smartphone,
    body: [
      "Most players can’t see the BioBase app while playing — their screen is the game. The companion solves this: scan the QR from the client, and your phone becomes a live stats display you prop up next to your monitor.",
      "The companion mirrors the client’s UI with two modes. Full mode (tablets) is an exact replica of the client’s layout. Compact mode (phones, default) is a streamlined single-column view optimized for glancing.",
      "Both modes share the same design language and component library. Responsive CSS handles the adaptation — one codebase, not two apps that drift apart. The companion connects via a secret, time-limited link unique to each client instance.",
    ],
  },
  {
    id: "dashboards",
    phase: "Phase 2",
    title: "Performance Dashboards",
    focus: "Data Views",
    priority: "next",
    features: 8,
    status: "Planned",
    icon: Layers,
    body: [
      "This is the core value of BioBase — what makes it worth installing. Players want to improve specific aspects of their game, and each aspect gets its own purpose-built dashboard.",
      "Movement dashboard: speed patterns, counter-strafe timing, path efficiency, bhop consistency. Shooting dashboard: accuracy breakdowns, spray control visualization, crosshair placement tracking, peek timing analysis.",
      "Players select up to 3 focus categories and BioBase builds a combined dashboard on demand. Every player sees exactly the data that matters to their improvement path, nothing more.",
    ],
  },
  {
    id: "bio",
    phase: "Phase 2",
    title: "Bio-Sensor Integration",
    focus: "Bio Input",
    priority: "next",
    features: 5,
    status: "Planned",
    icon: HeartPulse,
    body: [
      "What makes BioBase unique: physiological data synced to the game clock. When a player clutches a 1v3, we can show their heart rate spiking, their grip pressure changing, their micro-tremor patterns — all timestamped to the exact tick.",
      "The bio-sensor device pairs with the client app over USB or Bluetooth. Raw sensor streams are captured at high frequency, downsampled to match the game’s tick rate, and overlaid on the performance dashboards.",
      "During live play, the companion app shows bio metrics alongside game stats in real time. During replay review, players scrub through their demo and see exactly how their body responded to each engagement. This is the data no other platform has.",
    ],
  },
  {
    id: "updates",
    phase: "Phase 1",
    title: "Auto-Update Pipeline",
    focus: "Infrastructure",
    priority: "now",
    features: 3,
    status: "Shipped",
    icon: ArrowUpCircle,
    body: [
      "Central control of updates is built in from day one. The client checks for updates on launch and when the user clicks the version number. Downloads happen in the background, and a single restart applies the update. No browser, no manual download, no installer wizard.",
      "The update feed is a simple YAML manifest served from the BioBase server. electron-updater handles differential downloads, integrity verification, and atomic installs. The Caddy reverse proxy ensures the feed is always cache-busted.",
      "When the server offering launches, the same pipeline extends to it — operators get notified of available updates and can apply them with one command. Every BioBase component is always up to date, always in sync.",
    ],
  },
  {
    id: "server",
    phase: "Phase 3",
    title: "BioBase CS2 Server",
    focus: "Server",
    priority: "future",
    features: 7,
    status: "Roadmap",
    icon: Server,
    body: [
      "Today the CS2 server is internal — we run it, we manage it, players connect to it. But some players and teams want to run their own BioBase-powered server with the full data pipeline.",
      "The packaged server offering will include: the CS2 dedicated server with BioBase instrumentation, the dashboard for server operators, the data pipeline that feeds client apps, and the movement/shooting analysis backend.",
      "This is a future phase. The server architecture is already built and running — it’s a matter of packaging it for self-hosting, building an onboarding flow, and ensuring the auto-update pipeline works for server operators the same way it works for client users.",
    ],
  },
]

const priorityStyle = {
  now: { label: "Active", dot: "bg-emerald-400", badge: "bg-emerald-500/15 text-emerald-400 border-emerald-500/25" },
  next: { label: "Up Next", dot: "bg-sky-400", badge: "bg-sky-500/15 text-sky-400 border-sky-500/25" },
  future: { label: "Future", dot: "bg-violet-400", badge: "bg-violet-500/15 text-violet-400 border-violet-500/25" },
} as const

function statusDot(s: string) {
  return s === "Shipped" ? "bg-emerald-400" : s === "In Progress" ? "bg-amber-400" : s === "Planned" ? "bg-sky-400" : "bg-violet-400/60"
}

function statusColor(s: string) {
  return s === "Shipped" ? "text-emerald-400" : s === "In Progress" ? "text-amber-400" : s === "Planned" ? "text-sky-400" : "text-violet-400"
}

function getScrollParent(el: HTMLElement): HTMLElement | null {
  let p = el.parentElement
  while (p) {
    const s = getComputedStyle(p).overflowY
    if (s === "auto" || s === "scroll") return p
    p = p.parentElement
  }
  return null
}

export function RoadmapSection() {
  const [activeIndex, setActiveIndex] = useState(0)
  const refs = useRef<(HTMLDivElement | null)[]>([])
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const el = rootRef.current
    if (!el) return
    const scrollRoot = getScrollParent(el)

    const observer = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (!e.isIntersecting) continue
          const i = refs.current.indexOf(e.target as HTMLDivElement)
          if (i >= 0) setActiveIndex(i)
        }
      },
      { root: scrollRoot, rootMargin: "-5% 0px -65% 0px", threshold: 0 },
    )

    for (const r of refs.current) if (r) observer.observe(r)
    return () => observer.disconnect()
  }, [])

  function jumpTo(i: number) {
    const el = rootRef.current
    if (!el) return
    const sp = getScrollParent(el)
    const target = refs.current[i]
    if (!target || !sp) return
    sp.scrollTo({
      top: sp.scrollTop + target.getBoundingClientRect().top - sp.getBoundingClientRect().top,
      behavior: "smooth",
    })
  }

  const ch = chapters[activeIndex]
  const pm = priorityStyle[ch.priority]
  const Icon = ch.icon

  return (
    <div ref={rootRef}>
      {/* Hero */}
      <div className="border-b border-border/40 px-5 pb-5 pt-4 md:px-8 md:pb-6 md:pt-5">
        <p className="text-[11px] font-semibold uppercase tracking-[0.15em] text-primary">
          BioBase Live
        </p>
        <h1 className="mt-1 text-xl font-bold tracking-tight md:text-2xl">Product Roadmap</h1>
        <p className="mt-1.5 max-w-lg text-[13px] leading-relaxed text-muted-foreground">
          From CS2 performance client to full analytics platform &mdash; movement, shooting,
          bio-sensors, and self-hosted servers.
        </p>
        <div className="mt-3 flex flex-wrap gap-1.5">
          {(["now", "next", "future"] as const).map((p) => {
            const m = priorityStyle[p]
            const n = chapters.filter((c) => c.priority === p).length
            return (
              <span
                key={p}
                className={`inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-[10px] font-semibold ${m.badge}`}
              >
                <span className={`size-1.5 rounded-full ${m.dot}`} />
                {m.label} &middot; {n}
              </span>
            )
          })}
        </div>
      </div>

      {/* Two-column: chapters scroll, stats stick */}
      <div className="flex">
        {/* Chapters */}
        <div className="min-w-0 flex-1">
          {chapters.map((c, i) => {
            const isActive = i === activeIndex
            const CI = c.icon
            return (
              <div
                key={c.id}
                ref={(el) => {
                  refs.current[i] = el
                }}
                className={`border-b border-border/20 px-5 py-6 transition-colors duration-300 md:px-8 md:py-8 ${isActive ? "bg-card/50" : ""}`}
              >
                <div className="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-[0.12em]">
                  <span className="text-muted-foreground">{c.phase}</span>
                  <span className="text-border">&middot;</span>
                  <span className={statusColor(c.status)}>{c.status}</span>
                </div>

                <div className="mt-1.5 flex items-center gap-2">
                  <CI
                    className={`size-4 shrink-0 transition-colors duration-300 ${isActive ? "text-primary" : "text-muted-foreground/40"}`}
                  />
                  <h2
                    className={`text-base font-bold tracking-tight transition-colors duration-300 md:text-lg ${isActive ? "text-foreground" : "text-muted-foreground/60"}`}
                  >
                    {c.title}
                  </h2>
                </div>

                <div className="mt-3 max-w-xl space-y-2.5">
                  {c.body.map((para, j) => (
                    <p
                      key={j}
                      className={`text-[13px] leading-[1.65] transition-colors duration-500 ${isActive ? "text-foreground/80" : "text-muted-foreground/35"}`}
                    >
                      {para}
                    </p>
                  ))}
                </div>

                <div className="mt-3 flex items-center gap-2 text-[10px]">
                  <span className="rounded bg-muted/60 px-1.5 py-0.5 font-medium text-muted-foreground">
                    {c.features} features
                  </span>
                  <span className="rounded bg-muted/60 px-1.5 py-0.5 font-medium text-muted-foreground">
                    {c.focus}
                  </span>
                </div>
              </div>
            )
          })}
          <div className="h-[50vh]" />
        </div>

        {/* Sticky stats panel */}
        <div className="hidden w-56 shrink-0 border-l border-border/40 lg:block xl:w-64">
          <div className="sticky top-0 max-h-screen overflow-y-auto p-4">
            {/* Current chapter card */}
            <div className="rounded-lg border border-border/50 bg-card/60 p-3">
              <div className="flex items-center gap-2.5">
                <div className="flex size-8 items-center justify-center rounded-md bg-primary/10">
                  <Icon className="size-4 text-primary" />
                </div>
                <div className="min-w-0">
                  <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                    {ch.phase}
                  </p>
                  <p className="truncate text-sm font-bold">{ch.title}</p>
                </div>
              </div>

              <div className="mt-3 grid grid-cols-2 gap-1.5">
                <div className="rounded-md bg-muted/30 px-2.5 py-1.5">
                  <p className="text-base font-bold tabular-nums">{ch.features}</p>
                  <p className="text-[9px] text-muted-foreground">Features</p>
                </div>
                <div className="rounded-md bg-muted/30 px-2.5 py-1.5">
                  <p className="truncate text-sm font-bold">{ch.focus}</p>
                  <p className="text-[9px] text-muted-foreground">Focus</p>
                </div>
              </div>

              <div className="mt-2 flex items-center justify-between rounded-md bg-muted/30 px-2.5 py-1.5">
                <div>
                  <p className="text-xs font-semibold">{ch.status}</p>
                  <p className="text-[9px] text-muted-foreground">Status</p>
                </div>
                <div
                  className={`size-2 rounded-full ${statusDot(ch.status)} ${ch.status === "In Progress" ? "animate-pulse" : ""}`}
                />
              </div>

              <div className="mt-2">
                <span
                  className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold ${pm.badge}`}
                >
                  {pm.label}
                </span>
              </div>
            </div>

            {/* Chapter navigation */}
            <div className="mt-4">
              <p className="mb-1.5 text-[9px] font-semibold uppercase tracking-wider text-muted-foreground">
                Chapters
              </p>
              <div className="space-y-px">
                {chapters.map((c, i) => (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => jumpTo(i)}
                    className={`flex w-full items-center gap-2 rounded-md px-2 py-1 text-left text-[11px] transition-colors ${
                      i === activeIndex
                        ? "bg-primary/10 font-semibold text-primary"
                        : "text-muted-foreground hover:bg-muted/40 hover:text-foreground"
                    }`}
                  >
                    <span
                      className={`size-1.5 shrink-0 rounded-full ${i === activeIndex ? "bg-primary" : statusDot(c.status)}`}
                    />
                    <span className="truncate">{c.title}</span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Mobile floating pill */}
      <div className="pointer-events-none fixed inset-x-0 bottom-4 z-20 flex justify-center lg:hidden">
        <div className="pointer-events-auto rounded-full border border-border/50 bg-background/90 px-3.5 py-1.5 shadow-lg backdrop-blur-sm">
          <p className="text-[11px] font-semibold">
            <span className="text-primary">{ch.phase}</span>
            <span className="mx-1 text-muted-foreground/40">&middot;</span>
            <span>{ch.title}</span>
          </p>
        </div>
      </div>
    </div>
  )
}
