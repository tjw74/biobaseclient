# Biobase admin: `biobase.local`

## Desired outcome

Anyone maintaining a Biobase deployment should open **`http://biobase.local`** (or HTTPS, once configured) in a browser **on the same local network as the machine running Biobase** and land on a **single place** to manage the app: monitoring, logs, game control, and any future admin surfaces.

**Name resolution** uses **mDNS** (e.g. via Avahi on the host) so `biobase.local` is advertised on the LAN **without** requiring router DNS entries or static IP bookmarks for that name.

**Routing** to individual tools (Grafana, Loki, Prometheus, game bot control, and others) is done with a **reverse proxy** in front of the existing containers, with paths or subpaths so the stack stays service-oriented in Docker but **presents** as one site under `biobase.local`.

Grafana and the rest of the **observability** stack continue to do what they do today; the **CS2 bot control** service remains a **dedicated, game-only** control layer—only **discovery and navigation** are unified at `biobase.local`.

**Out of scope for `.local`:** remote access from another network. That requires VPN, tunnel, or similar—separate from this LAN-first admin experience.

## End result (checklist in plain language)

- On the Biobase host: mDNS makes **`biobase.local`** resolve for clients on the same LAN.
- On the Biobase host: a small **entry page** (or redirects) at `biobase.local` that links or proxies to all admin tools the operator needs.
- **One mental model:** “Open Biobase” = open **`biobase.local`**, then jump to Grafana, logs, or game control as needed.

This document is the product intent; implementation (Avahi, proxy, paths) is tracked in the repo and deployment runbooks as they are added.
