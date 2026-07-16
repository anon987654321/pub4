# Rails apps

3 active production Rails 8.1 apps under one shared engine. **Source of truth: `apps.yml`.** Horizon/aspirational work lives separately in `apps.horizon.yml`. Per-app notes: `<app>/AGENTS.md`. Backlog: `TODO.md`.

## Apps

| App | Domain | Port | Role |
|-----|--------|------|------|
| brgen | brgen.no | 38182 | City social + marketplace, dating, TV, takeaway, playlist |
| amber | amber.brgen.no | 61352 | Wardrobe / outfit intelligence |
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

## Gates

Unified runner:

```zsh
ruby RAILS/gates/runner.rb --all          # every registered gate
ruby RAILS/gates/runner.rb production     # or domain_alignment apps_yml …
ruby RAILS/gates/runner.rb --list
```

Individual scripts remain for `OPENBSD/bin/check*` and `gate_environment.rb` backward compat.

```zsh
ruby RAILS/check_production_gate.rb
ruby RAILS/rails_runtime_gate.rb          # static production checks; add --runtime for bundle/db/ci
cd RAILS/<app> && bin/ci                  # per-app RuboCop, Brakeman, bundler-audit, test
MASTER/bin/probe rails
ruby RAILS/gates/runner.rb visual_contract --capture ...
```

**In-process gate library** (`gates/lib/`, `Deploy::GateResult` from `OPENBSD/lib/gate_result.rb`):

| Class | Role |
|-------|------|
| `Deploy::ProductionGate` | Production config, CI, deploy contract; optionally nests master asset/TTS checks |
| `Deploy::MasterWebAssetsGate` | MASTER/web precompiled face assets + deploy-script wiring |
| `Deploy::MasterTtsGate` | TTS worker/supervisor contract |
| `Deploy::DomainAlignmentGate` | DNS/registry/master.json/relayd alignment |
| `Deploy::FrontendProductionGate` | Layout/CSS contract + MASTER/web face wiring |
| `Deploy::FrontendAuditorGate` | Shared frontend auditor (0 warnings) |
| `Deploy::StimulusComponentsGate` | Stimulus-components adoption + importmap pins |
| `Deploy::SharedWiringGate` | Per-app shared routes, importmap, public assets, Stimulus |

`check_production_gate.rb`, `master_web_assets_gate.rb`, and `master_tts_gate.rb` are thin CLI wrappers. `rails_runtime_gate.rb` calls `Deploy::ProductionGate.run(skip_nested: true)` in-process (avoids re-running nested master gates when `production` and `rails_runtime` both run under `--all`). Set `GATE_SKIP_NESTED=1` when shelling out to `check_production_gate.rb` if you need the same skip from a subprocess.

`domain_alignment_gate.rb` already uses `Deploy::GateResult`; other gates are migrating incrementally. `release_gate.rb` still shells out to several gates — see `TODO.md`.

`visual_contract_gate.rb` defines the seeded desktop, compact, and mobile crawl for each app's happy, empty, error, and offline states. Under an app bundle, add `--capture --app <name> --base <url>` to write screenshots plus a manifest containing route, status, title, screenshot SHA-256, console errors, and accessibility violations. Running via `runner.rb --all` without `--capture` only validates route/lens data shapes — not a visual regression pass.

On OpenBSD, use the package-qualified Ruby 3.4 commands:

```zsh
cd /home/dev/pub4/RAILS/<app>
bundle34 check
zsh OPENBSD/vps_ci.sh brgen   # vm23: mutex + load gate
bundle34 exec bin/ci            # direct (auto-guarded on VPS via Pub4::CiGuard)
```

## Apps.yml validator

Registered in `gates/runner.rb` as `apps_yml`:

```zsh
ruby RAILS/gates/runner.rb apps_yml
ruby RAILS/gates/apps_yml_validator.rb   # standalone, same checks
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
| playlist / spilleliste | playlist |
| takeaway | takeaway |
| tv | tv |
| maps | maps |
| messenger | conversations |
| dating | dating |
| ai | MASTER relay → :53187 |

Scoped roots use single-prefixed helpers (`marketplace_root_path`, `maps_root_path`) — not double-prefixed `marketplace_marketplace_root_path`. `ApplicationHelper#marketplace_root_url` delegates to `Rails.application.routes.url_helpers` so it does not shadow the route helper.

**Standalone apps:** amber (amber.brgen.no:61352), bsdports (bsdports.org:47312).

**Operator UI:** MASTER domain bar (`MASTER/web/public/domain_cluster.js`), CLI `/domain <name>` via `SubdomainOrchestrator`.

Gate: `ruby RAILS/domain_alignment_gate.rb`

## Production readiness

Last updated: 2026-07-15.

**Gates:**

```sh
ruby RAILS/gates/runner.rb --all
ruby RAILS/rails_runtime_gate.rb
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

**Blockers:**

1. City vanity TLS — `OPERATOR.sh` stage 1 must issue certs for every apex in `ALL_DOMAINS`; relayd keypairs only exist for certs on disk.
2. Domain drift — `master.json`, `apps.yml`, `OPERATOR.sh`, and `relayd.conf` must agree.
3. relayd restart after route changes.
4. Seeds skipped in production unless `RUN_PRODUCTION_SEEDS=1`.
5. openrsync broken on vm23 — deploy uses git pull.

**Deploy:**

```sh
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
cd /home/dev/pub4 && git pull origin main
SKIP_MASTER_SCAN=1 zsh OPENBSD/vps_on_vm_install.sh
doas rcctl restart relayd
ruby34 OPENBSD/health_check.rb --public --all-ready-apps
```

## Recent changes (2026-07-15)

- **Gates:** `gates/runner.rb` registers `apps_yml` and `shared_wiring`; production/master/domain/frontend/stimulus gates callable in-process via `gates/lib/` and `Deploy::GateResult`. `release_gate.rb` no longer subprocesses those four gates.
- **Shared wiring gate:** `ruby RAILS/gates/shared_wiring_gate.rb` — verifies all apps eval shared routes/importmap, ship error pages, and register shared Stimulus controllers.
- **Shared wiring:** social routes eval in all three apps; Stimulus compose/save controllers in `shared/frontend/`.
- **Design/PWA:** line-height and touch-target fixes; reduced-motion guards; error pages in each app `public/`.
- **Performance:** Active Storage preload on posts, deals, outfits, demo wardrobe, user profiles, dating matches, and TV channels.
- **Tests:** model coverage for brgen `Dating::Match`, `Marketplace::Order`, `Takeaway::Order`, `Vote`; amber `Outfit`, `WardrobeItem`, `Connection`; bsdports `User`; plus `shared_wiring_gate_test.rb` and gate contracts.
- **Deploy scripts:** `@core.sh` / `@database.sh` / `@runtime_gate.sh` / `@scaffold.sh` / `@service.sh` / `@sync.sh` are thin shims over `_*.sh` (same pattern as `@deploy.sh`).

**Still open** (see `TODO.md`): `runner.rb --all` still subprocesses each gate; broader controller coverage; `apps.yml` `planned` features marked `agent: ignore` (pgvector, live streaming, monetization).

## Deploy scripts

Canonical orchestrator: `_deploy.sh`. `deploy.sh` and `@deploy.sh` are thin entry shims. Per-app `brgen.sh` / `amber.sh` / `bsdports.sh` source the shared contract.

---
*Updated 2026-07-15 after RAILS TODO pass (routing, Stimulus, design audit, gate flattening).*