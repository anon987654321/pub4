# Page UI/UX simulations

Full-matrix user simulation for every full-page Rails surface in the **focus
triangle** (brgen · amber · MASTER web).

## Run

```zsh
# Source checks always; live HTTP when apps listen
ruby RAILS/gates/runner.rb page_simulation

# With Falcon up (guest GET matrix)
# brgen :38182  amber :61352  MASTER web :53187
ruby RAILS/gates/runner.rb page_simulation

# Multi-step journeys (postconditions, redirect honesty)
ruby RAILS/gates/runner.rb flow_journey

# Vertical + secondary host probes (user_flow guest persona)
ruby RAILS/gates/runner.rb user_flow

# Phone viewport journey (44px `--tap-min` chrome, overflow, landmarks, brgen subapps)
ruby RAILS/gates/runner.rb mobile_flow

# Desktop tab order
ruby RAILS/gates/runner.rb keyboard_flow
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

1. `ruby RAILS/gates/runner.rb page_simulation`
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
