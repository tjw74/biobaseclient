# Biobase Performance Review Layout

Updated: 2026-06-24T04:20:00Z

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
- Categories are reorderable by drag handle; the personalized order persists.
- Expansion state persists and multiple sections may remain open for comparison.
- Expand all, collapse all, and reset order controls are always available.
- Collapsed category rows must show score, trend, best signal, issue, and cost/opportunity.
- Expanded sections retain the focused category dashboard and expose the full canonical metric inventory with measured/estimated/not-measured state.
- Deep-dive screens are optional secondary workflows.

## Why

Performance review depends on relationships across categories: movement affects aim, exposure affects deaths, utility timing affects entries, fatigue affects consistency. Forced separate pages hide those relationships.
