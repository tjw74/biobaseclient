# Biobase — agent context

Monorepo for **CS2 / Biobase** analytics: Docker stacks (`bb_client`, `bb_cs2_server`, `bb_biobase_local`, monitoring), **Postgres** session ingest (**`bb_data_collection`**), **Grafana/Loki**, and operator **hub** (`http://<host>:8880/` by default).

## LLM Wiki (Karpathy pattern)

- **Compiled wiki directory:** `wiki/` (Obsidian-compatible markdown).
- **Framework + skills:** `obsidian-wiki/` — skills are symlinked to **`.cursor/skills`** for Cursor.
- **Setup:** Copy `obsidian-wiki/.env.biobase.example` → `obsidian-wiki/.env` and set `OBSIDIAN_VAULT_PATH` to your absolute path to **`wiki/`** if it differs from the example.
- **Raw gist copy:** `docs/llm-wiki-raw/karpathy-llm-wiki-gist.md`
- **Operator map (canonical narrative):** `info.md` at repo root — compare with `bb_client/initdb/*.sql` for current table/schema placement (`public` / `ops` / `game`).

When the user asks to ingest, lint, or query the wiki, open the matching skill under `obsidian-wiki/.skills/`.

## Biobase Performance Roadmap + UI Doctrine

When building performance analytics, use these files as the canonical guide:

- `docs/roadmap.md`
- `docs/features/performance_dataset_categories.md`
- `docs/ui/clarion_interface_doctrine.md`
- `docs/ui/performance_review_layout.md`
- `wiki/projects/biobase/concepts/biobase-performance-dataset-roadmap.md`
- `wiki/projects/biobase/concepts/biobase-performance-review-ui-doctrine.md`

Core rule: the default UX is **one Performance Review screen** with a top summary, sticky category rail, and expandable sections. Do not force a separate full page for Movement/Aim/Combat/etc. unless implementing an optional deep-dive view. Preserve compact, value-first, low-cognitive-load UI: no card soup, no duplicated metric labels, semantic color only, and screenshot review before marking UI complete.
