# Shared Rails engine

This README is the single living documentation surface for `RAILS/shared/`. Executable gates, tests, and configuration remain authoritative; the sections below preserve the operational context that is useful to a human reader.

MASTER face and all RAILS apps share one **layout chrome** contract. Dialects
(social / luxury / wscons / face CRT) restyle color, type, and radius. They must
not invent a second z-scale, skip-link, tap floor, or main landmark pattern.

Source of truth: `../../MASTER/data/rules.yml#design_system`. The committed
`shared/design_tokens.yml` is a generated projection. CSS: `shared/app/assets/stylesheets/_layout_chrome.scss`
(RAILS), face `:root` generated into `MASTER/web/public/face.css`.

## Focus triangle (active product surface)

Primary product work targets these three only (unless explicitly scoped
elsewhere):

| Surface | Role |
|---------|------|
| **brgen** | City social — feed, channels, ambient chat, verticals |
| **amber** | Luxury wardrobe — outfits, feed compose, soft guests |
| **MASTER web** | Face + mission control at `ai.brgen.no` — embeddable AI |

Shared glue: `pub4-shared` (layout chrome, comments form/row, social locales,
`master_embed`, empty states). bsdports / studio remain maintenance-only unless
named in a task.

Bridge contract: RAILS hosts embed MASTER via `shared/master_embed` +
`master_web_url(autostart:, embed:)`. Face boot rules stay in
`MASTER/web/CLAUDE.md` (primer before WebGL; no three.js at first paint).

Social primitives (shared engine):
- `shared/post_card` — brgen `variant: :card`, amber `variant: :prose`
- `comments/form` + `comments/comment` — capability-aware form/row
- `shared/link_embed` — a post's YouTube, SoundCloud, Vimeo or Spotify link as
  a thumbnail facade; `media_exclusive_controller.js` on `<body>` loads the
  player only on press, and an unresolved link stays a plain link
- `social.en.yml` / `social.nb.yml` — actions, comments, post, master keys

## Surfaces

| Surface | Body attributes | Main landmark | Chrome |
|---------|-----------------|---------------|--------|
| MASTER chat | `data-layout="face" data-surface="face"` | `main#chat-shell`, holding the `#zin` prompt form | CRT HUD, radius 0 |
| MASTER dashboard | `data-layout="document" data-surface="face"` | `#main-content` | mono panels |
| brgen | `data-layout="document" data-surface="social"` | `#main-content` | app-shell + tab-bar |
| amber | `data-layout="document" data-surface="luxury"` | `#main-content` | app-shell + tab-bar |
| bsdports | `data-layout="document" data-surface="wscons"` | `#main-content` | top nav, CRT tokens |

## Required on every HTML document

1. `viewport-fit=cover` (safe-area aware)
2. First focusable: `.skip-link` → primary content
3. `main` with `id` + `role="main"`
4. CSS vars present (all defined in `_dialect_tokens.scss`, values from `MASTER/data/rules.yml#design_system`): `--chrome-inset` (0.75rem), `--tap-min` /
   `--bar-height` (44px), `--z-canvas`…`--z-skip` (shared ladder), `--safe-*`
5. Interactive primary controls ≥ 44px tall
6. No second box-shadow elevation language (flat UI); face popover exception
   only

## Storefront promotional art

Marketplace and Takeaway share one campaign-art system. The canonical grammar lives at MASTER/data/rules.yml#design_system.promotional_art: clean matte backgrounds, one-to-four products, a bounded copy zone, real HTML typography, and exact prices and CTAs. Shared::PromotionalArt generates the image prompt and returns the copy separately; shared/_promotional_art renders the deterministic HTML composition. Do not ask an image model to typeset campaign copy. Generate the product scene, then place the headline, body, price, badge, and CTA in Rails.

## Shared primitives

- `.skip-link` — hard-hidden until `:focus-visible`, corner at chrome-inset +
  safe-area
- `.page-header` — title + optional actions, measure-capped
- `.app-shell` / `.layout` — document column (RAILS); face uses full-viewport
  canvas
- `main#main-content` — page gutter via `--page-gutter` unless inside `.layout`

## What may diverge

