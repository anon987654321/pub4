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
- Any bar at the bottom edge publishes its height into `--tab-bar-h` so floating
  widgets clear it (playlist's transport is the model).

## Component families (closed sets)

- **Buttons** — dash-spelled, one family in `_zen_shell.scss`: `btn` base +
  compound variants `.btn.btn-primary/-ghost/-danger/-sm`, plus `btn-link`,
  `btn-block`, `btn-share`. Variants are compound (`0-2-0`) so an app's later
  `.btn` base is a dialect skin that can never beat them; ghost ink is `inherit`
  (wscons stays green). `btn_vocabulary` lint holds the set at zero strays.
  brgen's accent-painted base is its dialect; amber's small-button overrides
  ride dual solo+compound selectors.
- **Icons** — `Shared::UiHelper#icon` + the sprite partial, rendered by all
  three app layouts behind `config.x.icon_sprite` (2026-08-21; amber's theme
  toggle had been referencing symbols it never included). The face's icons are
  queued for the same namespace.
- **Empty states** — `shared/empty_state` with `action:` CTA, both lint
  directions at zero. The `○` glyph is a queued dialect slot.
- **Cards** — `_post_card` (card/prose variants) is the anatomy; `_feed_card` is
  the compact row. Wider adoption (amber posts, engine cards onto tv's
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

Token: face joins fleet token names (a face.part*.txt session — the
--c-*/--x-text namespace is read by the GENERATED bundles. The tap-test fence
LIFTED 2026-08-22: the local face failing to boot under triangle was nothing
deeper than MASTER/web's bundle never installed under the pinned 3.4.9 — one
bundle install, four surfaces up, face answers 200); shared edge scale;
radius-scale parameter per dialect; scrim unification (operator's eye).
Components: card-grid still needs a second real consumer.

The component sitting ran 2026-08-21; most of the queue refuted the
purchasable-row way:

- **media-card, landed where it was real**: deals/_card and listings/_card
  carried one byte-similar image slot (photo/placeholder/badge, same class
  family, same responsive widths) — now `marketplace/_card_media`. The card
  BODIES stay local (a deal leads with its discount, a listing with its meta
  row). Cross-engine (maps place-card, tv-card, event-card) refuted: duration
  overlays, time chips and address lines are structural differences — a phrase
  in common, not an anatomy.
- **chat anatomy refuted**: the four message partials are four animals — an
  87-line IRC/DM hybrid with receipts and expiry, a one-line party message, a
  deliberately minimal stream-chat line with its own broadcast contract, and
  amber's to/from letter. Who + body + when is a phrase.
- **event-row refuted**: events/_event and activity_events/_event render
  different models (Event vs polymorphic activity); nothing to unify.
- **trust strip dropped from the queue**: no view consumer exists at all —
  TrustSignal/TrustScore are model/service only. A component with zero consumers
  is not queued, it is unbuilt. **Refuted on examination (2026-08-21):
  purchasable-row** — takeaway's form-quantity row, the cart's remove-action row
  and the listing card share a phrase (name · price), not an anatomy; one
  partial serving all three would be a parameter soup shallower than three clear
  local rows. The face's 52-finding debt closed the same day (26 were a
  line-blind REDUCED_MOTION twin filing against face.css's own reset; the primer
  fade capped at 300ms; the rest were fences stated inline).

## Tap-target sweep (gates/probes/tap_target_probe.rb) — first run 2026-08-22

The 2026-08-17 hand-found pair is an instrument now: every interactive element
on 7 pages against the fleet's own --tap-min, in a 390x844 mobile viewport over
CDP. Landed from the first run: face clean (its --tap-min was CITED but never
defined — the button drew at 18px; the drawn square is a ::before inside a 44px
button now), legal footer links grown by invisible padding, brgen's shadow copy
of _site_legal_footer deleted (it was masking the shared one), the theme
toggle's label carries the 44px box.

Verdicts, recorded not forced:
- brgen author links (42x21) — feed density vs tap size is the operator's call;
  the same invisible-padding trick would work if wanted.
- amber nav row (35px) and author links — amber's active session's design.
- bsdports .port-name rows (12px) — the index-density identity; one line per
  port IS the surface. Deliberate, stays.

## Stylesheet size budget (auditor css_file_size, 200 lines) — stance 2026-08-22

Ten sheets exceed it. Not one queue: _zen_shell (474) and _minimal (459) are
BASE LAYERS — one file is their design, splitting them scatters the cascade
story; _dialect_tokens (200+) holds tokens AND theme mixins and is the one with
a real seam (tokens vs mixins) if anyone splits anything. face.css (1282) is the
whole face by construction. The app sheets (_chrome_polish 324, _marketplace
251, _vertical_playlist 378, amber _brand 378) are section-seamed and splittable
when their surfaces are next open; the auditor keeps counting so none of this
grows silently.
