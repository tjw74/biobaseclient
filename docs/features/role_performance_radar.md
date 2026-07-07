# Role Performance Radar — Product & Technical Specification

Feature: Skybox-EDGE-class role radar for player evaluation and comparison.
Audience: frontend engineer, backend engineer, data engineer, CS2 analyst.
Status: spec v1 — 2026-07-07.

---

## 1. Chart type

Radar (spider/web) chart.

- **Primary polygon**: the selected player, filled at ~18% opacity, 1.5px stroke, accent color.
- **Comparison polygon** (optional, one at a time): teammate, opponent, team average, role average, or a saved custom benchmark. Dashed 1.2px stroke, secondary color, no fill (or 8% fill). Two polygons maximum — a radar with 3+ polygons is unreadable.
- **Axes**: one per metric (12 axes, section 2). Order is fixed and grouped so adjacent axes are conceptually related (firepower axes together, utility axes together, trade axes together, opening axes together). Fixed order matters: users learn shapes ("entry shape", "anchor shape") and shape recognition breaks if axis order changes.
- **Scale**: all axes normalized 0–100 (section 10). Rings at 25/50/75. The 50 ring is visually emphasized — it is the benchmark median.
- **Raw values**: never lost. Tooltips show raw value + percentile + sample size. The metric table (section 7) shows raw values for both polygons plus delta.

Axis order (clockwise from top):

```
Rating → ADR → KPR → K/D → DPR(inv) → KAST →
Traded deaths/r → Trade kills/r → Opening attempts → Opening K/D →
Flash assists/r → Utility dmg/r
```

---

## 2. Metrics

| # | Axis | Raw unit | Direction | Kind |
|---|------|----------|-----------|------|
| 1 | Rating | ~0.0–2.0 | higher better | quality |
| 2 | ADR | dmg/round | higher better | quality |
| 3 | KPR | kills/round | higher better | quality |
| 4 | K/D | ratio | higher better | quality |
| 5 | DPR | deaths/round | **lower better** | quality |
| 6 | KAST | % rounds | higher better | quality |
| 7 | Traded deaths /r | per round | higher better* | style+quality |
| 8 | Trade kills /r | per round | higher better | style+quality |
| 9 | Opening attempts /r | per round | **neither** | style |
| 10 | Opening K/D | ratio | higher better | quality |
| 11 | Flash assists /r | per round | higher better* | style+quality |
| 12 | Utility damage /r | dmg/round | higher better* | style+quality |

\* "higher better" only relative to the player's **role benchmark** — see section 10.