- Color dialect and radius (face/wscons = 0; social soft; luxury warm)
- Presence of tab-bar vs top nav vs face HUD
- Nothing about the typeface. Every app sets one family, `shared_chrome.font` in
  `design_tokens.yml` ("Helvetica Neue Pro", "Helvetica Neue", Arial, sans-serif).
  Monospace (`shared_chrome.font_code`, `--font-mono`) is for code blocks inside
  posts and comments, brgen's live chat logs and MASTER's web chat. brgen keeps
  its wordmark's own stack. Marketplace resolves `--font-ad` to the house
  grotesk; takeaway retains its separate promotional face until rendered review
  replaces it.

## Verify

```zsh
ruby RAILS/test/layout_contract_test.rb
ruby RAILS/tools/generate_face_root_css.rb   # face :root sync
ruby RAILS/tools/build_all_css.rb --check
```

---

The four surfaces (brgen + verticals, amber, bsdports, the MASTER face) are one
family in four dialects. This table is where a new surface starts — pick from
it, don't invent beside it. Decisions recorded 2026-08-21 at the close of the
consistency campaign; enforcement lives in `visual_contract_lint`,
`css_coverage_lint`, `breakpoint_lint`, `empty_state_lint` and
`MASTER/tools/design_baseline.rb`, all ratcheted.

## Dialects

| Surface | Palette | Radius | Type | Theme |
|---|---|---|---|---|
| brgen (+verticals) | brgen_old grayscale, per-vertical accents (3-slot map) | 4/8/12/8 | Inter | light default on all eight, `data-theme` toggle |
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

- **Buttons** — dash-spelled, one family in `_buttons.scss`: `btn` base +
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
- playlist redeclares `--font-mono` as SF Mono. It is the fifth face in the
  fleet and it is deliberate: the vertical is branded on the SF family, stated
  at the head of `_vertical_playlist.scss`, and the token is scoped to
  `body.vertical-playlist` so no other surface inherits it.

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

Ten sheets exceed it. Not one queue: _components (593) and _minimal (459) are
BASE LAYERS — one file is their design, splitting them scatters the cascade
story; _dialect_tokens (200+) holds tokens AND theme mixins and is the one with
a real seam (tokens vs mixins) if anyone splits anything.

"Splitting scatters the cascade story" held until it was measured. The button
family came out of _components on 2026-09-10 into `_buttons.scss`, forwarded
immediately before it, and the three built bundles hold the same declarations in
an order no element can tell apart — the 24 pairs that changed relative order
all pit `.btn` against a utility that ties it at 0-1-0, and no element in the
tree wears both. So the objection is answerable per candidate rather than in
general: build the CSS before and after, diff the resolved order, and a seam
whose two halves never contend is a seam. face.css (1282) is the
whole face by construction. The app sheets (_chrome_polish 324, _marketplace
251, _vertical_playlist 378, amber _brand 378) are section-seamed and splittable
when their surfaces are next open; the auditor keeps counting so none of this
grows silently.

---

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem
(`pub4-shared`) loaded via local path in each app Gemfile.

brgen is one process with many hosts, not one site: city apex = feed,
`engines/*` = subdomain verticals (`dating.brgen.no`,
`marketplace.lsangeles.com`). Messenger is host routes. `ai.brgen.no` is MASTER.
Topology: `RAILS/brgen/AGENTS.md`.

## Visual system — one `application.css` per app

Each app compiles a **single** `app/assets/builds/application.css` via Dart
Sass. A layout links that file and nothing else — no second stylesheet for
tokens, animations or a minimal UI.

**One stylesheet per app.** Each app owns exactly one stylesheet,
`app/assets/stylesheets/application.scss`, and brgen's verticals style
themselves inside brgen's, scoped under `body.vertical-<name>`. The operator
asked for it on 2026-09-15: "for all our rails apps id prefer we collapse all scss
files into a single application.scss one such file for each app." An app adds no
partial of its own; it may load the shared engine's partials, which stay files.
`limits.yml` → `frontend_protection` protects that one file.

A shared partial first reached after the app's own rules is loaded with
`@include meta.load-css("name")` at that point, because Sass accepts `@use` only
above every rule. A shared partial the stack already loaded is not loaded again.

**Stack entry** (top of every `application.scss`):

```scss
@use "stack" as *;
```

`stack` forwards: `_minimal`, `_tokens`, `_animations`, `_buttons`,
`_components` (offline page, install prompt, x.com-shell primitives). The button
partial's position is a cascade contract, not an ordering convenience:
_components's `@media (forced-colors: active)` block names `.btn` and ties with it
at 0-1-0, so it has to keep the later word.

