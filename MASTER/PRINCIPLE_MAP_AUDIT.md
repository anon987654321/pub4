# Principle-map gap audit: v110 → HEAD (key-by-key)

## Update 2026-08-07 / applied 2026-08-16

Closed 8 gaps by linking existing kernel/unit rules (no new scanners):
`circuit_breaker`, `least_privilege`, `secure_by_default`,
`composition_over_inheritance`, `boy_scout_rule`, `durability`,
`user_control`, `sovereignty`.

Remaining critical gaps (`pledge_unveil`, `secrets_rotation`, `audit_logging`)
need real evidence sources, not empty `rule_ids`.

---

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
| live tree (`rules.yml` → `structural_ops.ops`) | 9 | 2 | **70** |
| hypothetical, patch `0001` applied | 142 | 69 | 3 |

**Resolved 2026-08-03 — patch `0001` is unapplied, everywhere.** The catalog note below
asked where the 142-op catalog lives. It doesn't: no file in the repo defines
`move_method` or `clarify_purpose`, on any branch, at any SHA. The only operations
catalog in the tree is `rules.yml`'s `structural_ops.ops` with **9** ops, of which
exactly two — `delete` and `decouple` — resolve. **70 of 72 dangle today.** The
before/after numbers were computed, not shipped.

The 142 reconstructs as the v110 fossil's 136 operations plus 6 HEAD-native. That fossil
is recoverable: `MASTER/data/archive/master.v3.yml`, deleted at `a81006e30` (2026-07-25)
as an "unreferenced legacy config snapshot". Restoring its operations does resolve 69/72,
leaving exactly `flatten_ui`, `prefer_title_type_token`, `wire_i18n_for_literals`.

But the fossil also settles what v110's linkage was worth. Its smells are bare keys with
nil values (`deep_nesting:` — no regex, no severity, no detector) and its operations are
one-line glosses (`rename: "reveal intent"`). The meta's "every smell has a detector,
operations never orphaned" was aspiration, not structure. **v110 was a vocabulary; HEAD is
executable rules.** The loss runs opposite to how this audit reads it.

Correspondingly, `operation:` is inert at HEAD — `PrincipleMap::Queries#operation_for` has
zero callers in `lib/`, `core/` or `bin/`. Restoring the catalog closes the reference graph
on paper while nothing reads it. Do it only alongside a consumer, or delete the field.

## Priority (revised by this audit)

Reordered 2026-08-03 after measuring against the live registry rather than against rule
names. The original list is kept struck through, because *why* it was wrong is the
reusable lesson: it matched v110's vocabulary against 225 declarative rule ids in
`data/rules.yml` and never loaded the registry, which holds **180 executable rule classes** —
a different population. Nine of them exist only in Ruby, and they are precisely the
mechanical ones the audit called absent.

1. ~~Add the 3 remaining dangling ops~~ → **70 dangle, not 3**, and `operation:` has no
   reader. Decide whether the field earns a consumer before restoring 136 glosses to feed
   it.
2. ~~9 mechanically-detectable smells~~ → **6 already ship**: `deep_nesting` is
   `NESTING_DEPTH` (Prism AST, depth > 4), `complex_conditional` is
   `CYCLOMATIC_COMPLEXITY` (> 10), `mixed_abstraction` is `ONE_ABSTRACTION_LEVEL`,
   `unvalidated_input` is `DEFENSIVE_INPUT`/`PARSE_DONT_VALIDATE`/`COMPLETE_MEDIATION`,
   `shared_mutable_state` is `NO_HIDDEN_GLOBAL_STATE`/`IMMUTABLE`,
   `excessive_configuration` is `CONVENTION_OVER_CONFIG`. Genuinely missing:
   `hard_to_delete`, `low_cohesion`, `resource_waste`.
3. ~~`sectionitis_prevention` + `boring_technology`~~ → `sectionitis_prevention` **ships**
   as `CONFIG_HIERARCHY` (YAML/JSON depth > 4, duplicate keys, top-level key ceiling).
   `boring_technology` (dependency churn) is a real gap.
4. **Reconciliation, done 2026-08-03 (`a4d37f5da`)** — 32 of the 86 gaps were already
   enforced under other names; `covered` 51 → 83, `gap` 86 → 51, integrity still 0.
   Three entries (`knowledge_biases`, `output_biases`, `patterns`) were fossil
   `biases:`/`patterns:` section keys swept into `principles:` by the merge, and were
   dropped: 138 → 135.
5. **Build the two coherent clusters in the remaining 51.** Security/OpenBSD (6) and test
   discipline (5) — *no registered rule touches tests at all*. Started with
   `STRONG_PARAMETERS` (`6bdfdaf39`).
6. Leave the ~30 architecture/aesthetic principles as persona prose. Unchanged, and the
   audit's soundest call.

The reverse invariant is now gated. `rules.yml:190` declares "every registered rule id
traces to a `principle_map` entry". Before reconciliation 45 of 180 did; after, 79. It is
violated **101 times**, and `rake lint:principle_trace` holds that number as a ratcheting
ceiling in `rake audit` — `RATCHET=1` records a new low, and raising it takes a commit that
says why. Measured 2026-08-03: `101/101 of 181 registered rules untraced`, so it passes with
zero headroom and the next unmapped rule turns the audit red.

An earlier revision of this line said "nothing checks it". That was written before the
ratchet landed in the same session and was stale on arrival.
