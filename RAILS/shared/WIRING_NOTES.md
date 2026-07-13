# Shared Rails wiring notes

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem (`pub4-shared`) loaded via local path in each app Gemfile.

## Visual system — one `application.css` per app

Each app compiles a **single** `app/assets/builds/application.css` via Dart Sass. No separate `tokens.css`, `animations.css`, or `minimal-ui*.css` links in layouts.

**Protected file:** only `application.scss` per `limits.yml` → `frontend_protection`. Prefer `@use "pub4_stack"` plus existing domain partials (brgen pattern); avoid new `_appname.scss` sprawl when product CSS fits the entry or an existing partial.

**Stack entry** (top of every `application.scss`):

```scss
@use "pub4_stack" as *;
```

`pub4_stack` forwards: `_minimal`, `_tokens`, `_animations`, `_zen_shell` (offline page, install prompt, zen-minimal shell).

**Brgen** adds product partials after the stack (`_root`, `_canvas`, `_shell`, …). **Standalone apps** add a thin product block below `@use "pub4_stack"`.

**Static exceptions:**
- `shared/public/styles/errors.css` — Rails default error pages only
- brgen: `face.css`, `lightgallery.css` — product vendor assets
- External font CDNs where apps use them (amber)

**Tooling:** `dartsass-rails`, `Shared::FrontendAuditor` (0-warning target on app-owned paths), `bin/rails dartsass:build` in CI.

## Hotwire / Stimulus baseline

**JS entrypoints** (`shared/frontend/`):
- `pub4_hotwire.js` — Turbo, theme-meta, PWA SW, nav-reveal (idempotent), minimal-gesture boot
- `pub4_stimulus_boot.js` — full @stimulus-components fleet (incl. password-visibility, nested-form, carousel, read-more, checkbox-select-all), StimulusReflex, Futurism, live-search, offline-page, install-prompt, theme-toggle
- `Shared::StimulusFormHelper` — `character_counter_field`, `password_visibility_field`, `read_more`
- Gate: `ruby RAILS/stimulus_components_adoption_gate.rb` (no legacy `char-counter` / duplicate controllers)
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

**Commentable:** brgen and amber use polymorphic `comments` + `Shared::Commentable` on `Post`.

**Deferred DRY:** brgen still has local `NotificationsController` and `VotesController` vs shared stubs (see brgen/app/controllers/{notifications,votes}_controller.rb headers); Follow schema differs across apps. Promote when city inbox grouping and vote karma side-effects are unified. Controllers carry comments linking here.

**Notification model:** brgen keeps `Notification` (not `Shared::Notification`) on the same `notifications` table. Brgen adds `title`/`body` presenters, a `match` kind for dating, and Turbo broadcasts to `brgen:notifications:*`. Shared::Notification is the thin engine stub for apps that eval `shared/config/routes/social.rb`. Same table, different presentation contract — duplication beats the wrong abstraction until inbox grouping unifies.

Controllers: `Shared::LiveSearchable`, `StructuredEvents`, `MediaGuard`, `ActorIdentity`.

Emit activity via `Shared::EventEmitter` / `include Shared::StructuredEvents` for unified graph + Turbo Stream consumers.

## CI gate (per app)

```bash
bin/rails dartsass:build
bin/importmap audit
bin/rails test
```

Family-level: `ruby RAILS/test/pwa_design_contract_test.rb`, `ruby RAILS/test/shared_social_routes_test.rb`, `ruby RAILS/frontend_production_gate.rb`.

## Visual design system (2026-07-10)

**Reference:** x.com's current design language is the base for every app's chrome. Source of truth is code, not this doc: `shared/app/assets/stylesheets/_x_base.scss` (two mixins, `x-dark-tokens`/`x-light-tokens`) and `shared/design_tokens.yml`. All three apps (amber, brgen, bsdports) inherit these via `pub4_stack` → `_tokens.scss` → `_x_base.scss`, so a change to `_x_base.scss` propagates everywhere.

Real X reference values baked into the tokens (verify against current x.com before changing, don't guess):
- Accent `#1d9bf0`, danger `#f4212e`, success `#00ba7c`, warning `#ffd400`
- Dark: bg/surface `#000000`, elevated surface `#16181c`, text `#e7e9ea`, secondary text `#71767b`, border `#2f3336`
- Light: bg/surface `#ffffff`, elevated surface `#f7f9f9`, text `#0f1419`, secondary text `#536471`, border `#eff3f4`
- Layout: 275px sidebar / 600px feed / 350px widgets / 1265px max — X's real three-column widths
- Radius: 16px cards, full pill on buttons/chips/avatars, 4-12px on smaller controls
- Type: `--x-font` is X's real UI stack (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`) — Chirp itself is proprietary and can't be redistributed, so this is the same fallback X itself serves when Chirp isn't loaded. `--x-font-mono` (JetBrains Mono stack) is reserved for code/data/terminal-flavored surfaces (bsdports' ports listings) — never the default body font.

**Flat rule, no exceptions:** no `box-shadow`, `text-shadow`, `backdrop-filter`, or `filter: blur()/drop-shadow()` anywhere in app CSS. Real X has none of these in its own chrome — elevation and separation come from a 1px hairline border (`var(--x-border)`/`var(--border)`) or a solid (non-translucent) background, never a shadow or a glassmorphism blur. If you're tempted to add elevation, add a border instead.

**Process:** phase 1 (current) is exact parity with x.com's real values on the shared token layer. Deliberate, branded divergence from that baseline is phase 2 and hasn't started yet — don't invent a "unique" color/spacing choice on the shared layer without that being an explicit, separate decision.

## Engine extraction (done)

`install_frontend_baseline.sh` is deprecated. Prune per-app duplicates of shared controllers/partials when found.
