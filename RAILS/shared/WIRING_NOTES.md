# Shared Rails wiring notes

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem
(`pub4-shared`) loaded via local path in each app Gemfile.

brgen is one process with many hosts, not one site: city apex = feed,
`engines/*` = subdomain verticals (`dating.brgen.no`,
`marketplace.lsangeles.com`). Messenger is host routes. `ai.brgen.no` is MASTER.
Topology: `RAILS/brgen/AGENTS.md`.

## Visual system — one `application.css` per app

Each app compiles a **single** `app/assets/builds/application.css` via Dart
Sass. No separate `tokens.css`, `animations.css`, or `minimal-ui*.css` links in
layouts.

**Protected file:** only `application.scss` per `limits.yml` →
`frontend_protection`. Prefer `@use "stack"` plus existing domain partials
(brgen pattern); avoid new `_appname.scss` sprawl when product CSS fits the
entry or an existing partial.

**Stack entry** (top of every `application.scss`):

```scss
@use "stack" as *;
```

`stack` forwards: `_minimal`, `_tokens`, `_animations`, `_zen_shell` (offline
page, install prompt, x.com-shell primitives).

**Brgen** adds product partials after the stack (`_root`, `_canvas`, `_shell`,
…). **Standalone apps** add a thin product block below `@use "stack"`.

**Static exceptions:**
- `shared/public/styles/errors.css` — Rails default error pages only
- brgen: `face.css`, `lightgallery.css` — product vendor assets
- External font CDNs where apps use them (amber)

**Tooling:** `dartsass-rails`, `Shared::FrontendAuditor` (0-warning target on
app-owned paths), `bin/rails dartsass:build` in CI.

## Hotwire / Stimulus baseline

**JS entrypoints** (`shared/frontend/`):
- `hotwire.js` — Turbo, theme-meta, PWA SW, nav-reveal (idempotent),
  minimal-gesture boot
- `stimulus_boot.js` — full @stimulus-components fleet (incl.
  password-visibility, nested-form, carousel, read-more, checkbox-select-all),
  StimulusReflex, Futurism, live-search, offline-page, install-prompt,
  theme-toggle
- `Shared::StimulusFormHelper` — `character_counter_field`,
  `password_visibility_field`, `read_more`
- Gate: `ruby RAILS/gates/runner.rb stimulus_components` (no legacy
  `char-counter` / duplicate controllers)
- `theme_meta.js`, `nav_reveal.js`, `live_search_controller.js`, …

**Per-app wiring:**

```js
// app/javascript/application.js
import "pub4/hotwire"
import "controllers"
```

```ruby
# config/importmap.rb
eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)
```

**Live search:** `live_search_index` helper + `Shared::LiveSearchable` — rolled
out on all index views.

**Mailers:** `render "layouts/mailer_styles"` (shared partial; inline `<style>`
required for email clients).

## Social endpoints

Amber and brgen eval `shared/config/routes/social.rb` (notifications, reactions,
reports). BSDports intentionally omits those routes because its schema has no
social tables.

**Brgen** mounts equivalent routes inline; uses city-specific
`NotificationsController` (grouped inbox) and `ModerationReport` for reports.
Reactions use `Shared::ReactionToggle`.

## Shared concerns

Models: `Shared::Reactable`, `Followable`, `Votable`, `Commentable`,
`Notifiable`, `ActivityTrackable`, `GeoLocatable`, `StrictSafeAssociations`.

**Strict loading is on everywhere — mind the after-write reads.**
`ApplicationRecord` sets `strict_loading_by_default = true` for *all*
environments. Only `development.rb` downgrades a violation to a log line
(`action_on_strict_loading_violation = :log`); test and production **raise**,
because that is Rails' default.

That combination traps state-changing methods that notify someone or emit
activity: they `update!` first, then read a `belongs_to` to find the recipient.
On a record loaded by id — controller action, PSP webhook, background job —
nothing is preloaded, so the read raises *after* the write has committed. The
state change sticks, the notification is silently lost, and the caller gets a
500. Retries then no-op because the guard (`payable?`, `may_transition_to?`) is
already satisfied.

Fixed instances (2026-07-27): `Shared::ActivityTrackable#tracks_activity`
resolved `actor:` with a bare `public_send` inside `after_commit`, *outside*
`record_activity!`'s rescue — this affected all 38 models passing `actor:`, and
every one with an `updated:` event. Also
`Marketplace::Order#mark_paid!/accept!/decline!`,
`Takeaway::Order#transition_to!/calculate_totals!`, the `Tv` activity emitters,
and the `listing_owner`/`restaurant_owner`/`channel_owner` actor delegates.

