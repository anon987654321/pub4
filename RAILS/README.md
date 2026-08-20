# Rails apps

3 active production Rails 8.1 apps under one shared engine. **Source of truth: `apps.yml`.** Horizon/aspirational work lives separately in `apps.horizon.yml`. Per-app notes: `<app>/AGENTS.md`. Debt: `MASTER/DEBT.md`, operator debt in `OPENBSD/data/debt.yml`.

brgen is **one process, many hosts**: every city apex in
`Brgen::DomainRegistry` (feed) plus namespaced engines on subdomains
(`dating.brgen.no`, `dating.lsangeles.com`, `marketplace.lndon.uk`, …). Apexes
are usually the city with a vowel dropped. Not a folder of apps. Read
`brgen/AGENTS.md` before touching a vertical.

## Apps

| App | Domain | Port | Role |
|-----|--------|------|------|
| brgen | brgen.no (+ city apexes) | 38182 | City network: feed at the apex, vertical engines on subdomains |
| amber | amber.brgen.no | 61352 | Wardrobe / outfit intelligence (separate app, not a brgen subapp) |
| bsdports | bsdports.org | 47312 | Ports search and advisories |

Deploy: `cd RAILS && doas zsh deploy.sh` (default: brgen) or `doas zsh deploy.sh <app>`

## Contract

1. Tracked tree at `RAILS/<app>/` copied to `/home/<app>/app`
2. `pub4-shared` via `path: '../shared'` in Gemfile
3. Ruby 3.4, `RAILS_ENV=production`, Falcon behind relayd
4. `config.assume_ssl = true` — no `force_ssl`
5. Health at `/up` (liveness) and `/health` (Solid Cache/Queue/DB depth); rc.d per app in `OPENBSD/etc/rc.d/`
6. Secrets in `/etc/<app>.env` on VPS — no `config/master.key` in git

## Shared

`RAILS/shared/` — engine gem, concerns, Stimulus baseline, `WIRING_NOTES.md`

Copy-tree deploy mirrors shared at `/home/<app>/shared` (sibling of `app/`, not inside it). CI and jobs resolve OPENBSD tools via `Pub4::DeployPaths` (`shared/lib/pub4/deploy_paths.rb`) using `PUB4_RAILS_ROOT` or `/home/dev/pub4/OPENBSD/…` on vm23.

```ruby
include Shared.concern(:Votable)   # Notifiable, ActivityTrackable, GeoLocatable, …
```

**Social routes** — all three apps eval the same file:

```ruby
instance_eval(File.read(File.expand_path("../../shared/config/routes/social.rb", __dir__)))
```

Defines `notifications`, `reactions`, and `reports`. Contract test: `ruby RAILS/test/shared_social_routes_test.rb`.

**Shared Stimulus** — compose/save/upload controllers live in `shared/frontend/` and register via `stimulus_boot.js` + `shared/config/importmap_baseline.rb`:

- `autosave_controller.js`
- `draft_store_controller.js`
- `media_picker_controller.js`
- `feed_compose_controller.js` (per-app expanded class via `feed_compose_expanded_class_value`)
- `scroll_reveal_controller.js`

Per-app copies of these controllers were removed from amber/brgen.

## Constitutional command chain

RAILS is also passed through MASTER's chain of commands — the same
`/scan → /fix → /scan → /critique → /review` loop MASTER runs on itself. Drive
it from the MASTER tree:

```zsh
cd MASTER && ruby bin/gate                 # full scan→fix→scan→critique→review
cd MASTER && MASTER_GATE_SCAN_ONLY=1 ruby bin/gate   # CI/preflight (no /fix)
# or: ruby bin/gate --scan-only
```

`bin/gate` runs two command sets through `bin/cli`: `:master` scans `.`, then
`:deploy` scans `../RAILS` and `../OPENBSD`. Full mode ends with
`git diff --exit-code` so a `/fix` pass cannot leave a dirty tree. Scan-only
mode is safe for CI (no autonomous edits). Counterpart to `gates/runner.rb`
(deploy contract) and per-app `bin/ci` (RuboCop/Brakeman/tests).

