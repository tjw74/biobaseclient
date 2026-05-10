"use client"

import type { DashboardSection } from "@/components/biobase-sidebar"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

type OverviewSectionProps = {
  onNavigate: (section: DashboardSection) => void
}

const overviewNavPillClass =
  "rounded-full border-border bg-muted/25 text-foreground shadow-none hover:border-primary hover:bg-primary hover:text-primary-foreground"

export function OverviewSection({ onNavigate }: OverviewSectionProps) {
  return (
    <Card size="sm" className="bg-card/80 ring-foreground/10">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">BioBase CS2</CardTitle>
        <p className="text-muted-foreground text-xs leading-snug">
          Bot matches, server status, clip upload, and Grafana when configured.
        </p>
      </CardHeader>
      <CardContent className="flex flex-wrap gap-1.5 pt-0">
        <Button
          type="button"
          variant="outline"
          size="sm"
          className={overviewNavPillClass}
          onClick={() => onNavigate("match_server")}
        >
          Match & server
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className={overviewNavPillClass}
          onClick={() => onNavigate("practice_tools")}
        >
          Practice
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className={overviewNavPillClass}
          onClick={() => onNavigate("upload")}
        >
          Upload
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className={overviewNavPillClass}
          onClick={() => onNavigate("observability")}
        >
          Observability
        </Button>
      </CardContent>
    </Card>
  )
}