Use `strict_safe(:assoc)` / `strict_safe_attribute(:assoc, :column)` from
`Shared::StrictSafeAssociations` in those paths. It is **not** a licence to skip
preloading — `includes` at the query site is still correct and is what stops the
N+1 strict loading exists to catch. This is the safety net for paths where a
dropped notification is worse than an extra `SELECT`. Actor resolution now
degrades to `nil` rather than raising: analytics must never be why a write
fails.

**Commentable:** brgen and amber use polymorphic `comments` +
`Shared::Commentable` on `Post`.

**Deferred DRY:** brgen still has local `NotificationsController` and
`VotesController` vs shared stubs (see
brgen/app/controllers/{notifications,votes}_controller.rb headers); Follow
schema differs across apps. Promote when city inbox grouping and vote karma
side-effects are unified. Controllers carry comments linking here.

**Notification model:** brgen keeps `Notification` (not `Shared::Notification`)
on the same `notifications` table. Brgen adds `title`/`body` presenters, a
`match` kind for dating, and Turbo broadcasts to `brgen:notifications:*`.
Shared::Notification is the thin engine stub for apps that eval
`shared/config/routes/social.rb`. Same table, different presentation contract —
duplication beats the wrong abstraction until inbox grouping unifies.

Controllers: `Shared::LiveSearchable`, `StructuredEvents`, `MediaGuard`,
`ActorIdentity`.

Emit activity via `Shared::EventEmitter` / `include Shared::StructuredEvents`
for unified graph + Turbo Stream consumers.

## CI gate (per app)

```bash
bin/rails dartsass:build
bundle exec ruby -e 'require "./config/environment"; require "importmap/commands"; Importmap::Commands.start(%w[audit])'
bin/rails test
```

Family-level: `ruby RAILS/test/pwa_design_contract_test.rb`, `ruby
RAILS/test/design_contract_test.rb`, `ruby
RAILS/test/shared_social_routes_test.rb`, `ruby RAILS/gates/runner.rb
frontend_production`.

## x.com parity recovery (2026-07-20)

Recovered from deleted execute-plan stack (tags: `recover/x-parity-stack`,
`recover/x-modal-sheet`) without full merge.

| Piece | Location |
|-------|----------|
| Contract tests | `RAILS/test/design_contract_test.rb`, `shared/test/lib/design_tokens_test.rb` |
| Web vitals (1% sample) | `shared/frontend/hotwire.js` → `POST /web_vitals` (`WebVitalsController`, `fleet.rb`) |
| Bottom sheet | `shared/frontend/bottom_sheet_controller.js` (`pub4/bottom_sheet`) |
| Modal / sheet CSS | `shared/app/assets/stylesheets/_modal.scss` (via `@forward "modal"` in `_stack.scss`) |
| Action bar + icons | `shared/_action_bar`, `shared/_icon`, `shared/icons/*` |
| UI helper | `Shared::UiHelper` (engine initializer `shared.ui_helper`) |
| Theme FOUC | `shared/_theme_bootstrap` + `theme_toggle` sets `document.documentElement.dataset.theme` |

**Not recovered wholesale:** full `_shell` layout rewrite for all apps (main
layouts already diverge). Pull shell partials only when a product explicitly
adopts them.

**Gates (from repo root):**

```bash
ruby RAILS/test/design_contract_test.rb
ruby RAILS/shared/test/lib/design_tokens_test.rb
ruby RAILS/tools/build_all_css.rb --check
ruby RAILS/gates/runner.rb frontend_auditor
```

## Who owns a rendered value (2026-08-11)

The line an agent kept having to guess at, so it is written down. It was guessed
twice on 2026-08-11 alone: a `border-color: #fff` that put `magic_hex` over its
ceiling, and six media queries where one width was both a floor and a ceiling.

**An agent may not choose or change a rendered value.** Not a colour, not a
breakpoint edge, not a radius, not a layout. The operator is a trained architect
and the apparent oddities are usually decisions — the swipe-reveal nav is
deliberate, the flat pass that stripped every box-shadow is deliberate, the
`brgen-old-*` grayscale is deliberate. "It looks wrong to me" is not evidence.

**What an agent may do instead, in preference order:**

1. **Add a token, and reference it.** A named entry in `design_tokens.yml` with
   the count of sites that justify it is an addition, not a change: the rendered
   value is identical the moment every site points at it.
2. **Add a gate.** A number that can only fall is worth more than a fix, because
   it holds after the session ends. `Pub4::BreakpointLint` exists for exactly
   this.