**Rating** — composite form score. We compute the public approximation of HLTV 2.0 and label it "BB Rating" (we cannot reproduce HLTV's proprietary coefficients exactly):
`Rating ≈ 0.0073·KAST% + 0.3591·KPR − 0.5329·DPR + 0.2372·Impact + 0.0032·ADR + 0.1587`, with `Impact ≈ 2.13·KPR + 0.42·APR − 0.41`.
Why coaches care: single-number form tracker; the anchor axis everyone already speaks.

**ADR** — average damage per round: `Σ health damage dealt to enemies / rounds`. Damage is as-applied (already capped by remaining HP in `player_hurt.dmg_health`); team damage and self damage excluded. Why: measures consistent damage output even when kills are stolen/traded — the least noisy firepower stat.

**KAST** — % of rounds where the player got a **K**ill, **A**ssist, **S**urvived, or was **T**raded (a teammate killed the player's killer within the trade window). Why: round-participation floor. A player with high rating and low KAST feasts in some rounds and disappears in others; a high-KAST low-rating player contributes something every round.

**Flash assists /r** — kills by teammates on enemies blinded by this player's flash (`player_death.assistedflash == true` with this player as assister), per round. Why: measures supportive utility that never appears in K/D; the defining stat of support players.

**Utility damage /r (UDR)** — damage from HE/molotov/incendiary thrown by the player, per round: `player_hurt.weapon ∈ {hegrenade, inferno, molotov, incgrenade}` attributed to thrower. Why: quantifies grenade quality — anchors and supports generate 15–25 UDR; a low-UDR anchor is giving up free damage on executes.

**Traded deaths /r** — the player's deaths that were avenged by a teammate within the trade window, per round. Why: dying *usefully*. Entry players should die traded (they die into a prepared teammate); a high-death player with low traded-death rate is dying alone in the wrong places.

**DPR** — deaths per round. Lower is better; the axis is inverted at normalization so "big polygon = good" stays true. Why: survival is CT-side map control and T-side post-plant equity; lurkers and anchors live on low DPR.

**K/D** — kills / deaths across the filter set. Why: the classic; kept because players and orgs expect it, but positioned next to KPR/DPR which decompose it.

**KPR** — kills per round. Why: raw fragging volume independent of deaths.

**Trade kills /r** — kills where the player killed an enemy who had killed a teammate within the trade window, per round. Why: refragging discipline; the defining stat of the "pack" second-man and rotating CTs.

**Opening K/D** — opening kills / opening deaths, where the opening duel is the **first kill of the round**. Why: quality *in* the opening duel — does the player win the fights they take first?

**Opening attempts /r** — rounds where the player was the killer **or victim** of the round's first kill, per round. Why: this is a **style** axis, not a quality axis. High attempts = entry/aggressive spacetaker; low attempts = lurker/anchor. Neither is better — it defines the role shape. (Section 10 covers how normalization treats it.)

Trade window: **5.0 seconds** (configurable constant; Skybox and HLTV both use ~5s). Both trade metrics and KAST's "T" use the same window so numbers reconcile.

---

## 3. Filters

All filters compose (AND semantics) and apply to both polygons unless the comparison explicitly overrides them (e.g. compare "me on Mirage T-side" vs "role average all maps").

| Filter | Options | Notes |
|--------|---------|-------|
| Player | any ingested player | search by name/steamid; roster grouping |
| Comparison | none · player · team avg · role avg · opponent avg · custom benchmark | one at a time |
| Map | all · de_mirage · de_inferno · … | list from ingested data, not hardcoded |
| Side | both · T · CT | side-splitting changes role list (below) |
| Time | 30d · 3m · 6m · custom range | on match date |
| Match count | last 10 · 25 · 50 · 100 | mutually exclusive with time filter; most-recent-first |
| Buy type | all · pistol · eco · force · full | player's **team** buy state for the round |
| Role | All · CT allround · Anchor · Rotation · T allround · Lurk · Half-lurk · Pack/entry | role filters the **benchmark population** and (optionally) the player's tagged rounds |

Buy type classification (team equipment value at freeze end, CS2 values):

- **pistol**: round 1 or 13
- **eco**: team spend < $5,000
- **force**: $5,000–$20,000 and not following a won round with full save intent (v1: just the band)
- **full**: > $20,000

Role filters have two modes:

1. **Benchmark mode** (default): the player polygon uses all their rounds; the *benchmark/percentile population* is players tagged with that role. "How does s1mple look measured against lurkers?"
2. **Round-scope mode** (toggle): only the player's rounds tagged with that role are aggregated. Requires role tags at player-map-side granularity (section 8).

---

## 4. Data sources

Ingest CS2 `.dem` files (already implemented in `bb_cs2_dashboard/demo_native.py` via awpy + demoparser2). Fields consumed by this feature:

| Data | demoparser2 source | Status in BioBase |
|------|--------------------|-------------------|
| Player identity (steamid, name) | tick props / event payloads | ✅ parsed |
| Team + side per round | `team_num` per tick, round spans | ✅ parsed |
| Round number/spans | `round_start`, `round_end` events | ✅ parsed |
| Map | header | ✅ parsed |
| Tick timestamps | ticks | ✅ parsed |
| Kills/deaths/assists | `player_death` (attacker, victim, **assister_steamid**, headshot, weapon, `assistedflash`) | ✅ stored (assister fields present in payload) |
| Damage events | `player_hurt` (attacker, victim, `dmg_health`, weapon, hitgroup) | ✅ stored |
| Flash blind events | `player_blind` (attacker, victim, `blind_duration`) | ➕ add to `EVENT_NAMES` |
| Utility throws/detonations | `hegrenade_detonate`, `inferno_startburn`, `flashbang_detonate` | ➕ add (positions optional v1) |
| Trade windows | derived from `player_death` sequence | derived |
| Economy/buy state | tick props `balance`/equipment value sampled at `round_freeze_end` | ➕ add `round_freeze_end` + one economy sample per round |
| Round result | `round_end` payload (`winner`) | ➕ read payload (already stored in `data`) |
| Player positions | ticks X/Y/Z | ✅ parsed |
| Opening duel events | first `player_death` per round | derived |

Parser delta is small: extend `EVENT_NAMES`, add one economy snapshot per round, keep everything else.

---

## 5. Derived data — exact calculations

All derivations run per **player-round** first (the atom), then aggregate.

Let `R` = set of rounds in the filter scope, `|R|` = round count.

- **ADR** = `Σ dmg_health(attacker=p, victim∈enemies) / |R|`
- **KPR** = `kills(p) / |R|` — kills exclude team kills and suicides (`attacker==victim` or `weapon=='world'`)
- **DPR** = `deaths(p) / |R|`
- **K/D** = `kills(p) / max(1, deaths(p))`
- **KAST** = `|{r ∈ R : kill ∨ assist ∨ survived ∨ traded_death}| / |R| × 100`
  - assist = `player_death.assister_steamid == p` (flash assists count)
  - survived = alive at `round_end`
  - traded_death = p's killer was killed by any teammate within 5s of p's death
- **Opening attempt** (per round) = p is attacker or victim of the round's first kill → **attempts/r** = `opening_rounds / |R|`
- **Opening duel win rate** = `opening_kills / (opening_kills + opening_deaths)`
- **Opening K/D** = `opening_kills / max(1, opening_deaths)`
- **Trade kills /r** = `|{kills by p where victim had killed a teammate of p within the previous 5s}| / |R|`
- **Traded deaths /r** = `|{deaths of p avenged by teammate within 5s}| / |R|`
- **Flash assists /r** = `|{player_death: assister==p ∧ assistedflash}| / |R|`
- **Utility damage /r** = `Σ dmg_health(attacker=p, weapon∈UTILITY) / |R|`, `UTILITY = {hegrenade, inferno, molotov, incgrenade}`

**Role benchmarks**: for each role × filter-combination, compute the distribution (p5, p25, p50, p75, p95, mean, n) of every metric over the benchmark population (all player-stints tagged with that role, minimum 100 rounds each). Stored snapshots, recomputed nightly (section 8).

**Percentile normalization**: see section 10.

**Minimum sample-size warnings**:

- `|R| < 30` → red badge "Very low sample — directional only", polygon rendered with dotted stroke.
- `30 ≤ |R| < 100` → amber badge "Low sample (n rounds)".
- Opening metrics additionally require `opening_attempts ≥ 10` else that axis renders hollow (no fill to the point) with an "insufficient" tooltip.

---

## 6. Value to pro teams

- **Role identity**: the polygon *shape* is the role. High opening attempts + high traded deaths + mid ADR = entry. Low DPR + high UDR + low opening attempts = anchor. Coaches see at a glance whether a player's actual play matches the role on the whiteboard.
- **Role expectations**: comparing against the *role average* polygon (not the global average) answers "is this a good anchor" instead of "is this a good fragger" — the question global stats can't answer.
- **Underperformance**: quality axes (Rating, ADR, KAST, Opening K/D) below the role median while style axes match = right role, poor execution → aim/positioning work. Style axes off = wrong role or broken system.
- **Improvement over time**: same player, time filter 3m vs custom previous-3m benchmark → polygon delta is the progress report.
- **Roster competition**: two candidates for the same slot, same filter set, one chart. The table below the radar gives the per-metric deltas for the decision doc.
- **Opponent prep**: opponent player vs their role average reveals exploitable deviations — an anchor with high opening attempts will peek; a lurker with low traded deaths dies alone (push the lurk).
- **Roster validation**: post-transfer, verify the new player's shape in *your* system vs their shape in the old team (time-range comparison).
- **Practice priorities**: the weakest quality axis relative to role benchmark is the practice queue, updated weekly.

---

## 7. UI / UX

Layout (single screen, Clarion doctrine — calm density, no card soup):

```
┌──────────────────────────────────────────────────────────────┐
│ FILTER BAR: [Player ▾] vs [Comparison ▾]   Map ▾  Side ▾     │
│             Time ▾  Matches ▾  Buy ▾  Role ▾        [Export ▾]│
├──────────────────────────────┬───────────────────────────────┤
│                              │  COMPARISON SUMMARY           │
│                              │  player photo/name/team/role  │
│        RADAR CHART           │  n rounds · n matches · dates │
│        (center-left,         │  ── biggest gaps ──           │
│         ~55% width)          │  +21 UDR   vs role avg        │
│                              │  −14 Opening K/D percentile   │
│                              │  sample badge                 │
├──────────────────────────────┴───────────────────────────────┤
│ METRIC TABLE: metric · raw A · raw B · Δ · percentile A/B ·  │
│               sparkline (last 10 matches) · sample n         │
└──────────────────────────────────────────────────────────────┘
```

- **Tooltip** (hover an axis vertex): metric name, raw value, unit, percentile, benchmark median raw value, sample n, one-line definition. 250ms delay, follows vertex not cursor.
- **Axis click**: pins the tooltip and highlights the metric's row in the table.
- **Empty state**: "No rounds match these filters" + the single most restrictive filter called out ("0 eco rounds on de_nuke in the last 30 days — remove Buy filter?").
- **Loading state**: radar skeleton (gray rings + pulsing axes), never spinners over data.
- **Low sample**: badges per section 5; polygon style degrades (dotted) rather than hiding data.
- **Export**: PNG (chart at 2x, dark and light), CSV (metric table incl. raw + percentile + n), PDF report (chart + table + filter set + generated-at + benchmark description — one page).

---

## 8. Data model

```sql
players (
  player_id     BIGINT PK,          -- steamid64
  name          TEXT,               -- latest known
  team_id       BIGINT FK NULL,
  role_default  TEXT NULL           -- coach-assigned: anchor|rotation|lurk|...
);

teams (
  team_id   BIGINT PK,
  name      TEXT,
  org_tag   TEXT
);

matches (
  match_id     BIGINT PK,
  demo_sha256  TEXT UNIQUE,
  map          TEXT,
  played_at    TIMESTAMPTZ,
  team1_id     BIGINT FK,
  team2_id     BIGINT FK,
  score1       INT,
  score2       INT,
  source       TEXT                 -- hltv|faceit|own-server
);

rounds (
  match_id     BIGINT FK,
  round_no     INT,
  start_tick   INT,
  end_tick     INT,
  winner_side  TEXT,                -- T|CT
  t_buy_type   TEXT,                -- pistol|eco|force|full
  ct_buy_type  TEXT,
  PRIMARY KEY (match_id, round_no)
);

player_round_stats (                -- THE ATOM. One row per player per round.
  match_id        BIGINT,
  round_no        INT,
  player_id       BIGINT,
  side            TEXT,             -- T|CT
  role_tag        TEXT NULL,        -- per-round role (nullable, inherits default)
  kills           INT, deaths INT, assists INT,
  headshots       INT,
  damage          INT,              -- to enemies, applied
  utility_damage  INT,
  flash_assists   INT,
  got_kill        BOOL, got_assist BOOL, survived BOOL, was_traded BOOL,
  trade_kills     INT,
  traded_death    BOOL,
  opening_kill    BOOL, opening_death BOOL,
  PRIMARY KEY (match_id, round_no, player_id)
);

player_match_stats (                -- materialized rollup for fast filters
  match_id BIGINT, player_id BIGINT, side TEXT,      -- side='both' row too
  rounds INT, kills INT, deaths INT, assists INT, damage INT,
  utility_damage INT, flash_assists INT, trade_kills INT,
  traded_deaths INT, kast_rounds INT,
  opening_kills INT, opening_deaths INT,
  PRIMARY KEY (match_id, player_id, side)
);

radar_metric_definitions (
  metric_key    TEXT PK,            -- 'adr', 'kast', 'opening_attempts_pr', ...
  display_name  TEXT,
  unit          TEXT,
  direction     TEXT,               -- higher|lower|style
  kind          TEXT,               -- quality|style|hybrid
  description   TEXT,
  formula       TEXT
);

role_benchmarks (                   -- nightly snapshots
  benchmark_id  BIGSERIAL PK,
  role          TEXT,               -- 'anchor', 'lurk', 'all', ...
  scope_hash    TEXT,               -- hash of (map, side, buy, time bucket)
  metric_key    TEXT FK,
  p5 REAL, p25 REAL, p50 REAL, p75 REAL, p95 REAL,
  mean REAL, population INT,
  computed_at   TIMESTAMPTZ,
  UNIQUE (role, scope_hash, metric_key, computed_at)
);
```

Aggregation path: filters → scan `player_match_stats` (fast path) or `player_round_stats` (buy/role/side round-level filters) → aggregate → normalize against matching `role_benchmarks` snapshot.

---

## 9. API design

Base: `/api/radar`.

### `GET /api/radar/player/{steamid}`

```
?maps=de_mirage&side=T&window=3m&buy=full&role_benchmark=lurk
&compare=player:76561198012345678 | team_avg:4494 | role_avg:lurk | none
```

```json
{
  "player": { "steamid": "76561198061763596", "name": "n1ssim", "team": "Legacy" },
  "scope": { "maps": ["de_mirage"], "side": "T", "window": "3m",
             "buy": "full", "rounds": 214, "matches": 17,
             "sample_quality": "ok" },
  "benchmark": { "role": "lurk", "population": 63, "computed_at": "2026-07-07T02:00:00Z" },
  "axes": [
    { "metric": "rating",  "raw": 1.12, "normalized": 61, "benchmark_median_raw": 1.05 },
    { "metric": "adr",     "raw": 78.4, "normalized": 58, "benchmark_median_raw": 74.1 },
    { "metric": "dpr",     "raw": 0.61, "normalized": 66, "benchmark_median_raw": 0.65,
      "inverted": true },
    { "metric": "opening_attempts_pr", "raw": 0.14, "normalized": 31,
      "style_axis": true },
    { "metric": "opening_kd", "raw": 1.4, "normalized": 72,
      "sample": 29, "sample_quality": "ok" }
  ],
  "comparison": {
    "kind": "role_avg", "label": "Lurk average",
    "axes": [ { "metric": "rating", "raw": 1.05, "normalized": 50 } ]
  }
}
```

### `GET /api/radar/benchmarks?role=anchor&maps=all&side=CT`

```json
{
  "role": "anchor", "scope_hash": "c4f2…", "population": 71,
  "metrics": {
    "adr":  { "p5": 51.2, "p25": 62.0, "p50": 68.9, "p75": 75.3, "p95": 84.0 },
    "udr":  { "p5": 4.1,  "p25": 9.8,  "p50": 14.2, "p75": 19.6, "p95": 27.3 }
  }
}
```

### `GET /api/radar/filters`

```json
{
  "maps": ["de_ancient","de_dust2","de_inferno","de_mirage","de_nuke","de_overpass","de_train"],
  "sides": ["both","T","CT"],
  "windows": ["30d","3m","6m","custom"],
  "match_counts": [10,25,50,100],
  "buy_types": ["all","pistol","eco","force","full"],
  "roles": ["all","ct_allround","anchor","rotation","t_allround","lurk","half_lurk","pack_entry"],
  "players": [{ "steamid": "…", "name": "donk", "team": "Spirit" }]
}
```

### `GET /api/radar/metrics`

Returns `radar_metric_definitions` rows verbatim — the client renders tooltips and the docs page from this, so definitions live in exactly one place.

---

## 10. Implementation notes

**Normalization = percentile against the benchmark population, robust-clamped.**

```
norm(x) = clamp(percentile_of(x, benchmark_distribution), p5→0, p95→100)
```

Interpolate between stored quantiles (p5/p25/p50/p75/p95). Median lands at 50 by construction, so the 50-ring *is* the role median. Never min-max normalize against the current chart's two players — the polygon would change shape when you change the comparison, destroying trust.

**Lower-is-better (DPR)**: invert after percentile: `norm = 100 − percentile`. Mark `"inverted": true` in the API; tooltip shows the raw value with the direction arrow ("0.61 DPR — lower is better").

**Style axes (opening attempts)**: percentile against the **role** population, not global — 0.14 attempts/r is ~80th percentile for lurkers, ~10th for entries. When benchmarking against "All", render style axes in a visually distinct tone (muted axis label + "style" chip in tooltip) so a small value is not read as "bad." Never include style axes in any single-number "overall score."

**Cross-role fairness**: quality axes normalize against the *selected role benchmark*, so "good for an anchor" is the built-in interpretation. Comparing two players from different roles → default to each player normalized against **their own** role benchmark with a banner "normalized per-role"; a toggle switches both to a common population for raw-ability comparison.

**Small samples**: hard/soft badges per section 5. Rate metrics with tiny denominators (opening K/D on 6 attempts) get **empirical-Bayes shrinkage** toward the role median: `x' = (n·x + k·median)/(n + k)` with k≈10; shrunk values are marked in tooltips ("stabilized — low sample"). Never silently plot a 3-attempt 3.0 opening K/D at the 99th percentile.

**Performance quality vs role style — the core design stance**: the radar deliberately mixes both, because the *shape* answers "what does this player do" (style) and the *distance from the 50-ring on quality axes* answers "how well do they do it." The UI separates them everywhere else: table groups metrics by kind, tooltips carry the kind chip, exports label them, and no composite score ever sums a style axis.

**Caching**: benchmark snapshots nightly; player aggregates cached per (player, filter-hash) with invalidation on new demo ingest. Radar responses are <5KB — precompute nothing else.

**BioBase integration path**: parser deltas in section 4 (add `player_blind`, `round_freeze_end` + economy snapshot, read `round_end.winner`, keep assister fields); `player_round_stats` builder as a post-parse step in `bb_cs2_dashboard`; radar UI as a Review-screen section (player already selected there) with the comparison selector in the section header; benchmarks bootstrap from the pro-demo library already on the biobasedata API.
