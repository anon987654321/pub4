# Shared Rails wiring notes

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem (`pub4-shared`) loaded via local path in each app Gemfile.

## Visual system — one `application.css` per app

Each app compiles a **single** `app/assets/builds/application.css` via Dart Sass. No separate `tokens.css`, `animations.css`, or `minimal-ui*.css` links in layouts.

**Protected file:** only `application.scss` per `limits.yml` → `frontend_protection`. Prefer `@use "stack"` plus existing domain partials (brgen pattern); avoid new `_appname.scss` sprawl when product CSS fits the entry or an existing partial.

**Stack entry** (top of every `application.scss`):

```scss
@use "stack" as *;
```

`stack` forwards: `_minimal`, `_tokens`, `_animations`, `_zen_shell` (offline page, install prompt, x.com-shell primitives).

**Brgen** adds product partials after the stack (`_root`, `_canvas`, `_shell`, …). **Standalone apps** add a thin product block below `@use "stack"`.

**Static exceptions:**
- `shared/public/styles/errors.css` — Rails default error pages only
- brgen: `face.css`, `lightgallery.css` — product vendor assets
- External font CDNs where apps use them (amber)

**Tooling:** `dartsass-rails`, `Shared::FrontendAuditor` (0-warning target on app-owned paths), `bin/rails dartsass:build` in CI.

## Hotwire / Stimulus baseline

**JS entrypoints** (`shared/frontend/`):
- `hotwire.js` — Turbo, theme-meta, PWA SW, nav-reveal (idempotent), minimal-gesture boot
- `stimulus_boot.js` — full @stimulus-components fleet (incl. password-visibility, nested-form, carousel, read-more, checkbox-select-all), StimulusReflex, Futurism, live-search, offline-page, install-prompt, theme-toggle
- `Shared::StimulusFormHelper` — `character_counter_field`, `password_visibility_field`, `read_more`
- Gate: `ruby RAILS/gates/runner.rb stimulus_components` (no legacy `char-counter` / duplicate controllers)
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

**Live search:** `live_search_index` helper + `Shared::LiveSearchable` — rolled out on all index views.

**Mailers:** `render "layouts/mailer_styles"` (shared partial; inline `<style>` required for email clients).

## Social endpoints

Amber and brgen eval `shared/config/routes/social.rb` (notifications, reactions, reports). BSDports intentionally omits those routes because its schema has no social tables.

**Brgen** mounts equivalent routes inline; uses city-specific `NotificationsController` (grouped inbox) and `ModerationReport` for reports. Reactions use `Shared::ReactionToggle`.

## Shared concerns

Models: `Shared::Reactable`, `Followable`, `Votable`, `Commentable`, `Notifiable`, `ActivityTrackable`, `GeoLocatable`, `StrictSafeAssociations`.

**Strict loading is on everywhere — mind the after-write reads.** `ApplicationRecord` sets `strict_loading_by_default = true` for *all* environments. Only `development.rb` downgrades a violation to a log line (`action_on_strict_loading_violation = :log`); test and production **raise**, because that is Rails' default.

That combination traps state-changing methods that notify someone or emit activity: they `update!` first, then read a `belongs_to` to find the recipient. On a record loaded by id — controller action, PSP webhook, background job — nothing is preloaded, so the read raises *after* the write has committed. The state change sticks, the notification is silently lost, and the caller gets a 500. Retries then no-op because the guard (`payable?`, `may_transition_to?`) is already satisfied.

Fixed instances (2026-07-27): `Shared::ActivityTrackable#tracks_activity` resolved `actor:` with a bare `public_send` inside `after_commit`, *outside* `record_activity!`'s rescue — this affected all 38 models passing `actor:`, and every one with an `updated:` event. Also `Marketplace::Order#mark_paid!/accept!/decline!`, `Takeaway::Order#transition_to!/calculate_totals!`, the `Tv` activity emitters, and the `listing_owner`/`restaurant_owner`/`channel_owner` actor delegates.

Use `strict_safe(:assoc)` / `strict_safe_attribute(:assoc, :column)` from `Shared::StrictSafeAssociations` in those paths. It is **not** a licence to skip preloading — `includes` at the query site is still correct and is what stops the N+1 strict loading exists to catch. This is the safety net for paths where a dropped notification is worse than an extra `SELECT`. Actor resolution now degrades to `nil` rather than raising: analytics must never be why a write fails.

**Commentable:** brgen and amber use polymorphic `comments` + `Shared::Commentable` on `Post`.

**Deferred DRY:** brgen still has local `NotificationsController` and `VotesController` vs shared stubs (see brgen/app/controllers/{notifications,votes}_controller.rb headers); Follow schema differs across apps. Promote when city inbox grouping and vote karma side-effects are unified. Controllers carry comments linking here.

**Notification model:** brgen keeps `Notification` (not `Shared::Notification`) on the same `notifications` table. Brgen adds `title`/`body` presenters, a `match` kind for dating, and Turbo broadcasts to `brgen:notifications:*`. Shared::Notification is the thin engine stub for apps that eval `shared/config/routes/social.rb`. Same table, different presentation contract — duplication beats the wrong abstraction until inbox grouping unifies.

Controllers: `Shared::LiveSearchable`, `StructuredEvents`, `MediaGuard`, `ActorIdentity`.

Emit activity via `Shared::EventEmitter` / `include Shared::StructuredEvents` for unified graph + Turbo Stream consumers.

## CI gate (per app)

```bash
bin/rails dartsass:build
bundle exec ruby -e 'require "./config/environment"; require "importmap/commands"; Importmap::Commands.start(%w[audit])'
bin/rails test
```

