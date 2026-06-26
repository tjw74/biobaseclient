---
title: BioBase CS2 Server Installer
category: concepts
tags: [biobase, cs2, server, installer, docker, windows, linux]
sources: [projects/biobase]
summary: >-
  One-click CS2 server installer: Go binary with embedded server files,
  auto-installs Docker Desktop + WSL2 on Windows, auto-resumes after
  restart, generates secure config, builds and starts full container stack.
provenance:
  extracted: 0.95
  inferred: 0.05
  ambiguous: 0.00
created: 2026-06-25T07:00:00Z
updated: 2026-06-25T07:00:00Z
---

# BioBase CS2 Server Installer

One-click installer for the BioBase CS2 server stack. Separate product from the desktop client app — distributed via its own GitHub repo ([tjw74/biobaseserver_cs2](https://github.com/tjw74/biobaseserver_cs2)).

## Design Principle

Zero friction. User downloads one file, runs it, server works. No CLI, no manual configuration, no prerequisite knowledge. The installer handles everything including Docker and WSL2 setup.

## Architecture

The installer is a Go binary cross-compiled from Linux to Windows (`CGO_ENABLED=0 GOOS=windows GOARCH=amd64`). All server source files are embedded inside the binary via Go's `embed.FS` (packed as `server.zip`). The binary is ~3.3 MB.

### What the installer does

1. Extracts server files to `~/BioBase/CS2Server/`
2. Generates `.env` with secure random passwords (RCON + dashboard)
3. Checks for Docker Desktop — downloads and installs if missing
4. If WSL2 not enabled (fresh Docker install), sets a Windows `RunOnce` registry key and triggers restart
5. After restart, auto-launches via RunOnce, starts Docker Desktop, waits for engine
6. Runs `docker compose up -d --build` to build and start all 4 containers
7. Health-checks TCP 27015 (CS2 game port)
8. Displays connection info and generated passwords

### Container stack

| Service | Port | Purpose |
|---------|------|---------|
| `bb_cs2_server` | 27015 | CS2 dedicated server + BiobasePosEmitter + MatchZy |
| `bb_cs2_control` | 8765 | RCON REST API (bot/map control) |
| `bb_cs2_dashboard` | 8780 | Admin UI + desktop client API + live movement feed |
| `bb_cs2_renderer` | — | Demo video rendering (optional, `--profile render`) |

## Distribution

- **Repo**: `tjw74/biobaseserver_cs2` (separate from client app at `tjw74/biobase`)
- **Release**: GitHub Releases, single `.exe` asset
- **Build**: `CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags="-s -w"` from `installer/go-setup/`
- **Installer source**: `installer/go-setup/main.go`

## Windows-specific handling

- **NSIS was rejected**: NSIS-compiled executables trigger Windows Defender false positives (AV quarantine, not just SmartScreen). Native Go PE binaries only get SmartScreen "unknown publisher" warning (clickable).
- **WSL2 restart**: Docker Desktop requires WSL2, which requires a Windows restart on first install. The installer automates this via `RunOnce` registry key + `shutdown /r`.
- **Auto-login for remote testing**: Parsec remote desktop requires Windows auto-login for unattended restart. Configured via `Winlogon` registry keys (AutoAdminLogon, DefaultUserName, DefaultPassword).
- **No prompts**: Zero user input. All config uses sensible defaults. User edits `.env` after install to customize.

## Linux path

On Linux, Docker is typically already installed or installs without restart. The same `install.sh` bash script handles detection, prompts, and compose. No Go binary needed — the script is the installer.

## Future: local training harness

The server installer is a step toward the "BioBase harness" concept: the BioBase desktop app + a local CS2 server running on the same Windows machine. Zero-lag training, offline simulations, local data analysis. The installer is the foundation — a user installs the app and the server, and has a complete self-contained training rig.

## Key decisions

- **Docker is the right abstraction** for packaging the server. 4 services, multiple languages (Python, Go, Node, .NET), complex plugin pipeline — Docker makes it portable and reproducible.
- **Separate repo from client**: most users only need the app. The server is a distinct offering for advanced users, teams, and BioBase's own infrastructure.
- **No code signing yet**: unsigned `.exe` triggers SmartScreen warning. Code signing requires a paid certificate (~$200-400/year). Acceptable for now; will be addressed when the product matures.

## Related

- [[biobase-product-roadmap]] — Phase 3: Server Offering
- [[biobase-cs2-admin-dashboard]] — Admin dashboard served by the server stack
- [[biobase]] — project hub
