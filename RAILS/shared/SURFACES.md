# SURFACES.md — the consistency contract

The four surfaces (brgen + verticals, amber, bsdports, the MASTER face) are one
family in four dialects. This table is where a new surface starts — pick from
it, don't invent beside it. Decisions recorded 2026-08-21 at the close of the
consistency campaign; enforcement lives in `visual_contract_lint`,
`css_coverage_lint`, `breakpoint_lint`, `empty_state_lint` and
`MASTER/tools/design_baseline.rb`, all ratcheted.

## Dialects

| Surface | Palette | Radius | Type | Theme |
|---|---|---|---|---|
| brgen (+verticals) | brgen_old grayscale, per-vertical accents (3-slot map) | 4/8/12/8 | Inter | dark default, `data-theme` toggle |
| amber | luxury warm paper | –/6/10/14 | Inter + editorial faces (amber-only) | light default, `data-theme` toggle |
| bsdports | wscons terminal green | 0 | system mono | **one-theme by design** — no toggle until decided otherwise |
| MASTER face | black + lavender `--c-*` | 0 | JetBrains Mono | **one-theme black by design** |

- Per-surface typefaces are dialect identity, not drift — but a fifth face is a
  decision, not an accident. amber's editorial fonts never leak into shared
  partials.
- The theme mechanism is ONE thing everywhere it exists: the shared
  `theme_toggle` + `theme_bootstrap` partials writing
  `documentElement.dataset.theme`; CSS reads `:root[data-theme]`. The
  checkbox-sibling CSS lane is retired (2026-08-21, proven live over CDP).

## Chrome grammar

| Surface | Primary nav | Bottom bar | Brand mark | Search |
|---|---|---|---|---|
| brgen core | swipe-reveal swiper (deliberate, hidden at rest) | mobile tab bar | shared `_brand_mark`, fixed top-left, armored | live_search |
| marketplace | Amazon-style nav bar | inherits | same | nav-bar search (yep surface) |
| playlist | immersive stage + transport bar (publishes `--tab-bar-h`) | transport | same | — |
| dating / tv / maps / messenger | immersive or grid, per `_vertical_shell` | varies | same | maps has overlay search |
| amber | sidebar + tab bar | tab bar | shared mark | live_search |
| bsdports | top nav (no swipe grammar — index-density identity) | none, deliberate | shared mark | live_search |
| face | none (single chat surface) | — | `.top-left-logo` (align to `_brand_mark` geometry: queued) | — |

- Immersive vs browsable is load-bearing and CSS-encoded
  (`body[class*="vertical-"]` hides feed chrome). Naming it in markup
  (`data-shell=`) is a queued refinement, not yet built.
- Any bar at the bottom edge publishes its height into `--tab-bar-h` so
  floating widgets clear it (playlist's transport is the model).

## Component families (closed sets)

- **Buttons** — dash-spelled, one family in `_zen_shell.scss`:
  `btn` base + compound variants `.btn.btn-primary/-ghost/-danger/-sm`, plus
  `btn-link`, `btn-block`, `btn-share`. Variants are compound (0-2-0) so an
  app's later `.btn` base is a dialect skin that can never beat them; ghost ink
  is `inherit` (wscons stays green). `btn_vocabulary` lint holds the set at
  zero strays. brgen's accent-painted base is its dialect; amber's small-button
  overrides ride dual solo+compound selectors.
- **Icons** — `Shared::UiHelper#icon` + the sprite partial, rendered by all
  three app layouts behind `config.x.icon_sprite` (2026-08-21; amber's theme
  toggle had been referencing symbols it never included). The face's icons are
  queued for the same namespace.
- **Empty states** — `shared/empty_state` with `action:` CTA, both lint
  directions at zero. The `○` glyph is a queued dialect slot.
- **Cards** — `_post_card` (card/prose variants) is the anatomy; `_feed_card`
  is the compact row. Wider adoption (amber posts, engine cards onto tv's
  aspect-poster grammar) is the recorded refactor queue below.
- **Scrims** — `--scrim-45..72`; unification to fewer densities awaits the
  operator's eye.
- **Hairlines on dark glass** — playlist's `--glass`/`--edge-*`; the face's
  `--border-faint/soft/strong` is the same idea awaiting the shared edge scale.

## Fences (deliberate, with reasons where they live)

- Popover arrow drop-shadow: the author's recorded 2026-07-21 exception — the
  one shadow in the fleet.
- `chat_upload.css` stays a separate file: it is deliberately lazy-loaded
  (preload + JS flip + noscript), not sprawl.
- `--x-text` and the face's `--c-*` namespace: read by the *generated* face
  bundles; renaming means editing `face.part*.txt` and regenerating — a face
  session's work, queued, not casual.
- wscons and the face are one-theme; brgen ghosts inherit ink; the deliberate
  max-width bands carry `scan: intentional` markers inline.

## Queued refactors (recorded, ratchet-held, unscheduled)

Token: face joins fleet token names (fenced: the --c-*/--x-text namespace is
read by the GENERATED bundles — a face.part*.txt session, and the local face
did not boot under triangle, so no tap-test is currently possible); shared
edge scale; radius-scale parameter per dialect; scrim unification (operator's
eye). Components: media-card, card-grid, chat anatomy, event-row, trust strip
— each needs a second real consumer or a sitting of its own.
**Refuted on examination (2026-08-21): purchasable-row** — takeaway's
form-quantity row, the cart's remove-action row and the listing card share a
phrase (name · price), not an anatomy; one partial serving all three would be
a parameter soup shallower than three clear local rows. The face's 52-finding
debt closed the same day (26 were a line-blind REDUCED_MOTION twin filing
against face.css's own reset; the primer fade capped at 300ms; the rest were
fences stated inline).
