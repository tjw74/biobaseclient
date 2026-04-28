---
title: >-
  Biobase Hub Routing
category: concepts
tags: [cs2, nginx, grafana, docker, networking]
sources: [projects/biobase]
summary: >-
  nginx reverse proxy at port 8880 routes /bb/, /loki/, /cs2/, /data/ to
  services; GF_SERVER_ROOT_URL must match for Grafana redirects to work.
provenance:
  extracted: 0.88
  inferred: 0.10
  ambiguous: 0.02
created: 2026-04-28T00:00:00Z
updated: 2026-04-28T00:00:00Z
---

# Biobase Hub Routing

`bb_biobase_local` is an nginx container that serves as the single operator entry point. Default port: **8880** (override with `BIOBASE_LOCAL_PORT`).

## Path Routing

| Path | Destination | Notes |
|---|---|---|
| `/bb/` | Grafana | Proxy pass; prefix stripped |
| `/loki/` | Loki | Proxy pass |
| `/cs2/` | `bb_cs2_control` (FastAPI :8765) | Prefix stripped |
| `/data/` | `bb_data_collection` (FastAPI :8080) | Prefix stripped |
| `/` | Static hub HTML | `bb_biobase_local/html/index.html` |

## Grafana Root URL Requirement

Grafana must have `GF_SERVER_ROOT_URL` set to `http://<host-IP>:8880/bb/`. Without this, Grafana redirects and cookies break because Grafana generates absolute URLs using its internal root. ^[extracted]

## Hub UI

`index.html` provides a dark-mode operator page with:
- Start / Stop bot game buttons (calls `POST /cs2/api/bots/start` and `/stop`, also triggers `hub/start` and `hub/stop` on the data collection service simultaneously)
- Links to Grafana (`/bb/`), Loki (`/loki/`), and Prometheus (host port 19090)

`X-Api-Key` header is checked by `bb_cs2_control` if `BB_CS2_CONTROL_TOKEN` is set.

## mDNS / Local Discovery

`bb_biobase_local` ships a `verify.sh` and an Avahi-based mDNS install script to publish `biobase.local` on the LAN. Note: the mDNS name resolves to port 80, not port 8880 — the hub port must still be specified explicitly unless a port-80 proxy is set up separately.

## Remote Access

Not covered by the project. Use VPN or a tunnel; terminate TLS at something you control.

## Related

- [[biobase]] — project overview
- [[biobase-session-ingest]] — what the hub buttons trigger on the data service
