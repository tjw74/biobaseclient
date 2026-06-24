# Biobase Performance Review Layout

Updated: 2026-06-22T22:15:47Z

## Decision

Use one main Performance Review page with expandable category sections. Do not force the player into separate category pages by default.

## Layout

```text
Top Summary
  ↓
Sticky Category Rail
  ↓
Expandable Category Sections
  ↓
Optional Deep Dive
```

## Behavior

- Category rail click scrolls to and expands the category.
- One section opens by default: highest improvement opportunity.
- User can pin multiple sections open for comparison.
- Collapsed category rows must show score, trend, best signal, issue, and cost/opportunity.
- Deep-dive screens are optional secondary workflows.

## Why

Performance review depends on relationships across categories: movement affects aim, exposure affects deaths, utility timing affects entries, fatigue affects consistency. Forced separate pages hide those relationships.
