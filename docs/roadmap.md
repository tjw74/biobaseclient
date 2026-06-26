---
title: Biobase Performance Dataset Roadmap
created: 2026-06-22
updated: 2026-06-25T07:00:00Z
type: roadmap
tags: [biobase, cs2, performance, roadmap, analytics, ui]
status: active
---

# Biobase Performance Dataset Roadmap

## TLDR

Biobase performance analytics should be organized around 12 pro-player mental categories: Movement, Aim, Combat, Utility, Positioning, Decision Making, Teamplay, Economy, Round Performance, Consistency, Mechanical Execution, BioBase Biometrics. These are the canonical dataset groups Claude Code Desktop and other coding agents should use for future performance-dashboard work.

The app should not force one full page per category by default. The default experience should be a single **Performance Review** screen with compact category summaries, a sticky jump rail, and expandable sections. Dedicated category deep-dives are optional secondary views only when a player chooses to go deeper.

## Product Goal

Give pro CS2 players one match-review surface that answers:

- What mattered most this match?
- Which category helped me win or caused losses?
- What should I improve next?
- How do movement, aim, combat, utility, positioning, decisions, teamplay, economy, consistency, mechanics, and biometrics relate to each other?

The dashboard should feel like an expert coaching cockpit, not a generic analytics SaaS page.

## Canonical Dataset Categories

### Movement

- Velocity
- Strafing
- Bunny hops
- Counter-strafes
- Jumps
- Air control
- Positioning
- Movement efficiency
### Aim

- Crosshair placement
- Head-level %
- Flick accuracy
- Spray control
- Spray transfer
- Burst accuracy
- Tap accuracy
- First bullet accuracy
- Crosshair travel
- Target acquisition
- Time to first shot
- Reaction time
### Combat

- Kills
- Deaths
- Assists
- ADR
- Damage dealt
- Damage taken
- Headshot %
- Opening duels
- Trade kills
- Trade deaths
- Multi-kills
- Clutches
- Time to kill
- Survival time
### Utility

- Flash effectiveness
- Teammates flashed
- Enemies flashed
- Smoke effectiveness
- Molotov effectiveness
- HE damage
- Utility damage
- Utility value per round
- Utility timing
- Lineup success
### Positioning

- Heatmaps
- Angle hold time
- Angle win rate
- Time in cover
- Time exposed
- Peek locations
- Death locations
- Kill locations
- Rotation paths
- Distance traveled
### Decision Making

- Rotate timing
- Save decisions
- Retake participation
- Entry timing
- Re-peek frequency
- Aggression score
- Risk score
- Opportunity conversion
- Decision latency
### Economy

- Buy efficiency
- Equipment value
- Weapon value
- Economy impact
- Save success
- Upgrade timing
- Cost per kill
- Cost per damage
### Teamplay

- Trade percentage
- Spacing
- Distance to teammates
- Support effectiveness
- Flash assists
- Crossfires
- Bait deaths
- Refrag timing
- Site support timing
### Round Performance

- Round impact score
- MVP rounds
- Win contribution
- Objective contribution
- Bomb plants
- Defuses
- Entry impact
- Clutch impact
- Momentum
### Consistency

- Performance trend
- Round-to-round variance
- Aim consistency
- Movement consistency
- Decision consistency
- Utility consistency
- Confidence score
- Fatigue score
- Tilt indicator
### Mechanical Execution

- Reload timing
- Weapon switching
- Scope timing
- Accuracy recovery
- Weapon handling
- Input efficiency
- Idle time
- APM (actions per minute)
### BioBase Biometrics

- Heart rate
- HRV
- Respiration
- Skin temperature
- Skin conductance (stress)
- Eye tracking
- Blink rate
- Pupil dilation
- Posture
- Hand tremor
- Muscle tension
- Fatigue
- Cognitive load
- Focus score
- Stress score

## Category Order

Use this order unless a specific analysis flow says otherwise:

1. Movement
2. Aim
3. Combat
4. Utility
5. Positioning
6. Decision Making
7. Teamplay
8. Economy
9. Round Performance
10. Consistency
11. Mechanical Execution
12. BioBase Biometrics

This order matches how professional players naturally analyze performance: fundamentals first, outcome context second, team/economy layers next, then longitudinal consistency and biometrics.

## UI Doctrine for These Categories

