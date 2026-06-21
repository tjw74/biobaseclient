---
title: Zero-Inference Labeling
category: concepts
tags: [design-philosophy, ux, naming, marketing-psychology, biobase]
sources: [conversation]
summary: >-
  Naming philosophy: every label should communicate its meaning with zero
  cognitive inference required from the user. If hearing a name makes you
  ask "what is that?", the name has failed.
provenance:
  extracted: 0.95
  inferred: 0.05
  ambiguous: 0.00
created: 2026-06-21T23:00:00Z
updated: 2026-06-21T23:00:00Z
---

# Zero-Inference Labeling

A design and naming philosophy applied across all BioBase surfaces: every label, button, tab, menu item, and section name must communicate what it is with **zero cognitive inference** from the user. The name completes its own sentence.

## The principle

> If someone reads a label and has to mentally supply a missing word to understand it, that label has an **inference gap**. Every inference gap is friction. Zero gaps is the target.

This applies to UI labels, feature names, documentation headers, marketing copy, API endpoint names, and internal terminology.

## The test

Ask: *"If a new user sees this word in isolation, do they immediately know what's behind it, or do they ask 'what's that?'"*

- If they know: the label passes.
- If they ask: the label has an inference gap. Find a word that closes it.

## Case study: Review vs. Playback

The BioBase desktop client has two tabs. The first is **Live** — real-time stats while playing CS2. The second tab lets users watch recorded demo files with stats overlaid.

**"Review"** was the original name. Analysis:

- "Review" is a **judgment word**. It activates the evaluative brain: performance review, code review, peer review.
- It requires the user to supply the object: *"Review what?"* That's one inference gap.
- It carries emotional baggage — review implies you did something wrong that needs examining.
- It feels like work before you've clicked it.

**"Playback"** replaced it. Analysis:

- "Playback" is a **mechanical word**. It activates the media brain: VHS, DVR, YouTube.
- Everyone on earth knows what playback means: something was recorded, now you watch it.
- The demo file IS the recording. The tab IS where you play it back. The name completes its own sentence.
- Zero inference gaps. Zero emotional baggage. Zero ambiguity.

The psychology gap: "Review" asks the user to **infer purpose**. "Playback" **states it**.

## Word categories and inference load

| Category | Example | Inference load | Risk |
|---|---|---|---|
| **Mechanical** | Playback, Upload, Download, Connect | Zero — describes the action | None |
| **Descriptive** | Live Stats, Server Status, Movement | Zero — describes the content | None |
| **Purposive** | Review, Analyze, Optimize | One gap — "review what?" | User pauses |
| **Abstract** | Dashboard, Hub, Portal, Suite | Two gaps — "what's in it? what does it do?" | User lost |
| **Branded** | Playground, Workspace, Studio | Variable — depends on learned context | New users excluded |

Prefer mechanical and descriptive words. Avoid purposive and abstract words unless the context makes them unambiguous.

## Application beyond UI labels

This philosophy extends to:

- **API endpoints**: `/api/client/live/movement` tells you exactly what it returns. `/api/client/data` does not.
- **Documentation headers**: "Auto-Update Pipeline" is zero-inference. "Infrastructure" is not.
- **Feature names**: "Phone Companion" tells you what it is. "Secondary Display" does not.
- **Error messages**: "Server offline — no players connected" is actionable. "Connection error" is not.
- **Commit messages**: "Rename Review tab to Playback" is clear. "Improve naming" is not.

## Broader design alignment

Zero-inference labeling is one expression of the broader BioBase design principle: **extreme friction reduction**. Every moment the user spends interpreting, guessing, or wondering is friction. Every label that explains itself removes a moment of friction. The cumulative effect across an entire interface is the difference between software that feels intuitive and software that feels like work.

## Related

- [[biobase]] — project hub
- [[biobase-windows-client-primary-ui]] — client UI where this principle is applied
- [[biobase-product-roadmap]] — roadmap organized with zero-inference section names