Every app writes its own rules below the `@use` lines.

Gates and tests that once named a partial now name the rule: `Operator::ScssRules`
(`shared/lib/operator/scss_rules.rb`) reads a stylesheet into selectors and the
declarations each holds, so "the nav's tabs declare a tap floor" is asserted on
`.feed-tab` wherever that rule sits. Product pens — the yep.com search, jOxVvNE,
Amazon's nav bar and logo — are named once, in
`Shared::FrontendRuleSet::PRODUCT_PEN_FILES` and `PRODUCT_PEN_SELECTORS`.

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
  password-visibility, nested-form, read-more, checkbox-select-all),
  StimulusReflex, live-search, offline-page, install-prompt,
  theme-toggle
- `Shared::StimulusFormHelper` — `character_counter_field`,
  `password_visibility_field`, `read_more`
- Gate: `ruby RAILS/gates/runner.rb stimulus_components` (no legacy
  `char-counter` / duplicate controllers)
- `theme_meta.js`, `nav_autohide_controller.js`, `live_search_controller.js`, …

**Per-app wiring:**

```js
// app/javascript/application.js
import "operator/hotwire"
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

## Speed proposals decided against (2026-09-13)

The "134 ways to feel instant" intake was verified against the tree; about half
was already here. Turbo 8 hover-prefetches every link unless told not to (only
sign-out and Pagy links opt out), the nav bars are `data-turbo-permanent`, the
city feed appends new posts to a staging list behind a chip rather than
refreshing, `action_controller.js` and `optimistic_send_controller.js` are the
shared optimistic patterns, `feed_hotkey_controller.js` has `j`/`k`,
`importmap_preload_audit` and `ImportmapExternalHostsExamples` hold the CDN line,
`touch-action: manipulation` sits on `.app-shell`, `QueryBudgetTest` and
`front_page_weight_test` are the query and payload budgets, the Workbox worker
(`shared/pwa/service_worker.js`) precaches assets, serves pages network-first
with a cached fallback and replays offline POSTs through Background Sync, and
the motion tokens live in `design_tokens.yml`. The rest was refused for these
reasons.

Nothing more is preloaded or pre-connected. Every preload, `preconnect` and
Speculation Rules prerender is a real request or socket against one 1 GB, one
vCPU box, and a prerender bypasses Turbo and renders the whole document twice.
Hover prefetch already spends the head start on links a reader is about to
choose. Pressing on `mousedown` instead is worse than hover, and the live search
keeps its 300 ms debounce for the same reason: halving it roughly doubles
queries while typing.

No page is cached for everyone. brgen's and amber's pages carry per-viewer
chrome — vote state, badge counts, the signed-in nav — that no record's
`updated_at` covers, so `fresh_when`, `expires_in public: true`, a cached nav or
Russian-doll comments would show one reader's state to another. bsdports'
`ports#show` and the avatar route are anonymous data, which is why they are the
exceptions. The first feed image stays lazy for the same reason: `_post` is
fragment-cached on a key with no position in it, so a card cannot know it is
first.

`Server-Timing` stays development-only (`config.server_timing` in
`shared/config/environments/development.rb`): in production it subscribes to
every notification on every request on one vCPU and hands view and database
timings to any visitor. The field INP sample now logs its target element instead.

