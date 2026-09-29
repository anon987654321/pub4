# Rails gates

This README describes the executable Rails and MASTER web gate family. The registry in
`MASTER/gates/gates.yml`, the gate code, and the runner output are authoritative.

Assessment: 2026-09-30. Scope: RAILS family (brgen + verticals, amber, bsdports)
and the MASTER web face.

## Current coverage

| Layer | Current state |
|-------|---------------|
| Inventory / ports | implemented; bsdports is part of family inventory |
| Schema / runtime | implemented |
| Source UX floor | implemented, with i18n and accessibility source checks |
| Guest page matrix | implemented across brgen engines, amber, bsdports and MASTER |
| Authenticated mutations | credentialed live journeys are defined in `flows.yml` |
| Mobile browser | live mobile flow plus mutation coverage |
| Keyboard | live tab-order coverage |
| Pixel / visual | live CDP capture where the environment supplies apps and Chrome |
| Screen reader | computed Chrome accessibility-tree gate |
| Server performance | p95 response-time and response-byte budget gate |
| Integrity | mutation, calibration and constitutional coverage |

## Remaining evidence gates

The source and rendered gate machinery now covers the earlier structural gaps. The
remaining work is evidence that depends on credentials, a live box, or real
hardware.

1. **Authenticated journeys** — `flow_journey` now contains explicit signed-in
   checkout, seller, dating-like and Amber wardrobe mutations. They require
   disposable environment credentials and report missing credentials as
   inconclusive rather than green.
2. **Live `:id` coverage** — guest `:id` routes remain unresolved where no safe
   seeded record can exist. `LiveRecordIds` documents those cases instead of
   manufacturing identifiers.
3. **Server performance** — `server_response_budget` now measures p95 response
   time and response bytes across the same guest crawl used by
   `PageInventory`, with budgets in `MASTER/data/limits.yml`.
4. **Screen-reader path** — `accessibility_tree` reads Chrome's computed
   accessibility tree over representative mobile surfaces. It checks for a
   main landmark and names on interactive roles.
5. **Real-device audio** — `MASTER/bin/device-acceptance` is the hardware
   acceptance runner. It checks the declared voice policy, can record and
   transcribe a real Android/Termux microphone window, and can verify that a
   physical iOS device is attached. It does not claim device evidence until the
   command is actually run on that hardware.
6. **Rails payment staging** — checkout/payment provider success remains a
   staging-and-credentials question. The source gates already fail closed around
   provider configuration, seller readiness and callback integrity.

## Gate status

| Layer | Current state |
|-------|---------------|
| Guest page inventory | implemented, including brgen engines, amber, bsdports and MASTER |
| Authenticated mutations | implemented as credentialed live journeys |
| Mobile browser floor | implemented and mutation-tested |
| Screen-reader tree | implemented through Chrome Accessibility CDP |
| Server p95 time/bytes | implemented as `server_response_budget` |
| Pixel regression | implemented; live capture remains environment-dependent |
| Payment e2e | source/staging guards implemented; real provider transaction remains staging evidence |
| Real Android/iOS audio | acceptance runner implemented; physical-device evidence is runtime work |
## Three instrument rules, each paid for

A gate that demands one of several correct outcomes reports the environment as
the tree: amber's `/demo` redirects home without a seeded wardrobe and brgen's
marketplace shows an empty state without listings, so a check that demands the
populated branch reads an empty database as a broken app. Name the set of
correct answers and keep each falsifiable.

A test that runs a gate over this tree and asserts clean proves nothing — it
passes against a gate whose body is `return ok`. Plant the defect, assert red
and named, remove it, assert green, and drive the test once against a gutted
gate.

Check what the instrument opens before believing what it says. A stylesheet
lint that globs a directory misses what the bundle pulls in through `@use` and
`@forward`, and a class extractor that stops at a quote cannot read a Ruby class
value with interpolation in it.

## Perfectionist run recipe

```zsh
# Warm apps first (Falcon), then:
export RBENV_VERSION=4.0.5
ruby MASTER/gates/runner.rb page_simulation flow_journey \
  layout_suite rendered_suite human_walkthrough shared_wiring \
  production generated_asset schema_migration port_inventory \
  constitutional_scan gate_mutation visual_contract

# Optional hard mode (deploy host / CI with Chrome + apps):
GATE_STRICT_INCONCLUSIVE=1 GATE_STRICT_SOFT=1 \
  ruby MASTER/gates/runner.rb rendered_suite page_simulation
```

## What “adequate” means here

| Bar | Status |
|-----|--------|
| Ship without obvious guest dead-ends | **Met** (page_sim + flows + verticals) |
| NN/g floor (status, landmarks, touch, overflow) | **Mostly met** (mobile_flow + reflow + status polish) |
| Pixel-perfect regression on every surface | **Not met** |
| Auth journeys + payment e2e | **Not met** |
| Zero EN under default_locale :nb | **Approaching** (lints 0; residual secondary chrome remains) |