## Gates

Unified runner:

```zsh
ruby RAILS/gates/runner.rb --all          # every registered gate
ruby RAILS/gates/runner.rb production     # or domain_alignment apps_yml …
ruby RAILS/gates/runner.rb constitutional_scan   # MASTER /scan --no-autofix preflight
ruby RAILS/gates/runner.rb --list
```

`OPENBSD/bin/check-rails` and `gate_environment.rb` go through the same runner,
naming gates rather than pointing at files. The two entrypoints below are not
gates in the registry sense and stay callable on their own:

```zsh
ruby RAILS/gates/runner.rb production
ruby RAILS/gates/rails_runtime.rb        # static production checks; add --runtime for bundle/db/ci
cd RAILS/<app> && bin/ci                  # per-app RuboCop, Brakeman, bundler-audit, test
MASTER/bin/probe rails
VISUAL_CAPTURE=1 VISUAL_CAPTURE_APP=brgen VISUAL_CAPTURE_BASE=http://127.0.0.1:38182 ruby RAILS/gates/runner.rb visual_contract
```

**In-process gate library** (`gates/lib/`, `Deploy::GateResult` from `OPENBSD/lib/gate_result.rb`):

| Class | Role |
|-------|------|
| `Deploy::ProductionGate` | Production config, CI, deploy contract; optionally nests master asset/TTS checks |
| `Deploy::MasterWebAssetsGate` | MASTER/web precompiled face assets + deploy-script wiring |
| `Deploy::MasterTtsGate` | TTS worker/supervisor contract |
| `Deploy::DomainAlignmentGate` | DNS/registry/deploy_inventory.json/relayd alignment |
| `Deploy::FrontendProductionGate` | Layout/CSS contract + MASTER/web face wiring |
| `Deploy::FrontendAuditorGate` | Shared frontend auditor (0 warnings) |
| `Deploy::StimulusComponentsGate` | Stimulus-components adoption + importmap pins |
| `Deploy::SharedWiringGate` | Per-app shared routes, importmap, public assets, Stimulus |
| `Deploy::ConstitutionalScanGate` | MASTER `/scan --no-autofix` preflight on RAILS apps |

**Every gate is declared in `gates/gates.yml` and nowhere else** — one row per
gate carrying its `require`, its `Deploy::*` class, its pass line, and the
composite that already runs it as a leaf. `runner.rb` reads that file; so does
`OPENBSD/lib/gate_environment.rb`'s deploy-time integrity chain, by gate name
rather than by path. Adding a gate is one row.

This replaced four hand-maintained tables that had to agree with each other
(`GATE_MAP`, `IN_PROCESS`, `SUBPROCESS_ONLY`, `GATE_COVERED_BY`) plus 37 shim
scripts at the RAILS root whose only job was to require a class the runner
already loaded in-process.

Most gates run in-process and return a `Deploy::GateResult`; only `release`,
`rails_runtime`, and `visual_contract` still subprocess (bundle steps, argument
forwarding), declared with `script:` instead of `require:`/`class:`.
`gates/rails_runtime.rb` calls `Deploy::ProductionGate.run(skip_nested: true)`
directly, which avoids re-running nested master gates when `production` and
`rails_runtime` both run under `--all`; `GATE_SKIP_NESTED=1` gets the same skip
from `runner.rb production`, declared on that gate as an `env_flags:` row.
Horizon `apps.yml` features remain `agent: ignore` — see `MASTER/DEBT.md` /
`OPENBSD/data/debt.yml`.

`gates/visual_contract.rb` defines the seeded desktop, compact, and mobile crawl for each app's happy, empty, error, and offline states. Under an app bundle, add `--capture --app <name> --base <url>` to write screenshots plus a manifest containing route, status, title, screenshot SHA-256, console errors, and accessibility violations. `runner.rb` forwards `--capture` when `VISUAL_CAPTURE=1` (optional `VISUAL_CAPTURE_APP`, `VISUAL_CAPTURE_BASE`). Running via `runner.rb --all` without capture only validates route/lens data shapes — not a visual regression pass.

On OpenBSD, use the package-qualified Ruby 3.4 commands:

