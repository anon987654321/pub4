# Gate suite adequacy (perfectionist bar)

Assessment date: 2026-08-01. Scope: RAILS family (brgen + verticals, amber,
bsdports) + MASTER web UI.

## Verdict

**Strong professional floor. Not yet “perfectionist complete.”**

What we have is among the denser Rails UI gate suites: source ratchets,
multi-step journeys, full-page inventory sims, geometry/reflow, keyboard +
mobile floors, mutation tests. A perfectionist still needs authenticated
personas, denser residual-EN chrome, reliable CDP under load, and MASTER face in
every browser leaf.

## Coverage map

| Layer | Gates | Adequacy |
|-------|--------|----------|
| Inventory / ports | apps_yml, port_inventory, shared_wiring | Solid |
| Schema / runtime | schema_migration, phantom_foreign_keys, rails_runtime | Solid |
| Design constitution | css_constitution, dialect_purity, payment_honesty, design_metrics | Strong |
| Source UX floor | surface_schema, chrome_i18n/empty lints, human_walkthrough, user_flow | Strong |
| Full-page matrix | **page_simulation** (137 triangle pages + bsdports when wired) | Strong source; live needs warm Falcon |
| Multi-step journeys | **flow_journey** (brgen verticals depth + amber + master) | Strong guest; no auth journeys |
| Phone UX | **mobile_flow**, reflow, geometry mobile | Good floor; CDP flake → inconclusive |
| Keyboard | **keyboard_flow** | Good; desktop-first |
| Pixel / visual | visual_contract, layout_snapshot, visual_quality | Capture matrix exists; not every page |
| MASTER web | master_web_assets, production, page_sim face/dashboard | Face OK; static offline soft |
| Integrity | gate_mutation, calibration, constitutional_scan | Solid |

## Gaps a perfectionist would still flag

1. **Authenticated personas** — no signed-in walk of cart checkout, dating
   matches, sell form submit, amber wardrobe mutations.
2. **Residual EN chrome** — measured 2026-08-01 instead of guessed at.
   `chrome_i18n_lint` now has an `aria_label` rule (both `aria-label="…"` and
   `aria: { label: "…" }`) and reports per kind: empty titles 0, search
   placeholders 0, hardcoded aria-labels **172** across the three apps and the
   shared engine. The aria baseline is 172 rather than 0 because closing it
   needs Norwegian copy, not a regex; it may only ratchet down, and
   `RAILS/test/chrome_i18n_lint_test.rb` fails both when a kind exceeds its
   baseline and when a baseline has been beaten and not lowered. Until then, a
   screen-reader user on `:nb` hears English for those 172 labels — which is the
   gap, now with a number on it.
3. **CDP reliability** — long rendered_suite + cold Falcon → timeouts;
   mobile/keyboard must not green-wash (inconclusive when &lt;3 surfaces
   measured).
4. **MASTER face browser leaf** — not first-class in mobile_flow preferred set /
   geometry_surfaces.
5. **Auth + :id pages** — page_sim source-only for show/edit; no seeded live
   IDs.
6. **visual_contract capture** — needs `VISUAL_CAPTURE=1` + running apps;
   default run only validates matrix shape.
7. **bsdports** — out of product focus triangle but still a Rails app; must
   appear in family `--all`.
8. **No network/perf budget** — no LCP/INP or request waterfall gate.
9. **No screen-reader path** — landmarks yes; no axe/full a11y tree walk beyond
   visual_contract capture helpers.
10. **gate_mutation** does not prove mobile_flow / page_simulation catch defects
    yet.

## Perfectionist run recipe

```zsh
# Warm apps first (Falcon), then:
export RBENV_VERSION=3.4.9
ruby RAILS/gates/runner.rb page_simulation flow_journey \
  layout_suite rendered_suite human_walkthrough shared_wiring \
  production generated_asset schema_migration port_inventory \
  constitutional_scan gate_mutation visual_contract

# Optional hard mode (deploy host / CI with Chrome + apps):
GATE_STRICT_INCONCLUSIVE=1 GATE_STRICT_SOFT=1 \
  ruby RAILS/gates/runner.rb rendered_suite page_simulation
```

## What “adequate” means here

| Bar | Status |
|-----|--------|
| Ship without obvious guest dead-ends | **Met** (page_sim + flows + verticals) |
| NN/g floor (status, landmarks, touch, overflow) | **Mostly met** (mobile_flow + reflow + status polish) |
| Pixel-perfect regression on every surface | **Not met** |
| Auth journeys + payment e2e | **Not met** |
| Zero EN under default_locale :nb | **Approaching** (lints 0; residual secondary chrome remains) |