No structural rewrite without a measurement. Cursor pagination cannot follow the
hot feed's computed rank, and no city is near `OFFSET` pain. The fresh feed's
plan is `index_posts_on_city_id` plus a temp B-tree sort over one city's posts
(brgen.no's sitemap listed 1,376 on 2026-08-12); a `(city_id, created_at)` index
is worth its migration when a city passes tens of thousands. `select` of fewer
columns raises `MissingAttributeError` wherever a partial read meets a method
that needs the column. Streaming, 103 Early Hints and SSE all meet relayd and
Falcon on a box with no spare core, and SSE holds a fiber per reader. Windowing
breaks find-in-page and the accessibility tree; `content-visibility` already
covers long feeds. `contain: paint` clips card menus. A server-rendered card
cannot be optimistically inserted without a second template in JavaScript.
Frame navigation for the feed's sort chips would leave the lit chip, which sits
outside the list, stale; lazy frames for side panels turn one request into
several. Lazy-registering Stimulus controllers and subsetting or preloading
fonts change what loads and paints, and wait for a measurement that names a
cost. Per-surface or critical CSS trades one immutable cached file for a miss on
every surface's first visit. AVIF encoding is CPU the box does not have, and
WebP already reaches every current browser. `broadcast_*_later` would enqueue a
job nothing on vm23 runs, which `Post#broadcast_live_refresh` says in place.

## Social endpoints

Amber and brgen eval `shared/config/routes/social.rb` (notifications, reactions,
reports). BSDports intentionally omits those routes because its schema has no
social tables.

**Brgen** mounts equivalent routes inline; uses city-specific
`NotificationsController` (grouped inbox) and `ModerationReport` for reports.
Reactions use `Shared::ReactionToggle`.

## Shared concerns

Models: `Shared::Reactable`, `Votable`, `Commentable`, `Notifiable`,
`ActivityTrackable`, `GeoLocatable`, `StrictSafeAssociations`.

There is no `Followable`. It declared `has_many :follows_received, as:
:followable` against a `follows` table that has no polymorphic columns in either
app — both model following as user to user, `follower` and `followed` in brgen,
`follower` and `followee` in amber — so the association could only ever raise.
Nothing included it. Following stays per-app until the two schemas agree, which
is the Deferred DRY note at the end of this file.

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

**Deferred DRY:** brgen still has a local `VotesController` (see its header);
Follow schema differs across apps. Promote when vote karma side-effects are
unified. brgen's `NotificationsController` subclasses
`Shared::NotificationsController` and adds only the kind-grouped inbox state.

**Notification model:** brgen keeps `Notification` (not `Shared::Notification`)
on the same `notifications` table. Brgen adds `title`/`body` presenters, a
`match` kind for dating, and Turbo broadcasts to `brgen:notifications:*`.
Shared::Notification is the thin engine stub for apps that eval
`shared/config/routes/social.rb`. Same table, different presentation contract —
duplication beats the wrong abstraction until inbox grouping unifies.

Controllers: `Shared::LiveSearchable`, `StructuredEvents`, `ActorIdentity`.
Upload size and type limits are model-side, in `Shared::AttachmentLimits`,
which `ApplicationRecord` includes.

Emit activity via `Shared::EventEmitter` / `include Shared::StructuredEvents`
for unified graph + Turbo Stream consumers.

## Write races on SQLite, and the owner's own fields (2026-09-13)

Rails 8.1 opens every SQLite transaction `BEGIN IMMEDIATE`
(ActiveRecord's SQLite3 database statements), so each save takes the
database's single writer lock before its validations read. A uniqueness
validation and the insert behind it therefore cannot interleave with another
writer, and a callback's `update_all` rolls back with the save it belongs to.
Findings that ask for `LEAST/GREATEST` indexes, partial unique indexes for
nullable scopes, or `after_commit` to undo a rolled-back counter all assume a
database that interleaves writers; this one does not. Note the corollary before
wrapping a long import in one transaction: it would hold that lock for the
whole import.

Some permitted params look like privilege and are the owner's own controls:
a listing's `status` (the edit form's sold/reserved select), a partner
program's `status` (no review step exists), a restaurant's `active` checkbox,
and a store's `stripe_connect_id`, which has no OAuth flow to replace it and
only points the owner's own payouts. `kind` is different and is locked on
update. Money is stored as integer minor units everywhere; `MoneyInOre`'s
float reader divides one integer sum for display and accumulates nothing.

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
   it holds after the session ends. `Operator::BreakpointLint` exists for exactly
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

## Reading a design finding (2026-09-09)

Four rules, each learned by a session that fixed the wrong thing first. They sat
in the backlog for weeks, where a rule is read once; a contract is read before
every change, which is why they are here.

**A value-preserving snap is a fix. A value-changing one is a decision.** Moving
a literal into the token that already holds the same value changes nothing on
screen and needs no one's permission. Moving it onto a token whose value differs
by a pixel changes what is painted, and belongs to the operator however tidy it
looks in the diff.

**A retirement is not finished while a test still names the retired thing.** The
dead `#dark-toggle` lane survived its own removal in two apps because their tests
still asserted it, and the tests passed. Grep for the name, not for the code.

**Sticky hover is not a defect until the hovers are classified.** There are 122
`:hover` rules across these apps and most of them are correct on a touch device
because they never fire there. A count is not a finding.

**A finding against the design system is usually a finding against the
instrument.** One pass produced 981 of them and 596 were misreadings of correct
markup. Before believing a number, check what it measured — the standing example
is a scan that searched for a bare constant name while every caller wrote it
qualified, and reported forty dead files that were all alive.

## The layout micro-refinement intake (2026-09-13)

A 264-item ChatGPT intake asked for "one canonical" scale of nearly everything,
per-vertical anatomy rules and a battery of design validators. It measured
nothing and named no file. The system it asked for is here. `design_tokens.yml`
carries the spacing ladder from `space_2xs` to `space_2xl`, the radii, the type
sizes and line heights, a 66ch prose measure, `tap_min`, `focus_ring`, the motion
durations and easings, and the breakpoint vocabulary under `viewport`.
`ScaleLint` and the `scale_ratchet` gate, `BreakpointLint`, `RhythmLint`,
`EmptyStateLint`, `DestructiveActionLint`, `LayoutStabilityLint`,
`css_coverage_lint`, `MAGIC_COLOR` and `css_budget.yml` hold arbitrary values
down. `layout_snapshot`, `visual_contract` and the `reflow` width sweep, with
its 320px floor, are the rendered checks. MASTER already scans this tree
through `bin/gate`, so a separate UI sweep mapped onto its laws would be a second
door.

**Refused.** A second token file, a duplicate-token detector and collapsing
"visually equivalent" tokens: the social, luxury and `brgen_old` dialects repeat
names with different values on purpose, and a snap between them changes paint.
Density modes, optical-inset tokens and a motion budget have no reader and no
finding behind them.

**The operator's.** Everything about how a surface looks: type hierarchy and
weight, uppercase and tracking, card and list anatomy, the marketplace, takeaway,
messenger, feed, maps, dating and playlist layouts, density, decorative
gradients and borders, and where motion belongs. An agent sweeping those would
be redesigning the product by grep. A rendered finding with a page and a width
reopens any of them as a single item.

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
| amber | `luxury` | `:root` and the light selectors in its `application.scss`, both halves |
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

**brgen's actual dark palette** — grayscale, and deliberately so (brgen's `application.scss`:
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
light themes" this section used to warn about is fixed — brgen's `application.scss` restates
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
`body.vertical-maps` (brgen's `application.scss`) — plus `shared/_minimal.scss`
and `shared/_tokens.scss` themselves.

**Focus triangle:** brgen + amber + MASTER web. Shared engine glue (layout,
social locales, comments form/row, master_embed). bsdports/studio
maintenance-only unless named.

**Layout:** single-column feed (`--feed-max: 600px`) with edge-swiper
sidebar/widgets panels (`_shell.scss`). Footer tab bar is progressive (closed by
default; peel + scroll-up reveal via `scroll-chrome`). Side drawers and top
vertical nav are edge-swipe progressive. Verticals may hide chrome through the
vertical shell section of brgen's `application.scss`.

**Vertical accents:** single map in `design_tokens.yml` → `vertical_accents` and
the `$vertical-accents` map in brgen's `application.scss` only. Do not re-set
`--accent` anywhere else.

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

## The engine is eager-loaded, and its own config says otherwise (2026-09-10)

`Shared::Engine.config.eager_load_paths` is empty while
`Shared::Engine.paths.eager_load` lists eleven directories, which reads like the
engine going unloaded in production — the difference between a boot failure and
a first-request 500, so it was worth settling rather than guessing.

It is a Rails internal and nothing is missing. Measured inside a booted brgen
with a migrated database: `Rails.autoloaders.main` carries 56 directories, all
eleven of the engine's among them, and the loader's eager-load exclusion set is
empty — so `Rails.application.eager_load!` reaches every one. `bin/rails
zeitwerk:check`, which eager-loads the whole application, answers "All is good!".

The measurement wants a migrated database and fails without one in a way that
looks like the finding: `Shared::Authentication.allow_unauthenticated_access`
reads `::User.column_names` in a class body, so eager loading a fresh worktree
aborts with `Could not find table 'users'` before it reaches anything about
engines. Run `bin/rails db:prepare` first.

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

Deliberately left duplicated:

- **Framework-required host constants**: `SessionsController`,
  `PasswordsController`, `ReactionsController`, `DraftsController`,
  `Authentication`, the four reflexes, `ApplicationCable::Channel`, `Current`,
  `Session`, `controllers/{index,application,application_controller}.js`. These
  are already one-line delegations to the engine; routing, Zeitwerk and
  StimulusReflex resolve them by bare constant, so the file has to exist.

## What the engine may define at a bare root (2026-09-10)

Sixteen files sit at an engine autoload root under an unnamespaced constant. An
app that defines the same path shadows the engine's copy and nothing says so:
`ApplicationHelper` was in that state in two apps at once, so the engine's copy
loaded only in bsdports, and its `nok` was a second money formatter disagreeing
with `Shared::MoneyDisplay`.

The rule that came out of it, so the next file lands on the right side:

- **A controller, a mailer, a policy or an `Application*` base stays bare.**
  Routing, ActionMailer and Zeitwerk resolve these by bare constant from the host
  — `PasswordsMailer` is reached by name from `Shared::PasswordResetJob`, and a
  namespaced `FingerprintsController` would not answer the host's route.
- **A model stays bare**, because its name is its table name. `Shared::SiteVerification`
  looks for `shared_site_verifications`, and every association to it grows a
  `class_name:` — the churn the cohesion census is repeatedly wrong about.
- **A plain service is namespaced.** Nothing resolves it for you, so a bare name
  is a shadowing hazard with no framework paying for it. `Shared::Scrape` is the
  only one there was.

## `shared/lib/operator/` keeps a flat drawer (2026-09-10)

Thirteen of the twenty file names there end in `_lint` and the cohesion census
proposes a `pub4/lint/` shelf. Decided against. The shelf is already spelled in
the filenames; the file count does not move, so no ratchet is paid either way;
and the cost is renaming thirteen constants and following them through
`MASTER/lib/operator/ratchets.rb` — which derives each constant from the basename —
plus `shared/config/ci.rb`, `gates/lib/source/scale_ratchet.rb` and nine tests.
That is a cross-tree rename of a ratchet table bought for one path segment, on a
checkout where the commit hook refuses a cross-tree commit for good reason.

## Cohesion census proposals measured and rejected (2026-09-08)

The census keeps proposing these, and each was read and refused. The three
per-app `Current` models stay: amber's and bsdports' are identical six-liners,
brgen's is a strict superset, and `Current.user` needs a bare constant. The
`brgen/app/models/user/*_associations.rb` files stay in the host, because
`brgen/README.md` keeps `User` there. The `honesty` shelf in
`gates/lib/source/` is three files united by a word, and `gates.yml` addresses
each by require and class. The ActiveRecord regroups (`item`, `declutter`,
`community`, `fedi`, `story`) collide — `OutfitItem` as `Item::Outfit` meets
`Outfit` — and each costs `class_name:` churn through strict-loading
associations for a path segment. All ten `RAILS/*.sh` scripts are reached.
`MASTER/tools/cohesion.rb <dir>` reads one directory deep; use `--census
--tree=RAILS --list` for the tree.

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

## Declined, with the reason (2026-09-13)

Each of these was proposed as backlog work and measured against the tree. They
are recorded so the next pass does not reopen them.

**Static error pages stay static and bilingual.** `public/404.html`, `422.html`
and `500.html` are served when Rails itself cannot render, so they cannot call
I18n or read the city from `Brgen::DomainRegistry`. The Norwegian line with an
English gloss marked `lang="en"` is the honest fallback for a page that cannot
know its reader. A generator for fourteen files that change once a year adds
machinery without removing a defect, and a skip link on a page with four links
and no repeated navigation skips nothing. Links on those pages stay relative,
so no city is sent to another city's host.

**No conditional GET on brgen's show pages.** `fresh_when` works on bsdports'
`ports#show` because that page is `public: true` and identical for everyone.
A brgen post, event or listing carries the reader's vote state, a CSRF token and
the flash, so an ETag keyed on the record would hand a signed-in reader the copy
the browser cached while signed out.

**The nav swiper is not `data-turbo-permanent`, and feed sort is not a frame.**
The swiper marks the active vertical on every page; a permanent element keeps the
mark from the page the reader came from. Turbo Drive already swaps the feed
without a reload and morphs with scroll preserved, and Turbo 8 prefetches every
link on hover unless told otherwise, so a frame would add a second navigation
model for no fewer requests.

**Web vitals are logged, not stored.** `WebVitalsController` writes one log line
per beacon. On a 1 GB box a table of beacons is a write on every page view for a
number the operator reads with a log query when a page is slow, and
Server-Timing on every production response answers the same question per
request.

**Takeaway's and marketplace's nav bars stay two partials.** They share a top
row and the SCSS, but marketplace carries a cart link and six sections against
takeaway's four, so one partial would need injected blocks for both halves. Two
fifty-line files are plainer than one partial with holes.

**The countdown controller stays eagerly registered.** It is mounted only on a
takeaway order page, but every file importmap pins is preloaded with
`modulepreload`, so lazy registration would move when the thirty-line module is
evaluated, not whether it is fetched. Saving that evaluation is not worth a
second loading path for one controller.

**`update_column` stays where it writes nothing a page caches.** The seven
calls in brgen set a message's link preview and expiry, an order's gclid and
conversion stamp, and two seeder backfills. No fragment cache keys on a message
or an order, and the seeder runs before any cache exists, so the stale-cache
trap this file names does not apply to them.

## Conditional GET is bsdports-only, and keyed on the viewer (2026-09-14)

bsdports answers `ports#show` and `maintainers#show` with `stale?`, and every
ETag there carries the signed-in user through `etag { }` in its
`ApplicationController`. The port page is not identical for everyone: it renders
the watch toggle, CSRF-bearing forms and comments, so an ETag keyed only on the
port lets a reader who signed in, or whose page gained a comment, revalidate a
stale copy. Rows that never touch their parent (comments, advisories, version
history) put their newest `updated_at` in the key at microsecond precision,
because a bare `Time` expands to whole seconds. The HTML index carries no public
max-age: it is root, where sign-in lands, and a browser serves a fresh cached
entry without asking. The RSS feed keeps its ten minutes.

brgen and amber stay without conditional GET for the reasons in "No conditional
GET on brgen's show pages": the user id in the key fixes the signed-out copy but
not vote state or badge counts, which no record's `updated_at` covers.

In an app without guests, `authenticated?` resumes the session itself, because
`allow_unauthenticated_access` skips `resume_session` there. A broadcast partial
renders with no key generator and stays signed-out.

## Toggles redirect, and morph is what makes that cheap (2026-09-14)

Favorite, like, dislike, rewind, collaboration, import, pins and group members
answer with a redirect, not a Turbo Stream. A redirect back to the page the form
sat on is a Turbo 8 page refresh, and `turbo_refreshes_with :morph, scroll:
:preserve` in `Shared::ApplicationSetup` declares that the refresh morphs in
place. A stream template per action would save one server render per click at
the cost of a second copy of each button's markup, and dating's swipe deck, the
import form and the collaboration page move the reader on anyway.

The argument holds because the declaration reaches the page.
`shared/config/initializers/turbo_refresh.rb` applies it to the view context
that renders the layout, not to the controller's `helpers` proxy, which is a
separate view context whose `provide :head` lands nowhere. Each app's layout
yields `:head`, and a rendered assertion per app (brgen and amber home, bsdports
ports) holds both meta tags in place.

A morph rebuilds the page from server HTML, so a surface whose DOM a library
builds in the browser loses that DOM unless it sits the morph out. The tiptap
editor does, once mounted, by cancelling `turbo:before-morph-element` for its
own element; `test/system/tiptap_morph_test.rb` types into a comment, refreshes,
and finds the text still there. The maplibre map would need the same guard, and
does not carry one yet because the one page that mounts it, maps home,
subscribes to no stream and is the target of no toggle's redirect, so nothing
refreshes it.

## System tests stay on Selenium (2026-09-14)

The gates drive Chrome over CDP through `gates/support/cdp_session.rb` because
they run under bare `ruby` outside any bundle, where no driver gem can be
loaded. The four system tests run inside each app's bundle, where Capybara needs
a driver gem either way; Cuprite would add one to three lockfiles, which is a
change made on vm23, to save nothing on four tests that already run headless
Chrome. brgen's `assert_accessible` uses axe through Capybara and works under
either driver.

---

Recovered from `DEPLOY/rails/shared/frontend/STIMULUS_COMPONENTS_BASELINE.md`,
deleted at `ee3a56e33`. Unlike the amber architecture record, this one did
**not** survive verbatim — the install shape it prescribed is now a gate
failure. What follows is the current contract; the divergences are listed at the
end so the old text is not restored by someone who finds it in history.

Enforced by `Deploy::StimulusComponentsGate`
(`RAILS/gates/lib/source/stimulus_components.rb`), run as `ruby
RAILS/gates/runner.rb stimulus_components`. That class is the source of truth.
This document explains it; it does not redefine it.

## Packages are vendored, not fetched

All 16 `@stimulus-components/*` packages live in `shared/vendor/javascript/` as
`@stimulus-components--<name>.js` and pin to those local files through
`shared/config/importmap_baseline.rb`. The gate fails if the baseline stops
pinning `vendor/javascript`, and fails on any vendored file under 100 bytes — an
empty vendor file pins successfully and breaks only at runtime.

Vendored: `animated-number`, `auto-submit`, `character-counter`,
`checkbox-select-all`, `clipboard`, `content-loader`, `dropdown`, `lightbox`,
`notification`, `password-visibility`, `popover`, `rails-nested-form`,
`read-more`, `reveal`, `sortable`, `textarea-autogrow`.

**Do not reintroduce CDN pins for these.** `pin` defaults to `preload: true`, so
every pin emits a `modulepreload` and the browser fetches it eagerly on first
paint — seven CDN pins once cost brgen 537 requests per page load and left Turbo
undefined. Any dynamic `import()` behind a preloaded pin is decorative.

The two CDN pins that remain are deliberate and documented in place:
`@rails/request.js` from jsDelivr (its ESM build uses extensionless relative
imports that a browser cannot resolve; the `dist` bundle can), and brgen's
Tiptap pair from esm.sh at `preload: false`.

## Registration

`shared/frontend/stimulus_boot.js` registers the controllers every app uses.
`stimulus_boot_social.js` (brgen + amber, not bsdports), `stimulus_boot_brgen.js`
and `stimulus_boot_amber.js` register the rest — split out so an app whose
views never mount a controller never imports its module either. `nested-form`
(the short name `@stimulus-components/rails-nested-form` registers under) is
amber-only, in `stimulus_boot_amber.js`; `checkbox-select-all` is brgen-only,
in `stimulus_boot_brgen.js`. `gates/lib/source/stimulus_components.rb` reads
all four files together as one registry.

`shared/frontend/stimulus_components.js` is deprecated and the gate fails if the
file reappears. The old document pointed at it as the ESM bootstrap for
non-importmap apps; there are no such apps.

## Forbidden

The gate scans every `.erb`/`.html` under `RAILS/` outside `vendor/`,
`public/assets/` and `node_modules/`, and fails on the legacy char-counter
markup: `data-controller="char-counter"`, `controller: "char-counter"`,
`char-counter-max-value`, `data-char-counter-target`. Use the vendored
`character-counter` component instead.

Per-app copies of shared controllers are also failures:
`char_counter_controller.js`, `textarea_autogrow_controller.js`,
`stimulus_rails_nested_form_controller.js` under any app's
`app/javascript/controllers/`. Compose, autosave, draft-store, media-picker and
scroll-reveal controllers live in `shared/frontend/` for the same reason; the
per-app copies in amber and brgen were removed.

## Progressive enhancement

Plain HTML must work without JavaScript. Every live search and async interaction
ships server-rendered initial content, plus loading, empty, no-results and error
states, with keyboard-operable controls. `journey_invariant` measures the no-JS
landmark parity in a real browser; `page_simulation` covers the state pages.

## Rails 8 defaults

Turbo Frames for replaceable panels, Turbo Streams for live updates, Solid Queue
for expensive work, Solid Cable for real-time status, Solid Cache for
index/feed/card/search fragments, Active Storage for media, signed IDs for
user-facing action tokens.

## What changed since the deleted version

- **Install shape.** The old text prescribed `esm.sh` pins for eleven packages.
  All are vendored now, and restoring those pins reintroduces the preload
  problem.
- **`stimulus_components.js`.** Named as the bootstrap for "direct module apps";
  now a gate failure if present.
- **Component list.** The old list of 19 packages to standardize on was a wish
  list. The vendored set is the real one, and the nine names in the gate's
  `REQUIRED_BOOT` are the enforced subset. `sound` and `speech-recognition` were
  on the wish list and are not vendored.
- **Rollout order.** It sequenced Blognet, Baibl and Hjerterom after the three
  real apps. Those are horizon entries in `apps.horizon.yml`, `agent: ignore`.
- **Scope.** `DEPLOY/rails` no longer exists; this applies to `RAILS/`.