```zsh
cd /home/dev/pub4/RAILS/<app>
bundle34 check
zsh OPENBSD/vps_ci.sh brgen   # vm23: mutex + load gate
bundle34 exec bin/ci            # direct (auto-guarded on VPS via Pub4::CiGuard)
```

## Rendered gates (browser-measured)

The gates above analyse source. These measure what Chrome actually laid out.

```zsh
ruby RAILS/gates/runner.rb rendered_suite    # every browser-backed gate
ruby RAILS/gates/runner.rb geometry          # or a single leaf
ruby RAILS/gates/runner.rb flow_journey gate_mutation   # pure, no browser needed
GATE_SURFACES=brgen/marketplace ruby RAILS/gates/runner.rb geometry   # narrow a run
```

No gem dependency: `gates/support/cdp_session.rb` speaks the Chrome DevTools
Protocol over a WebSocket it implements with stdlib only. ferrum/selenium exist
only inside app bundles, and gates run under bare `ruby`. Chrome is found via
`CHROME_PATH` or the usual locations; without it every gate here degrades to a
warning rather than failing.

| Gate | Measures |
|------|----------|
| `geometry` | Rendered Fitts targets, centre-pixel occlusion, horizontal overflow, computed contrast, token conformance, 8px rhythm |
| `reflow` | 16-width sweep 320→1600px; overflow at any width, breakpoint fingerprint |
| `keyboard_flow` | Real Tab presses: skip-link position, document order, focus-ring visibility |
| `journey_invariant` | Idempotence, back-button equivalence, no-JS landmark parity |
| `cross_app` | Shared chrome and layout-mounted Stimulus agree across all three apps |
| `layout_snapshot` | Committed rect/style baselines in `gates/data/layout_snapshots/` |
| `flow_journey` | `gates/data/flows.yml` journeys with postconditions on state |
| `gate_mutation` | Breaks good fixtures and asserts the suite notices |

**Why geometry rather than grepping CSS.** `first_screen` asserts
`_nav.scss` contains the string `min-height: 44px`. `geometry` asserts the box
is 44px tall (`--tap-min`) in a real browser at that viewport, that nothing covers its centre
pixel, and that its text clears WCAG AA against its composited background — with
`var()`/`oklch`/`color-mix` resolved, which `DesignMetrics.parse_hex`
structurally cannot do.

**Subdomain verticals are reachable.** Chrome launches with
`--host-resolver-rules`, so `markedsplass.brgen.no` and the other verticals are
probed in a browser. Selenium could not set a `Host` header, which is why
`design_metrics_gate`'s optional probe skips markedsplass entirely.

**Snapshots, not screenshots.** `visual_contract_gate` reads its baseline from
whatever PNG sits at the destination path and then overwrites it, and
`RAILS/visual_contract/*.png` is gitignored — so a regression is reported once,
becomes the new baseline, and does not exist at all on a fresh checkout.
`layout_snapshot` commits a rect/style JSON instead: tracked, reviewable,
immune to antialiasing and GPU differences, and a diff reads
`nav.tab-bar: h 48→32` rather than "8,214 pixels changed". Baselines are
accepted only under `GATE_SNAPSHOT_UPDATE=1`, deliberately **not** under
`GATE_AUTOFIX` — blessing a regression is the behaviour this replaces.

**Autofix.** `geometry` and `reflow` write corrective rules into a generated
`_autofix_geometry.scss` per app, register the `@use`, and rebuild CSS before
remeasuring. Additive and quarantined on purpose: a rendered violation names a
selector, not a source rule, and the cascade rather than any one declaration
produced the box — so rewriting a guessed rule would be a guess. Revert by
deleting the partial and its `@use` line. Rounds and dry-run come from the
shared `GateAutofix` policy (`GATE_AUTOFIX=0`, `GATE_AUTOFIX_DRY=1`,
`GATE_AUTOFIX_ROUNDS=n`).

Token colours are never rewritten automatically — `design_metrics` prints the
hex that would clear AA and leaves the brand decision to a human.

Unit coverage: `ruby RAILS/test/gates/rendered_gates_test.rb`.