3. **Fix an ambiguity, not an aesthetic.** Two rules that both match at one
   exact viewport width have no intended outcome — bundle order decides.
   Collapsing that is repairing an undefined state, and it still gets said out
   loud in the commit.
4. **Record the finding and stop.** A ceiling raise with the reason in the file,
   naming the commit that caused it and the decision it is waiting on, is a
   legitimate outcome. It leaves the gate measuring everything else.

**Never** substitute a token whose value differs from the literal it replaces,
on the grounds that it is "more correct". That is a colour change wearing a
refactor's clothes.

## Visual design system (2026-07-19)

**Reference:** x.com interaction patterns. Source of truth:
`shared/design_tokens.yml`,
`shared/app/assets/stylesheets/_dialect_tokens.scss`, `_shell.scss`. amber/brgen
inherit via `stack` / `stack_brgen` → `_tokens.scss` → `_dialect_tokens.scss`.

**A declared dialect is not a worn one.** `_dialect_tokens.scss` declares the
mixins; what an app renders is whichever `:root` block wins in its bundle. Read
the second table before the first — until 2026-08-10 this section listed only
the first, and so described brgen in a palette and radius scale it had left.

**Declared (do not merge casually):**
| Mixin | Radius (xs/sm/md/card·lg) | Notes |
|---|---|---|
| `dark-tokens` / `light-tokens` | 4/8/12/16 | Graphite/indigo, parameterised |
| `luxury-*-tokens` | –/6/10/14 | Warm paper |
| `brgen-old-*-tokens` | 4/8/12/**8** | True grayscale, no accent hue |

**Worn at `:root` (verified against `builds/application.css`, 2026-08-10):**
| App | Dialect | Dark → light mechanism |
|---|---|---|
| brgen (+ verticals) | `brgen_old` | `:root` → `#dark-toggle:checked ~ .theme-root` |
| amber | `luxury` | `_variables.scss`, both halves |
| bsdports | `openbsd_wscons`, all radii **0** | Inline `:root` in its own `application.scss` — *not* a mixin here |
| MASTER web face | `face_root`, radius 0 | `MASTER/web`, outside this tree |

**Declared is not worn, third correction (2026-08-26).**
`openbsd_wscons.text_secondary` has now been wrong three times, and the second
correction caused the third. It said `#3d7a3d`; that was corrected to `#63c363`
on the reasoning that "a later `:root` sets `--text-secondary: var(--text)`".
That later `:root` is inside `@media (prefers-contrast: more)` — the
high-contrast override, not the default. A browser with default settings paints
`#499149` on 45 elements of the ports index against `#63c363` on 219, so the
dialect does have a secondary tier and it ships at 5.43:1: above AA, below the
AAA `style.yml` declares.

The instrument agreed with the wrong reading, which is why the note survived two
passes. `DesignMetrics.winning_property_values` kept only the last bare `:root`
declaration of a property, and a `:root` inside `@media` has the same selector
text as one outside it — so the conditional value shadowed the default and the
gate reported the real colour as "never reaches a pixel". It reads at-rule
nesting now; eight token pairs that were being skipped are counted, and
`contrast_below_aaa` moved 39 → 43 without the ceiling moving. That direction is
the point: a token naming the painted value makes the pair visible to every
measurement, one naming an aspiration hides it.

**The AI embed keeps its own dialect (2026-08-26).** brgen's guest home carries
MASTER's monospace voice inside the social dialect's sans, which reads as two
type systems meeting in one viewport. It stays, and this is the decision rather
than the accident: the chip is a doorway into MASTER, `ai.brgen.no` is a
different surface with a different contract, and the mono *is* how that surface
identifies itself — the same reason bsdports and the face are CRT-mono and brgen
social is not. What would be wrong is the mono spreading into feed chrome; it is
scoped to the embed and should stay there.

**brgen's actual dark palette** — grayscale, and deliberately so (`_root.scss`:
"this app's identity is the direction itself, not a rotated hue"):
- bg `#000000`, surface/elevated `#1a1a1a`, search `#222222`
- text `#e0e0e0`, secondary `#969696`, border `#333333`
- accent `#f2f2f2`, danger `#e46151`; `--radius-card`/`-lg` `8px`
- Per-vertical accents still apply on `body.vertical-*` (marketplace `#98876e`,
  tv `#dc635c`, dating `#00d4aa`, takeaway `#e07b39`, playlist `#12b6c4`, maps
  `#5b8fd4`, messenger `#6b7fd7`)

**The social indigo palette is still compiled into brgen** (`#17161c`/`#f7f6fa`/
`#897dda`), because `stack_brgen` forwards `_tokens.scss`. Verified against the
built bundle 2026-08-21: it is outranked everywhere it appears, and the "two
light themes" this section used to warn about is fixed — `_root.scss` restates
brgen-old under `:root[data-theme="light"]` **and** under `@media
(prefers-color-scheme: light)`, each emitted after the indigo block and winning
on specificity as well as order, so the checkbox path and the dataset path wear
the same 2014 white. Since 2026-08-21 the theme emissions sit in `@layer tokens`
(the lowest cascade layer), and un-layered styles beat layered ones regardless
of source order — so an app palette written at plain `:root` wins **by
construction**, and reordering `@use` lines can no longer restore indigo in
either theme. The non-theme rules `_tokens.scss` carries (the type/space/z
scales, the tabular money widths) stay exactly as worn: a layered token still
applies wherever nothing un-layered redeclares it.

Social dark-tokens is worn intentionally in exactly one brgen place —
`body.vertical-maps` (`_vertical_maps_shell.scss`) — plus `shared/_minimal.scss`
and `shared/_tokens.scss` themselves.

**Focus triangle:** brgen + amber + MASTER web. Shared engine glue (layout,
social locales, comments form/row, master_embed). bsdports/studio
maintenance-only unless named.

**Layout:** single-column feed (`--feed-max: 600px`) with edge-swiper
sidebar/widgets panels (`_shell.scss`). Footer tab bar is progressive (closed by
default; peel + scroll-up reveal via `scroll-chrome`). Side drawers and top
vertical nav are edge-swipe progressive. Verticals may hide chrome via
`_vertical_shell.scss`.

**Vertical accents:** single map in `design_tokens.yml` → `vertical_accents` and
`_vertical_shell.scss` only. Do not re-set `--accent` in ui_refinements or
vertical-local sheets.

**Empty states:** `shared/app/views/shared/_empty_state.html.erb` +
`_empty_state.scss`.

**Flat rule, no exceptions:** no `box-shadow`, `text-shadow`, `backdrop-filter`,
or `filter: blur()/drop-shadow()` in app CSS.

**Separation is space, not lines** (operator decision, 2026-07-28 — this
reverses the previous "separation = 1px hairline borders"). Stacked elements are
told apart by the gap between them; reach for padding, margin or `gap` first.
The home feed alone carried 35 bordered elements, 25 of them one hairline per
post, each competing with the text it was meant to organise.

**Tightened to "no lines at all" (operator decision, 2026-08-04.)** The three
exemptions below are down to one. Measured on the brgen front page at 390×844:
21 visible borders before, 0 after.

**"0 after" needed a second pass the same day.** The first measurement was taken
from a screenshot, and `.tab-bar-coach` renders *underneath* `.hotkey-coach`, so
its two buttons — `.tab-bar-coach-dismiss` and `.tab-bar-coach-show` — were not
in the frame and kept their `1px solid`. Re-measured by unhiding the coach from
the probe rather than waiting for a controller to reveal it: 8 borders, all of
them that pair, nothing else on the surface. Both now use a surface fill and
keep their 44px (`--tap-min`) targets; the page is at 0. If you check this
number, unhide every `[hidden]` first — an element that never painted reports no
borders and looks like a pass.

Still legitimate — the only exemption left:
- **form-field outlines** on `input` / `textarea` / `select`. An input with no
  outline gives no target; you must see where to type.

No longer exempt, and why:
- **Control outlines.** A button is not a field. `.compose-trigger`,
  `.btn-ghost`, `.btn-danger` and `.btn--secondary` each traded a 1px edge for a
  surface fill, which reads as a control without drawing a rule.
- **State indicators.** The active nav link's 2px underline is gone; state is
  weight and colour. `aria-current` was already carrying it for assistive tech,
  so nothing was lost but the line.
- **Inline-direction accent markers.** Not currently on any measured surface; if
  one comes back, it is a line and needs the same treatment.

A solid `background` still separates fine where a surface genuinely differs —
and after this pass it is doing all of the separating.

**Feed actions:** use `shared/_feed_icon.html.erb` SVG icons — not emoji.

## Engine extraction (done)

`install_frontend_baseline.sh` is deprecated. Prune per-app duplicates of shared
controllers/partials when found.

## What is *not* extracted, and why (2026-07-28)

A sweep for byte-identical files across amber/brgen/bsdports found 26 of them —
but only 299 lines in total, because most are 4–9 line files Rails, ActionCable
or StimulusReflex require the host app to define. Extracted the ones carrying
real logic:

- `Shared::SsoUserProvisioning` — `find_or_create_sso_user` was identical in all
  three; only `start_sso_session!` ever differed, and that stays overridable.
- `Shared::CableIdentity` — `ApplicationCable::Connection`'s cookie→user lookup.
  `set_current_user` returns true/false rather than the assignment value so
  brgen's soft-guest path can `super` and then keep looking.
- `Shared::DraftsActions` — session-backed form autosave.
- `passwords_mailer/reset.*` and `layouts/mailer.*` now live only in the engine,
  reachable because `shared.view_paths` appends to **ActionMailer** as well as
  ActionController. It previously did not, which is why every app carried copies
  — and why amber and bsdports were rendering Rails' *generated stub* mailer
  layout, shadowing the designed one, while brgen was not.
- `FingerprintsController`, `PasswordsMailer` and `lib/tasks/visits.rake` exist
  once, in the engine. The first two are top-level constants, resolved by bare
  name from a host route set and from `Shared::PasswordResetJob`; the rake tasks
  reach every app because `Rails::Engine#run_tasks_blocks` loads the engine's
  `lib/tasks/**/*.rake`.
- `jox_logo_controller.js` lives in `frontend/` and registers through
  `LAZY_COMPONENTS`, so amber and bsdports get the logo animation and brgen,
  which has no such logo, pays one importmap line and no fetch.

Deliberately left duplicated:

- **Framework-required host constants**: `SessionsController`,
  `PasswordsController`, `ReactionsController`, `DraftsController`,
  `Authentication`, the four reflexes, `ApplicationCable::Channel`, `Current`,
  `Session`, `controllers/{index,application,application_controller}.js`. These
  are already one-line delegations to the engine; routing, Zeitwerk and
  StimulusReflex resolve them by bare constant, so the file has to exist.

## Vertical ownership (2026-08-10)

brgen hosts five mountable engines and two plain namespaces. Which is which
matters more than it looks: **tooling that globs `<app>/app/**` sees the
namespaces and misses the engines**, and this repo has paid for that four times
— 57 engine views dropped out of four scanners at once when the verticals moved,
and the falling finding count read as an improvement rather than as blindness.
The engines live at `brgen/engines/<name>`, not `brgen/app/engines/<name>`.

| Vertical | Kind | Path | Models | Controllers | Views |
|---|---|---|---|---|---|
| marketplace | engine | `brgen/engines/marketplace` | 8 | 12 | 28 |
| playlist | engine | `brgen/engines/playlist` | 13 | 12 | 27 |
| tv | engine | `brgen/engines/tv` | 11 | 10 | 23 |
| takeaway | engine | `brgen/engines/takeaway` | 7 | 7 | 13 |
| dating | engine | `brgen/engines/dating` | 4 | 6 | 10 |
| maps | engine | `brgen/engines/maps` | — | 3 | 5 |
| messenger | namespace | `brgen/app/controllers/{conversations,messages}_controller.rb` | — | 2 | — |

Subdomain constraints in `brgen/config/routes.rb` map hosts onto these through
`Brgen::DomainRegistry`. The MASTER relay is not a vertical.

### Shared concerns each engine actually includes

Measured by scanning for `Shared.concern(:X)` and `include Shared::X` in each
engine's models — not by looking for the constant name, which over-reports on
comments and on `Tv` in particular.

| Engine | Concerns |
|---|---|
| marketplace | GeoLocatable, MediaProcessable, Notifiable, Reactable, Sluggable, StrictSafeAssociations |
| takeaway | GeoLocatable, MediaProcessable, Notifiable, Reactable, Sluggable, StrictSafeAssociations, Votable |
| dating | GeoLocatable, MediaProcessable, Notifiable, Reactable, StrictSafeAssociations |
| playlist | GeoLocatable, MediaProcessable, Notifiable, Reactable, Sluggable |
| tv | MediaProcessable, Notifiable, Reactable, Sluggable |

Four concerns are load-bearing everywhere: `MediaProcessable`, `Notifiable`,
`Reactable`, `Sluggable` (four of five). A change to any of those lands in every
vertical of brgen plus amber and bsdports at once. `Votable` is takeaway-only
inside the engines, which is worth knowing before assuming it is safe to change.

### Rules

- A vertical's models must not reference another vertical's models. Cross-
  vertical reads go through a shared concern.
- A vertical's views may use any shared Stimulus controller; the baseline is
  registered for every app in `frontend/stimulus_boot.js`.
- Anything that enumerates brgen's code must glob `brgen/engines/*/app/**`
  alongside `brgen/app/**`, or it is measuring roughly half the app and will
  report the difference as health.
