# Shared Rails wiring notes

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem (`pub4-shared`) loaded via local path in each app Gemfile.

## Visual system — one `application.css` per app

Each app compiles a **single** `app/assets/builds/application.css` via Dart Sass. No separate `tokens.css`, `animations.css`, or `minimal-ui*.css` links in layouts.

**Stack entry** (top of every `application.scss`):

```scss
@use "pub4_stack" as *;
```

`pub4_stack` forwards: `_minimal`, `_tokens`, `_animations`, `_zen_shell` (offline page, install prompt, zen-minimal shell).

**Brgen** adds product partials after the stack (`_root`, `_canvas`, `_shell`, …). **Standalone apps** add a thin product block below `@use "pub4_stack"`.

**Static exceptions:**
- `shared/public/styles/errors.css` — Rails default error pages only
- brgen: `face.css`, `lightgallery.css` — product vendor assets
- External font CDNs where apps use them (amber, blognet)

**Tooling:** `dartsass-rails`, `Shared::FrontendAuditor` (0-warning target on app-owned paths), `bin/rails dartsass:build` in CI.

## Hotwire / Stimulus baseline

**JS entrypoints** (`shared/frontend/`):
- `pub4_hotwire.js` — Turbo, theme-meta, PWA SW, nav-reveal (idempotent), minimal-gesture boot
- `pub4_stimulus_boot.js` — @stimulus-components, StimulusReflex, Futurism, live-search, offline-page, install-prompt, theme-toggle
- `pub4_theme_meta.js`, `pub4_nav_reveal.js`, `pub4_live_search_controller.js`, …

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

Five apps eval `shared/config/routes/social.rb` (notifications, reactions, reports). Controllers subclass `Shared::ReactionsController`, `Shared::NotificationsController`, `Shared::ReviewCasesController`.

**Brgen** mounts equivalent routes inline; uses city-specific `NotificationsController` (grouped inbox) and `ModerationReport` for reports. Reactions use `Shared::ReactionToggle`.

## Shared concerns

Models: `Shared::Reactable`, `Followable`, `Votable`, `Commentable`, `Notifiable`, `ActivityTrackable`, `GeoLocatable`.

**Commentable:** brgen and amber use polymorphic `comments` + `Shared::Commentable` on `Post`. blognet uses post-scoped comments.

**Deferred DRY:** brgen still has local `NotificationsController` and `VotesController` vs shared stubs; Follow schema differs across apps. Promote when city inbox grouping and vote karma side-effects are unified.

Controllers: `Shared::LiveSearchable`, `StructuredEvents`, `MediaGuard`, `ActorIdentity`.

Emit activity via `Shared::EventEmitter` / `include Shared::StructuredEvents` for unified graph + Turbo Stream consumers.

## CI gate (per app)

```bash
bin/rails dartsass:build
bin/importmap audit
bin/rails test
```

Family-level: `ruby DEPLOY/rails/test/pwa_design_contract_test.rb`, `ruby DEPLOY/rails/test/shared_social_routes_test.rb`, `ruby DEPLOY/rails/frontend_production_gate.rb`.

## Engine extraction (done)

`install_frontend_baseline.sh` is deprecated. Prune per-app duplicates of shared controllers/partials when found.