## Apps.yml validator

Registered in `gates/gates.yml` as `apps_yml`:

```zsh
ruby RAILS/gates/runner.rb apps_yml
ruby RAILS/gates/runner.rb apps_yml   # same checks, named once
```

Validates: app directories exist, deploy scripts present, unique ports/domains, feature `status: done|planned`.

## PWA

Workbox workers via `/service-worker`. Rebuild: `npm ci && npm run build:pwa` from this directory. Source: `shared/pwa/service_worker.js`.

All three apps compile the same network-first-for-HTML service worker logic. `/offline` renders the shared partial. Styled `404`/`422`/`500` pages from `shared/public/` are copied into each app's `public/` at deploy.

**Design audit** (MASTER `MobilePwaOperator#audit_all_deploy`):

```ruby
# from MASTER/, ruby -Ilib -e 'require "master"; pp Master::Rails::MobilePwaOperator.new.audit_all_deploy'
```

As of 2026-07-15: amber, brgen, and bsdports are **green** on real design violations (line-height, touch targets, reduced-motion). amber still reports two logo `line-height: 0` false positives in `_brand.scss` (standard SVG collapse idiom). Vendored `lightgallery.css` findings are excluded from counts — do not hand-edit.

## Multi-tenant routing

Subdomain constraints live in `brgen/config/routes.rb` via `Brgen::DomainRegistry`.

**brgen verticals:**

| Subdomain | Module |
|-----------|--------|
| markedsplass / marketplace aliases | marketplace |
| playlist | playlist |
| takeaway | takeaway |
| tv | tv |
| maps | maps |
| messenger | conversations |
| dating | dating |
| ai | MASTER relay → :53187 |

Scoped roots use single-prefixed helpers (`marketplace_root_path`, `maps_root_path`) — not double-prefixed `marketplace_marketplace_root_path`. `ApplicationHelper#marketplace_root_url` delegates to `Rails.application.routes.url_helpers` so it does not shadow the route helper.

**Standalone apps:** amber (amber.brgen.no:61352), bsdports (bsdports.org:47312).

**Operator UI:** CLI `/domain <name>` via `SubdomainOrchestrator`. The browser half is `window.MASTER_ACTIVE_DOMAIN`, read by `MASTER/web/public/chat_actions.js`. The dedicated domain bar has no source in the tree: `domain_cluster.js` went in `930a35ca5` and only the precompiled `MASTER/web/public/assets/domain_cluster-3bf218f7.js` survives, which means it ships and cannot be rebuilt. Treat it as vendored until someone restores the source.

Gate: `ruby RAILS/gates/runner.rb domain_alignment`

## Production readiness

Last updated: 2026-07-15.

**Gates:**

```sh
ruby RAILS/gates/runner.rb --all
ruby RAILS/gates/rails_runtime.rb
ruby OPENBSD/deploy_smoke_gate.rb
cd MASTER && bin/probe all
```

VPS per app:

```sh
cd /home/dev/pub4/RAILS/<app>
bundle34 check
RAILS_ENV=production bundle34 exec rails db:prepare
bundle34 exec bin/ci
curl -fsS http://127.0.0.1:<port>/up
ruby34 OPENBSD/health_check.rb --public --all-ready-apps
```

**Status:** brgen/amber/bsdports are ready when VPS `bin/ci` + public `/up` pass; master (ai.brgen.no) is ready on auth smoke + `/up`. Ship criteria: `MASTER/data/operator_playbook.yml`.

## Media integration

Rails uses `Pub4::DeployPaths` to resolve MASTER media tools from a source checkout or a VPS copy-tree; never assume `Rails.root/../../postpro`. Newsletter hero rendering can use the same postpro/repligen pair as MASTER. Keep provider tokens in the app's `/etc/<app>.env`; do not add them to Rails credentials or source. MASTER's natural-language media routing is local to the agent runtime, while Rails callers should use the shared service boundary so jobs remain observable and retryable.

**Blockers:** `BLOCKERS.md` — four entries, each with owner, unblock criteria,
and the check that covers it. Kept there rather than here because two of the
five sentences this section used to carry had gone stale unnoticed.

