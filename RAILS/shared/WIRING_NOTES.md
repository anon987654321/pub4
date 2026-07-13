# Shared Rails wiring notes

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem (`pub4-shared`) loaded via local path in each app Gemfile.

## Visual system — one `application.css` per app

Each app compiles a **single** `app/assets/builds/application.css` via Dart Sass. No separate `tokens.css`, `animations.css`, or `minimal-ui*.css` links in layouts.

**Protected file:** only `application.scss` per `limits.yml` → `frontend_protection`. Prefer `@use "pub4_stack"` plus existing domain partials (brgen pattern); avoid new `_appname.scss` sprawl when product CSS fits the entry or an existing partial.

**Stack entry** (top of every `application.scss`):

```scss
@use "pub4_stack" as *;
```

`pub4_stack` forwards: `_minimal`, `_tokens`, `_animations`, `_zen_shell` (offline page, install prompt, x.com-shell primitives).

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

## x.com parity verification (phase 1)

Run from repo root before merging visual/chrome work. Tier 1 gates are CI-blocking.

```bash
ruby RAILS/build_all_css.rb --check          # tokens.css ↔ _x_base.scss drift (no build)
ruby RAILS/frontend_auditor_gate.rb          # 0 warnings — amber, brgen, bsdports, shared
ruby RAILS/frontend_production_gate.rb       # dartsass + importmap + build_all_css
ruby RAILS/test/x_design_contract_test.rb    # token/layout/shell/feed contract assertions
# per app (CI also runs these):
cd RAILS/brgen && bin/rails dartsass:build
cd RAILS/amber && bin/rails dartsass:build
cd RAILS/bsdports && bin/rails dartsass:build   # output: app/assets/builds/app.css
```

`x_design_contract_test.rb` is wired in `RAILS/release_gate.rb` alongside `pwa_design_contract_test.rb`. Optional hardening (PR 13): `ruby RAILS/script/x_visual_snapshot.rb` — see **Visual baseline refresh** below.

### Icon contract

x.com action/nav icons are **inline SVG** via `shared/_x_icon.html.erb` — no sprite sheet.

| Concern | Rule |
|---------|------|
| Partial | `render "shared/x_icon", name: :like, size: 18` or `x_icon(:like)` from `Shared::XUiHelper` |
| Path partials | `shared/x_icons/_<name>.html.erb` |
| Markup | `viewBox="0 0 24 24"`, `fill="currentColor"`, `aria-hidden="true"` |
| Sizes | 18×18 action row; 26×26 sidebar/tab nav |
| Core names | `reply`, `repost`, `like`, `share`, `views`, `home`, `search`, `notifications`, `messages`, `compose` |

App-specific nav icons (amber wardrobe, brgen nearby, etc.) live under `shared/x_icons/` with the same partial contract.

### Action color verification checklist (deferred hex)

Like/repost **active** hues are not YAML anchors until snapshotted from live x.com. Do not guess values (e.g. `#f91880`).

| Token | Procedure | Until verified |
|-------|-----------|----------------|
| Like active hue | DevTools computed style on a liked post action; record hex + date below | `var(--x-accent)` via `--x-like-active` |
| Repost active hue | Same on repost-active state | `var(--color-success)` via `--x-repost-active` |
| Any new semantic hue | Dated DevTools snapshot required before `design_tokens.yml` change | Use existing `--x-*` aliases |

Record verified values here when snapshotted:

```
# like-active:  (unverified — fallback --x-accent)
# repost-active: (unverified — fallback --color-success)
```

### Phase 2 divergence process (not started)

Phase 1 requires exact `design_tokens.yml#social:` ↔ `_x_base.scss` parity. Branded divergence is **explicit phase 2** — never override shared `--x-*` anchors on the stack layer without all of:

1. Stakeholder sign-off (table below).
2. `design_tokens.yml` change + `x_design_contract_test.rb` update.
3. `ruby RAILS/build_all_css.rb --check` green.
4. WIRING_NOTES entry naming the divergence and scope.

| Divergence | Scope | Phase 2 trigger |
|------------|-------|-----------------|
| **brgen accent hue** | `brgen/_root.scss` or product partials only — **not** `--x-accent` on shared layer | Phase 1 parity gate passed; city brand decision |
| **openbsd_wscons** | `design_tokens.yml#openbsd_wscons:` green terminal palette on bsdports chrome | Phase 1 bsdports x.com shell signed off; mono/data cells may stay scoped in phase 1 |
| **amber luxury** | `body.product-luxury` only — Caprasimo, warm neutrals, `_items_luxury.scss` | Always outside phase 1 parity gate; x shell/feed audited on default body class |

### Stakeholder decisions (2026-07-13, final)

| # | Question | Decision | Implementation |
|---|----------|----------|----------------|
| 1 | MASTER canvas vs chrome | Cream message bodies; blue accent on links/buttons/focus only | PR 10: `--face-fg` on `.msg-body`; `--chrome-accent` on interactive chrome |
| 2 | bsdports mono identity | x.com shell + mono scoped to data cells | PR 8: system UI body; mono on `.port-name`/`code`/`pre`; no `openbsd_wscons` in phase 1 |
| 3 | amber luxury | `body.product-luxury` scope, outside parity gate | PR 7: luxury CSS gated; parity QA on default body |
| 4 | Chirp font | System UI stack only — no Chirp CDN | `_x_base.scss` `--x-font`; no `@font-face` for Chirp |
| 5 | Visual regression baselines | **RAILS team / frontend owner** owns PNG updates | PR 13 / process below |
| 6 | web-vitals destination | Server logs only | PR 16: `Rails.logger`; no MASTER bus or external collector |

### Visual baseline refresh (RAILS frontend owner)

When x.com chrome drifts or intentional token updates land:

1. **Owner:** RAILS team / frontend owner (on-call for x.com drift).
2. Re-capture Playwright baselines: `ruby RAILS/script/x_visual_snapshot.rb --update` (after PR 13 lands).
3. Viewports: 390×844, 1280×800. Pages: brgen home (dark + light), amber guest feed, bsdports ports index.
4. Open a PR with updated `RAILS/test/fixtures/x_visual/*.png` only when visual diff exceeds 0.5% threshold.
5. Include dated note in PR body: what changed on x.com and which surfaces were re-shot.
6. Token-only changes: `build_all_css.rb --check` + `x_design_contract_test.rb` may suffice without PNG refresh.

### Parity surface list (phase 1 sign-off)

Phase 1 “parity done” means **these surfaces only** — not all brgen verticals.

| Surface | Apps |
|---------|------|
| Shared token layer + flat rule | all |
| Three-column shell + mobile tab bar | amber, brgen, bsdports |
| Home/main feed (dark + light) | brgen, amber (default body — not `body.product-luxury`) |
| Inline compose on home feed | brgen, amber |
| Ports index + show (feed column) | bsdports |
| MASTER HUD chrome (cmd palette, chat shell, status) | MASTER |

Verticals (dating, marketplace, TV, takeaway, maps, messenger) get token alignment in phase 5+; per-vertical layout parity is explicitly out of phase 1 scope.

**Feed card gate:** `x_design_contract_test.rb#test_feed_partials_use_x_card` — home-feed item partials must render via `shared/x_card` (directly or through `posts/post`) on ≥80% of listed templates. Amber `posts/_post` and bsdports `ports/_row` migration tracked against this list.

## Engine extraction (done)

`install_frontend_baseline.sh` is deprecated. Prune per-app duplicates of shared controllers/partials when found.
