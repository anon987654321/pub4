# Principle-map gap audit: v110 → HEAD (key-by-key)

Codified 2026-08-03. Baseline of the audit: pub4 @ `48ed968c`. Headline counts
re-verified against `data/principle_map.yml` at `1eaeefec1` and match exactly
(138 entries, `status` covered 51 / gap 86 / unmapped 1, 72 distinct operations,
134/138 with both `detects` + `operation`).

## Correction to an earlier claim

An earlier note said smells *"transferred nearly 1:1 (227→225)"*. **That was wrong** —
it compared raw counts (v110's 227 smells vs HEAD's 225 YAML rule ids) without
checking identity. Matched by name, the real overlap is **105 of 227 (46%)**. The two
numbers being nearly equal is a coincidence.

## The architecture v110 had

Every one of v110's 293 principles carried five fields:

```yaml
tell_dont_ask:
  meaning: command objects rather than querying them
  detects: feature_envy          # -> a smell
  severity: medium
  confidence: 0.75
  operation: move_method         # -> a repair from the operations catalog
```

**293/293 (100%)** named both a `detects` smell and a repair `operation`, referencing
94 distinct operations — a closed graph: principle → smell → repair.

## What HEAD kept

`data/principle_map.yml` preserves that schema (`meaning/detects/severity/confidence/
operation`) and adds `rule_ids` + `status`. The architecture survived; the population
did not.

| | v110 | HEAD |
|---|---|---|
| principles | 293 | 138 in principle_map (47%) |
| …with `detects` + `operation` | 293 (100%) | 134/138 |
| …enforced by rules (`status: covered`) | — | **51** |
| v110 principles absent from the map | — | 164 |

MASTER already tracks this honestly: `status` is `covered: 51`, **`gap: 86`**,
`unmapped: 1`. 87 of 138 entries have empty `rule_ids` — declared law with nothing
enforcing it, but at least *labelled*. **Net: of v110's 293 principles, 51 (17%) are
enforced today.**

## Principles: 293 → 157 exact / 81 partial / 55 absent

### Real engineering losses (16) — each had a working detector + repair in v110

| principle | detects | operation |
|---|---|---|
| avoid_premature_optimization | premature_optimization | simplify |
| tell_dont_ask | feature_envy | move_method |
| extend_dont_replace | unnecessary_rewrite | extend |
| boring_technology | trendy_stack | simplify |
| pareto_principle | unfocused_effort | simplify |
| sectionitis_prevention | deep_nesting | flatten |
| performance_theater_avoidance | performance_theater | delete |
| teslers_law | hidden_complexity | delete |
| remove_non_essentials | unclear_intent | delete |
| essential_elements_only | unnecessary_elements | simplify |
| utilitas | purposeless_code | clarify_purpose |
| learnability | steep_learning_curve | simplify |
| intuitive_navigation | confusing_navigation | simplify |
| direct_manipulation | indirect_interaction | simplify |
| fittss_law | long_function | simplify |
| von_restorff_effect | uniform_presentation | simplify |

`sectionitis_prevention` and `boring_technology` restore first — both mechanically
checkable (config nesting depth; dependency churn) and both failure modes this repo
keeps hitting.

### Prose-only, do NOT restore as rules (39)

- **Japanese aesthetics (16):** fukinsei, yugen, mottainai, kintsugi, gaman, mushin,
  omoiyari, shoshin, shu_ha_ri, jo_ha_kyu, kire, yoin, shakkei, shibumi, miyabi, ikigai.
- **Architecture/design vocabulary (23):** ribbon_windows, passive_solar_design,
  indoor_outdoor_connection, prospect_and_refuge, monumental_form, clean_geometric_lines,
  monochromatic_schemes, photography_over_illustration, local_material_sourcing,
  natural_ventilation, gesamtkunstwerk, unity_of_art_craft, deference, repose, …

Restore these only into persona/voice prompts. As rules they would manufacture law
nothing can check — the exact pathology this audit closes.

## Smells: 227 → 122 absent (53%) — but the distribution is the story

| category | total | absent |
|---|---|---|
| accessibility | 5 | 0 |
| security | 14 | 1 |
| naming | 4 | 1 |
| structural | 11 | 2 |
| refactoring | 8 | 2 |
| observability | 3 | 1 |
| quality | 12 | 3 |
| reliability | 16 | 3 |
| complexity | 10 | 4 |
| aesthetic | 11 | 5 |
| maintainability | 16 | 6 |
| ux | 10 | 7 |
| philosophy | 19 | 16 |
| **design** | **88** | **71** |

The engineering core held; the design/philosophy/ux catalogue did not. 71 of 122 absent
smells are the single `design` category. **Excluding design/philosophy/ux, only 28 of 110
(25%) engineering smells are missing** — far better than the 53% headline.

Highest-value restorations, all mechanically detectable and currently unenforced:
`deep_nesting`, `complex_conditional`, `mixed_abstraction`, `low_cohesion`,
`shared_mutable_state`, `resource_waste`, `hard_to_delete`, `excessive_configuration`,
`unvalidated_input`.

## Linkage integrity

`principle_map.yml` references 72 distinct operations. Against the operations catalog:

| | catalog size | resolved | dangling |
|---|---|---|---|
| before patch `0001` | 9 | 2 | 70 |
| after patch `0001` | 142 | 69 | 3 |

The catalog restoration repaired 67 dangling references — before it, 70 of 72 operations
pointed at nothing (a graph 97% broken, invisible at section level). Strongest evidence
the ops restoration was load-bearing, not cosmetic.

Three remain dangling, HEAD-native (not v110): `flatten_ui`, `prefer_title_type_token`,
`wire_i18n_for_literals` — add to `structural_ops`.

> **Codify note (2026-08-03, `1eaeefec1`):** the operations catalog that resolves these
> 72 ops (`move_method`, `simplify`, …) was not found under `MASTER/` at this SHA — no
> file defines `move_method`, and there is no `patches/` dir. Either patch `0001` is
> unapplied on this branch or the catalog lives outside `MASTER/data`. The before/after
> ops numbers above reflect the *patched* state; **confirm the catalog's location/merge
> status** before acting on the linkage priorities.

## Priority (revised by this audit)

1. **Add the 3 remaining dangling ops** — trivial, closes the graph to 72/72.
2. **9 mechanically-detectable smells** above, starting with `deep_nesting` /
   `complex_conditional`.
3. **`sectionitis_prevention` + `boring_technology`** — checkable, and both name failure
   modes this repo demonstrably has.
4. **Work the 86 `status: gap` principles** — MASTER already lists them; they need
   `rule_ids`, not discovery.
5. Leave the 39 aesthetic/architectural principles as persona prose.
