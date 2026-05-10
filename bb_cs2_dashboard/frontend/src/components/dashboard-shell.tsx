"use client"

import { useState } from "react"

import { BiobaseSidebar, type DashboardSection } from "@/components/biobase-sidebar"
import { BiobaseSiteHeader } from "@/components/biobase-site-header"
import { ClipsUploadPanel } from "@/components/clips-upload-panel"
import { MapAndPresetsPanel } from "@/components/map-and-presets-panel"
import { MatchServerPanel } from "@/components/match-server-panel"
import { ObservabilitySection } from "@/components/observability-section"
import { OverviewSection } from "@/components/overview-section"
import { PracticeToolsSection } from "@/components/practice-tools-section"
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar"
import { useAuth } from "@/context/auth-context"

function renderSection(section: DashboardSection, onNavigate: (s: DashboardSection) => void) {
  switch (section) {
    case "overview":
      return <OverviewSection onNavigate={onNavigate} />
    case "match_server":
      return (
        <div className="space-y-3">
          <MatchServerPanel />
          <MapAndPresetsPanel />
        </div>
      )
    case "practice_tools":
      return <PracticeToolsSection />
    case "upload":
      return <ClipsUploadPanel />
    case "observability":
      return <ObservabilitySection />
    default: {
      const _exhaustive: never = section
      return _exhaustive
    }
  }
}

export function DashboardShell() {
  const [section, setSection] = useState<DashboardSection>("overview")
  const { me, logout } = useAuth()
  const showSignOut = me?.login_required ?? false

  return (
    <SidebarProvider>
      <BiobaseSidebar
        active={section}
        onNavigate={setSection}
        showSignOut={showSignOut}
        onSignOut={() => void logout()}
      />
      <SidebarInset>
        <BiobaseSiteHeader section={section} />
        <div className="flex flex-1 flex-col gap-3 px-3 py-3 md:gap-4 md:px-5 md:py-4">
          {renderSection(section, setSection)}
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