**Deploy:**

```sh
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
cd /home/dev/pub4 && git pull origin main
SKIP_MASTER_SCAN=1 zsh OPENBSD/vps_on_vm_install.sh
doas rcctl restart relayd
ruby34 OPENBSD/health_check.rb --public --all-ready-apps
```

## Recent changes (2026-08-02)

Three endpoints answered 500 in production while 148 simulated pages passed, because `PageInventory` globbed each app's own `app/views` and never `shared/app/views`. Everything the engine renders — account settings, notifications, both password screens, two-factor — sat outside every gate.

- **Shared pages are inventoried.** `PageInventory::SHARED_PAGES` declares them, one row per host app; `uncovered_shared_views` fails `page_simulation` on any non-partial shared view without a row. Inventory 148 → 162.
- **`/sitemap.xml`** raised `NameError` in all three apps: `SitemapBuilder` used `Builder::XmlMarkup` and nothing required `builder` once Rails 8 dropped `ActiveModel::Serializers::Xml`. `builder` and `csv` are declared engine dependencies now.
- **`/account/export`** called `Shared::AccountExporter`, which nobody had written. It exists: reflective over the User model, so one implementation covers three unrelated schemas.
- **amber's social stack** was routed and controllered with no tables. Migration `20260802180000`.
- **Dead routes.** Bare `resource :session` / `resources :passwords` routed seven actions at controllers implementing three and four. The runtime gate now asks each booted app whether every route resolves to an action method — `rails_runtime.rb --runtime`.
- **`i18n_resolution_test`** asserts every defaultless `t()` resolves in each app's own locales plus the engine's; bsdports had been shipping `translation_missing` markup into a live region.

## Recent changes (2026-07-15)

- **Gates:** every gate is a row in `gates/gates.yml`; production/master/domain/frontend/stimulus gates run in-process via `gates/lib/` and `Deploy::GateResult`. `gates/release.rb` no longer subprocesses those four gates.
- **Shared wiring gate:** `ruby RAILS/gates/runner.rb shared_wiring` — verifies all apps eval shared routes/importmap, ship error pages, and register shared Stimulus controllers.
- **Shared wiring:** social routes eval in all three apps; Stimulus compose/save controllers in `shared/frontend/`.
- **Design/PWA:** line-height and touch-target fixes; reduced-motion guards; error pages in each app `public/`.
- **Performance:** Active Storage preload on posts, deals, outfits, demo wardrobe, user profiles, dating matches, and TV channels.
- **Tests:** model coverage for brgen `Dating::Match`, `Marketplace::Order`, `Takeaway::Order`, `Vote`; amber `Outfit`, `WardrobeItem`, `Connection`; bsdports `User`; plus `shared_wiring_gate_test.rb` and gate contracts.
- **Deploy scripts:** the `@core.sh` / `@database.sh` / `@runtime_gate.sh` / `@scaffold.sh` / `@service.sh` / `@sync.sh` / `@deploy.sh` backward-compat shims have been retired; `_*.sh` are the canonical scripts.

**Debt / horizon** (see `MASTER/DEBT.md`, `OPENBSD/data/debt.yml`, `apps.horizon.yml`): `release`/`rails_runtime`/`visual_contract` still subprocess; `apps.yml` `planned` + `agent: ignore` (pgvector, live streaming, monetization). Solidus: Gemfile flag + mount stub ready — full `solidus:install` is staging-only (not on 1GB vm23). Deploy smoke: `sh OPENBSD/bin/deploy-smoke.sh`. Mutation request specs: brgen `vertical_mutations_test`, amber `wardrobe_mutations_test`, bsdports `port_mutations_test`. Family contracts run via `OPENBSD/bin/check-rails` and `check-full`.

## Deploy scripts

Canonical orchestrator: `_deploy.sh`. `deploy.sh` is a thin entry shim. Per-app `brgen.sh` / `amber.sh` / `bsdports.sh` source the shared contract.

---
*Updated 2026-08-02 — shared-engine pages inventoried; three fleet-wide 500s closed.*
