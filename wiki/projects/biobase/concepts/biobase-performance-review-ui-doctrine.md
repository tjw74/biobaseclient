---
title: Biobase Performance Review UI Doctrine
created: 2026-06-22
updated: 2026-06-24T04:20:00Z
category: concepts
type: doctrine
tags: [biobase, ui, design, performance-review, dashboard]
sources: [projects/biobase]
status: active
---

# Biobase Performance Review UI Doctrine

## TLDR

Biobase should use one main **Performance Review** screen, not twelve forced category pages. Categories appear as compact summaries and expandable sections on the same screen, with optional deep dives only when the player wants more detail.

## Core Philosophy

The interface should disappear. A pro player should be able to understand the match, identify the biggest improvement opportunity, and jump to the relevant replay moment without thinking about navigation.

## Default Layout

```text
Performance Review

Top Summary
  Overall | Strength | Weakness | Costliest mistake | Next improvement

Sticky Category Rail
  Movement | Aim | Combat | Utility | Positioning | Decision | Teamplay | Economy | Round | Consistency | Mechanics | Biometrics

Expandable Sections
  ▼ Movement
  ▶ Aim
  ▶ Combat
  ▶ Utility
  ...
```

## Navigation Rule

Do not make category switching mandatory full-page navigation. Use:

- sticky rail buttons
- scroll anchors
- accordion expansion
- pin-open comparison
- optional deep-dive button

This keeps the player in one mental place: reviewing the match.

## Personalization Contract

- Every category row has an explicit drag handle.
- User ordering persists locally and remains stable across launches.
- Multiple categories may stay expanded for comparison.
- Expansion state persists locally.
- Provide Expand all, Collapse all, and Reset order.
- The category rail follows the personalized row order.
- Expanded sections list every canonical metric and its evidence state, even when the metric is not measured yet.

This gives players control without hiding the canonical structure or implying that unavailable data is zero.

## Progressive Disclosure

### Level 1 — Top Summary

Show the few signals that matter most.

### Level 2 — Category Rail

Show all categories, each with one score/trend/key issue.

### Level 3 — Expandable Section

Show the category-specific stats and charts.

### Level 4 — Deep Dive

Only for dense analysis, raw events, heatmaps, or replay-linked workflows.

## Visual Rules

- Compact density, not empty minimalism.
- Thin borders, low radius, subtle surfaces.
- Small labels, tabular numbers, values close to labels.
- Thin charts, minimal gridlines, no decorative badges.
- Semantic color only.
- No repeated labels.
- No one-card-per-metric grid.
- No generic “Insights” sections when specific labels exist.

## Completion Checklist

Before marking UI work done:

- Screenshot reviewed.
- Duplicate labels removed.
- Category rail visible and useful.
- Collapsed sections contain actionable summary.
- Expanded sections are compact and interpretable.
- Deep-dive navigation is optional, not required.
- Mobile/phone companion behavior considered when relevant.