Family-level: `ruby RAILS/test/pwa_design_contract_test.rb`, `ruby RAILS/test/design_contract_test.rb`, `ruby RAILS/test/shared_social_routes_test.rb`, `ruby RAILS/gates/runner.rb frontend_production`.

## x.com parity recovery (2026-07-20)

Recovered from deleted execute-plan stack (tags: `recover/x-parity-stack`, `recover/x-modal-sheet`) without full merge.

| Piece | Location |
|-------|----------|
| Contract tests | `RAILS/test/design_contract_test.rb`, `shared/test/lib/design_tokens_test.rb` |
| Web vitals (1% sample) | `shared/frontend/hotwire.js` → `POST /web_vitals` (`WebVitalsController`, `fleet.rb`) |
| Bottom sheet | `shared/frontend/bottom_sheet_controller.js` (`pub4/bottom_sheet`) |
| Modal / sheet CSS | `shared/app/assets/stylesheets/_modal.scss` (via `@forward "modal"` in `_stack.scss`) |
| Action bar + icons | `shared/_action_bar`, `shared/_icon`, `shared/icons/*` |
| UI helper | `Shared::UiHelper` (engine initializer `shared.ui_helper`) |
| Theme FOUC | `shared/_theme_bootstrap` + `theme_toggle` sets `document.documentElement.dataset.theme` |

**Not recovered wholesale:** full `_shell` layout rewrite for all apps (main layouts already diverge). Pull shell partials only when a product explicitly adopts them.

**Gates (from repo root):**

```bash
ruby RAILS/test/design_contract_test.rb
ruby RAILS/shared/test/lib/design_tokens_test.rb
ruby RAILS/tools/build_all_css.rb --check
ruby RAILS/gates/runner.rb frontend_auditor
```

## Visual design system (2026-07-19)

**Reference:** x.com interaction patterns; pub4 graphite/indigo palette. Source of truth: `shared/design_tokens.yml`, `shared/app/assets/stylesheets/_dialect_tokens.scss`, `_shell.scss`. amber/brgen inherit via `stack` / `stack_brgen` → `_tokens.scss` → `_dialect_tokens.scss`.

**Dialects (do not merge casually):**
| Dialect | Apps | Radius | Notes |
|---------|------|--------|-------|
| `social` | brgen (+ verticals) | soft 4/8/12/16 | Graphite/indigo |
| `luxury` | amber | soft 6/10/14 | Warm paper (`luxury-*-tokens`) |
| `openbsd_wscons` | bsdports | **0** CRT-flat | Green mono terminal |
| `face_root` | MASTER web face | **0** CRT-flat | Operator face only |

**Shared social palette (dark):**
- Accent default `#7c6fd6`; brgen `#5b4fc4`; danger `#d1594a`
- bg/surface `#17161c`, elevated `#211f28`, search `#232030`
- text `#d8d6e0`, secondary `#8a879c`, border `#46435a`
- Light mode: indigo `#5b4fc4` on cool gray paper — **not** Twitter blue

**Focus triangle:** brgen + amber + MASTER web. Shared engine glue
(layout, social locales, comments form/row, master_embed). bsdports/studio
maintenance-only unless named.

**Layout:** single-column feed (`--feed-max: 600px`) with edge-swiper sidebar/widgets panels (`_shell.scss`). Footer tab bar is progressive (closed by default; peel + scroll-up reveal via `scroll-chrome`). Side drawers and top vertical nav are edge-swipe progressive. Verticals may hide chrome via `_vertical_shell.scss`.

**Vertical accents:** single map in `design_tokens.yml` → `vertical_accents` and `_vertical_shell.scss` only. Do not re-set `--accent` in ui_refinements or vertical-local sheets.

**Empty states:** `shared/app/views/shared/_empty_state.html.erb` + `_empty_state.scss`.

**Flat rule, no exceptions:** no `box-shadow`, `text-shadow`, `backdrop-filter`, or `filter: blur()/drop-shadow()` in app CSS.

**Separation is space, not lines** (operator decision, 2026-07-28 — this reverses
the previous "separation = 1px hairline borders"). Stacked elements are told
apart by the gap between them; reach for padding, margin or `gap` first. The
home feed alone carried 35 bordered elements, 25 of them one hairline per post,
each competing with the text it was meant to organise.

Still legitimate, because these are not separators:
- form-field and control outlines (affordance — you must see where to type)
- inline-direction accent markers (`border-inline-start: 3px solid var(--accent)`)
- state indicators (the active tab's underline)

A solid `background` still separates fine where a surface genuinely differs.

**Feed actions:** use `shared/_x_feed_icon.html.erb` SVG icons — not emoji.

## Engine extraction (done)

`install_frontend_baseline.sh` is deprecated. Prune per-app duplicates of shared controllers/partials when found.

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
  ActionController. It previously did not, which is why every app carried
  copies — and why amber and bsdports were rendering Rails' *generated stub*
  mailer layout, shadowing the designed one, while brgen was not.

Deliberately left duplicated:

- **Framework-required host constants**: `SessionsController`,
  `PasswordsController`, `ReactionsController`, `FingerprintsController`,
  `DraftsController`, `Authentication`, the four reflexes,
  `ApplicationCable::Channel`, `Current`, `Session`,
  `controllers/{index,application,application_controller}.js`. These are
  already one-line delegations to the engine; routing, Zeitwerk and
  StimulusReflex resolve them by bare constant, so the file has to exist.
- **`jox_logo_controller.js`** (48 lines, amber + bsdports). The shared
  Stimulus baseline is registered for *all* apps in `frontend/stimulus_boot.js`.
  Promoting product-specific branding there would ship a jox logo controller to
  brgen, which does not have that logo. Two copies beats one wrong dependency.
