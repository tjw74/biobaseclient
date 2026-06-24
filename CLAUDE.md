# Biobase — Claude Code Instructions

Use this file before implementing Biobase features.

## Product Direction

Biobase is a Windows-first CS2 performance analytics client plus central server. The desktop client is the primary user experience; the web/admin surfaces are secondary/operator surfaces.

## Performance Roadmap

Canonical docs:

- `docs/roadmap.md`
- `docs/features/performance_dataset_categories.md`
- `docs/ui/clarion_interface_doctrine.md`
- `docs/ui/performance_review_layout.md`
- `wiki/projects/biobase/concepts/biobase-performance-dataset-roadmap.md`
- `wiki/projects/biobase/concepts/biobase-performance-review-ui-doctrine.md`

## UI Rule

Default to **one Performance Review screen**:

1. Top summary.
2. Sticky category rail.
3. Expandable category sections.
4. Optional category deep dives only when explicitly selected.

Do not build twelve forced separate pages for Movement, Aim, Combat, Utility, etc. unless the task specifically asks for a deep-dive screen.

## Design Doctrine

Follow Clarion Zero-Cognitive-Load Interface Doctrine:

- value first, chrome last
- calm density
- compact analytical hierarchy
- no card soup
- no duplicated labels
- semantic color only
- thin charts, low padding, low radius
- screenshot/visual review before completion

## Canonical Categories

Movement, Aim, Combat, Utility, Positioning, Decision Making, Economy, Teamplay, Round Performance, Consistency, Mechanical Execution, BioBase Biometrics.
