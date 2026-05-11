---
title: CS2 admin dashboard & clips uploads
category: concepts
tags: [cs2, docker, clips, nfs, clarioncore]
sources: [projects/biobase]
summary: >-
  FastAPI + Vite admin UI for CS2 ops (status, map, bots, file uploads). Lives under URL prefix
  /admin; clips land on the ClarionCore VM at BB_CLIPS_HOST_DIR (default /mnt/backups/biobase/clips)
  via Docker bind to container /data/clips.
provenance:
  extracted: 0.9
  inferred: 0.1
  ambiguous: 0.0
created: 2026-05-11T21:20:00Z
updated: 2026-05-11T21:20:00Z
---

# CS2 admin dashboard & clips uploads

**Compose stack:** `bb_cs2_server/docker-compose.yml` — services `bb_cs2_server`, `bb_cs2_control`, **`bb_cs2_dashboard`** (image `bb-cs2-dashboard:local`, port **8780**). Checkout path on ClarionCore: `/home/clearmined/code/prod/biobase/bb_cs2_server`.

**UI / API prefix:** Dashboard and API are mounted under **`/admin`** by default (`BB_DASHBOARD_ROOT_PATH`, Vite build arg `VITE_DASHBOARD_BASE=/admin/`). Browser: `http://<host>:8780/admin/`. Public HTTPS example: Caddy forwards **`/admin*`** to the dashboard container (do not strip the prefix).

**Auth:** `BB_CS2_DASHBOARD_TOKEN` (shared password + cookie). Uploads and other APIs require session or **`X-Dashboard-Key`** / Bearer same token.

## Clips uploads

- **Endpoint:** `POST /admin/api/uploads` (multipart `file`; responds with `saved_as`, `bytes`, optional `vm_clips_path`, `host` hostname).
- **In-container path:** `BB_CLIPS_UPLOAD_DIR` default **`/data/clips`**.
- **VM path:** `BB_CLIPS_HOST_DIR` in **`bb_cs2_server/.env`** (gitignored; template `.env.example`). Default **`/mnt/backups/biobase/clips`**. Compose passes **`BB_CLIPS_VM_PATH`** (same as host dir) for UI toasts.

**NFS caveat (ClarionCore → Proxmox `192.168.1.113:/srv/backups`):** Server-created **`biobase/clips`** is often **`root:root` `755`**, so NFS root-squash blocks **all** client writes. Fix options:

1. **`bb_cs2_server/scripts/apply-clips-bind.sh`** — creates writable **`/mnt/backups/biobase_clips_upload`**, **`mount --bind`** onto **`/mnt/backups/biobase/clips`** when a writetest fails, appends **`fstab`** (`bind,nofail`), **`mount -a`**, migrates legacy Docker volume **`bb_cs2_server_bb_cs2_dashboard_clips`** if present, rebuilds/recreates **`bb_cs2_dashboard`** only.
2. **`bb_cs2_server/scripts/proxmox-chown-biobase-clips.sh`** — run on **Proxmox** as root to `chown 65534:65534` **`/srv/backups/biobase/clips`** (then client writes work without bind).

**Verify:** `docker inspect bb_cs2_dashboard` → mount **Source** must be the VM clips path (`/mnt/backups/biobase/clips`), **Destination** `/data/clips`. `findmnt /mnt/backups/biobase/clips` may show NFS source **`.../biobase_clips_upload`** after bind/submount.

## Related

- [[biobase]] — platform overview
- [[biobase-hub-routing]] — hub nginx (separate from direct :8780 dashboard access)
- [[llm-wiki-pattern]] — wiki maintenance rules