Use the Clarion Zero-Cognitive-Load Interface Doctrine:

> Make the interface disappear by reducing every screen to the fewest meaningful decisions, highest useful density, calmest hierarchy, and clearest next action.

### Required Pattern

Default view: **single Performance Review page**.

Do not force users to switch full pages for every category. Category switching should be jump/scroll/expand behavior, not mandatory navigation. The player should feel like they are reviewing one match, not operating twelve dashboards.

### Screen Structure

1. **Top Summary**
   - Overall performance score
   - Biggest strength
   - Biggest weakness
   - Most costly mistake
   - Best improvement opportunity
   - Match/session context

2. **Sticky Category Rail**
   - Compact buttons/cards for all 12 categories
   - Each shows score, trend, and one key issue/signal
   - Click scrolls to and expands that category

3. **Expandable Category Sections**
   - Collapsed state remains useful: score, trend, best signal, worst signal, cost/impact
   - Expanded state shows compact stats, charts, timelines, heatmaps, and coaching notes
   - One category may be expanded by default: the category with the highest improvement opportunity
   - Users may pin multiple categories open for comparison

4. **Optional Deep Dive**
   - Dedicated category view only after the user chooses “Deep dive”
   - Use for dense charts, heatmaps, timelines, raw events, and replay-linked analysis

## Design Rules

- One page by default; deep dives are optional.
- No card soup. Group stats into analytical lenses.
- No duplicate labels between section title, chart title, legend, and value rows.
- Compact spacing, thin borders, low radius, small labels, tabular numbers.
- Use semantic color only: constructive, risk, caution, neutral, inactive.
- Prefer interpretation over raw dumps: score, trend, cost, opportunity, confidence.
- Show relationships across categories, e.g. counter-strafe timing impacting first-bullet accuracy.
- Keep replay tick/time alignment available for every stat and future biometrics sync.
- Screenshot/visual QA is required before declaring UI work complete.

## Collapsed Category Contract

Every collapsed category section should be useful without expansion:

```text
Movement 82 ↑
Best: air control
Issue: counter-strafe stop time
Cost: 3 lost duels
```

Minimum fields:

- category name
- category score
- trend or delta
- best signal
- worst signal
- cost/impact/opportunity

## Expanded Category Contract

Every expanded category should include:

- compact KPI strip
- one primary chart/timeline/heatmap when relevant
- top 3 metric insights
- mistake/opportunity callout
- confidence/source marker for heuristic metrics
- optional replay jump anchors

## Implementation Phases

### Phase 1 — Canonical Data Contract

- Define the 12 category groups and metrics as typed constants.
- Map each metric to source: demo parser, server telemetry, derived heuristic, user/session metadata, or biometric device.
- Add confidence/source flags for metrics that are not directly observed.

### Phase 2 — Performance Review Shell

- Build the single Performance Review page.
- Add top summary and sticky category rail.
- Add expandable sections with placeholder/available data.
- Default expansion should prioritize the highest improvement opportunity.

### Phase 3 — Movement + Aim First

- Start with Movement and Aim because they are foundational and directly linked to demo timeline/replay review.
- Preserve tick/time alignment for replay HUD.
- Show relationships: counter-strafe → first bullet, crosshair placement → time to damage, velocity/exposure → deaths.

### Phase 4 — Combat, Utility, Positioning, Decision Making

- Add outcome and tactical categories.
- Use heatmaps, event timelines, and round context.
- Start coaching summaries and mistake timeline.

### Phase 5 — Teamplay, Economy, Round Performance, Consistency

- Add team/economy outcome layers.
- Add trends across last 5/10 rounds and session history.
- Add consistency and variance analysis.

### Phase 6 — Mechanical Execution + BioBase Biometrics

- Add mechanical execution signals.
- Integrate biometrics once device streams exist.
- Align biometric samples to demo tick/time and round events.

## Acceptance Criteria for Agents

Any implementation touching the Biobase performance dashboard must:

- Use the 12 categories above as the canonical grouping.
- Preserve the single-page Performance Review model by default.
- Use expandable/collapsible sections with useful collapsed summaries.
- Add optional deep-dive views only as secondary actions.
- Follow the Clarion Interface Doctrine: value first, calm density, no card soup, no repeated labels.
- Keep replay tick/time alignment and metric source/confidence metadata.
- Update repo docs and wiki if category names, groupings, or UI behavior change.
