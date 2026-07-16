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
- Gate: `ruby RAILS/stimulus_components_adoption_gate.rb` (no legacy `char-counter` / duplicate controllers)
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

Models: `Shared::Reactable`, `Followable`, `Votable`, `Commentable`, `Notifiable`, `ActivityTrackable`, `GeoLocatable`.

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

Family-level: `ruby RAILS/test/pwa_design_contract_test.rb`, `ruby RAILS/test/shared_social_routes_test.rb`, `ruby RAILS/frontend_production_gate.rb`.

## Visual design system (2026-07-15)

**Reference:** x.com's layout and interaction patterns; pub4's graphite/indigo palette on the shared token layer. Source of truth is code: `shared/app/assets/stylesheets/_x_base.scss`, `shared/design_tokens.yml`, and `shared/app/assets/stylesheets/_x_shell.scss` for the three-column grid. amber and brgen inherit via `stack` / `stack_brgen` → `_tokens.scss` → `_x_base.scss`.

**Shared palette (dark, `_x_base.scss` / `design_tokens.yml`):**
- Accent `#7c6fd6`, danger `#d1594a`
- bg/surface `#17161c`, elevated `#211f28`, search `#232030`
- text `#d8d6e0`, secondary `#8a879c`, border `#46435a`
- Layout: 275px sidebar / 600px feed / 350px widgets / 1265px max — implemented in `_x_shell.scss` at `min-width: 1265px`; icon-only sidebar rail (120px) at 769–1264px; mobile hides sidebar/widgets and shows tab bar
- Radius: **0** on shared tokens (`--x-radius-*` all 0) — hard edges, no rounded cards
- Type: `--x-font` is the system UI stack; `--x-font-mono` (JetBrains Mono Nerd Font stack) for code/data surfaces only

**Per-app accent overrides (phase 2 branding):** brgen sets `--x-accent: #5b4fc4` in `brgen/app/assets/stylesheets/_root.scss`. amber/bsdports use the shared indigo default unless they add their own override.

**Flat rule, no exceptions:** no `box-shadow`, `text-shadow`, `backdrop-filter`, or `filter: blur()/drop-shadow()` in app CSS. Separation comes from 1px hairline borders (`var(--x-border)`) or solid backgrounds.

**Feed actions:** use `shared/_x_feed_icon.html.erb` SVG icons in post cards — not emoji.

## Engine extraction (done)

`install_frontend_baseline.sh` is deprecated. Prune per-app duplicates of shared controllers/partials when found.
