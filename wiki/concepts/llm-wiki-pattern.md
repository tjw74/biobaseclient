---
title: LLM Wiki pattern (Karpathy)
category: concepts
tags: [knowledge-management, llm, obsidian]
sources: [docs/llm-wiki-raw/karpathy-llm-wiki-gist.md]
summary: >-
  Persistent compiled wiki maintained by an LLM: raw sources stay immutable;
  markdown vault is the compounding artifact; schema/skills define operations
  (ingest, query, lint).
provenance:
  extracted: 0.88
  inferred: 0.10
  ambiguous: 0.02
created: 2026-05-11T12:00:00Z
updated: 2026-05-11T12:00:00Z
---

# LLM Wiki pattern (Karpathy)

**Sources:** distilled from [[karpathy-llm-wiki-gist]] (verbatim copy in-repo).

## Core idea

Instead of pure RAG on every question, the LLM **incrementally maintains** interlinked markdown: ingest updates many pages; query reads the compiled graph; periodic **lint** finds drift, orphans, and contradictions.

Three layers:

1. **Raw sources** — immutable inputs (this repo: `docs/llm-wiki-raw/`, `info.md`, READMEs).
2. **Wiki** — LLM-owned markdown under `wiki/` (this project’s vault).
3. **Schema** — skills in `obsidian-wiki/.skills/` plus Cursor rules (`.cursor/rules/biobase-llm-wiki.mdc`).

## In this monorepo

- Vault: [[biobase]] hub under `wiki/projects/biobase/`.
- Optional CLI search at scale: [qmd](https://github.com/tobi/qmd) (see Karpathy gist; wired via env in `obsidian-wiki/.env.example` if you enable QMD).

## Related

- [[andrej-karpathy]] — gist author (stub).
- [[karpathy-llm-wiki-gist]] — raw gist text.