---

Full-matrix user simulation for every full-page Rails surface in the **focus
triangle** (brgen · amber · MASTER web).

## Run

```zsh
# Source checks always; live HTTP when apps listen
ruby MASTER/gates/runner.rb page_simulation

# With the apps up (guest GET matrix): RAILS/bin/triangle up, ports from apps.yml
ruby MASTER/gates/runner.rb page_simulation

# Multi-step journeys (postconditions, redirect honesty)
ruby MASTER/gates/runner.rb flow_journey

# Vertical + secondary host probes (user_flow guest persona)
ruby MASTER/gates/runner.rb user_flow

# Phone viewport journey (44px `--tap-min` chrome, overflow, landmarks, brgen subapps)
ruby MASTER/gates/runner.rb mobile_flow

# Desktop tab order
ruby MASTER/gates/runner.rb keyboard_flow
```

## Inventory

Discovered from non-partial `*.html.erb` views + MASTER public HTML.

| App    | Pages | Guest | Auth |
|--------|------:|------:|-----:|
| brgen  |    85 |    ~ |   ~ |
| amber  |    47 |    ~ |   ~ |
| master |     5 |     5 |   0 |
| **Σ**  | **137** |  |  |

Snapshot: `gates/data/page_sim_inventory.yml` (regenerated each run). Report:
`gates/data/page_sim_report.yml`.

## What each page is checked for

### Source (always)

| Check | Principle |
|-------|-----------|
| Page identity (`content_for :title` / `h1` / `h2`) | hierarchy |
| `shared/empty_state` has `action:` (or opt-out) | NO_DEAD_ENDS |
| Interactive affordance (links / forms / search) | good_design_is_useful |
| Guest surfaces without hard auth-wall copy | clarity / guest_open |
| Form fields with labels / aria-label | accessibility |
| MASTER face + mission-control landmarks | triangle a11y floor |

### Live (when port open)

Soft-guest HTTP GET of every **guest**, **non-parameterised** path:

- Status 200–399
- No Exception / Routing Error chrome
- `main` / skip / face root landmarks
- Guest-open: no “Sign in to continue”
- Title or h1 present

Auth-only and `:id` show/edit pages need a seeded session or fixture id — source
covers their templates; live matrix targets guest browse.

## Multi-step journeys (`flows.yml`)

Beyond single-page GETs:

- Marketplace browse + cart honesty
- Sign-in reachable from home
- Live guest-open
- Nearby ↔ Live loop
- Search empty + query
- Communities, channels, messenger
- Dating discover
- Playlist / TV / takeaway / maps roots
- Amber wardrobe, feed, demo, AI entry

## Geometry / keyboard / visual

`BrgenVerticalSurfaces` now includes secondary apex paths (nearby, communities,
search, channels, conversations, marketplace deals/sell) so `rendered_suite`
walks them when Chrome is available. Amber feed / outfits / demo are in
`geometry_surfaces.yml`.

## Polish loop

Simulation is not report-only. Soft findings (residual EN CTAs, missing titles,
form labels) are fixed in the same pass:

1. `ruby MASTER/gates/runner.rb page_simulation`
2. Address soft/hard findings (i18n keys in `en.yml` + `nb.yml`, wire `t()`)
3. Re-run until source matrix is clean
4. When ports are open, clear live findings the same way

### Polish already landed from the matrix

| Area | What |
|------|------|
| Amber wardrobe hub | Full i18n: chips, lifecycle filters, tool groups |
| Amber feed / analytics / shopping / live sessions / capsule | EN chrome → `t()` |
| Brgen posts index/show/edit | Sort tabs, vote a11y, share, about, form labels |
| Brgen channels, home title, places, messages, dating profiles | i18n + headings |
| Brgen notifications + playlist party | Open/mark-read, party chat form label |
| Shared Edit/Cancel/Open CTAs | Batch `actions.edit` / `cancel` / `open` across triangle |
| Cart | Full i18n + confirm on send-all-offers |
| Status (#1) | live-search + autosave strings via `status.*`; flash `aria-live` |
| Freedom (#3) | Amber archive → flash undo restore CTA |
| Efficiency (#6/#7) | First-visit hotkey coach; i18n help; coach on brgen+amber |
| Errors (#9) | Branded 404/422/500 with home/Live/wardrobe CTAs |
| keyboard_flow | Prefers live/wardrobe/feed over auth-only surfaces |

## Status notes

- **Source floor**: 137/137 templates simulated; hard + residual-EN soft = 0
  when last clean.
- **Live matrix**: requires Falcon (or equivalent) on the triangle ports.
- **bsdports** intentionally out of focus triangle; still has its own
  flow/geometry rows.
