# Rails apps

3 active production Rails 8.1 apps under one shared engine. **Source of truth: `apps.yml`.** Horizon/aspirational work lives separately in `apps.horizon.yml`. Per-app notes: `<app>/AGENTS.md`.

## Apps

| App | Domain | Port | Role |
|-----|--------|------|------|
| brgen | brgen.no | 38182 | City social + marketplace, dating, TV, takeaway, playlist |
| amber | amber.brgen.no | 61352 | Wardrobe / outfit intelligence |
| bsdports | bsdports.org | 47312 | Ports search and advisories |

Deploy: `cd RAILS && doas zsh OPERATOR.sh` (default: brgen) or `doas zsh OPERATOR.sh <app>`

## Contract

1. Tracked tree at `RAILS/<app>/` copied to `/home/<app>/app`
2. `pub4-shared` via `path: '../shared'` in Gemfile
3. Ruby 3.4, `RAILS_ENV=production`, Falcon behind relayd
4. `config.assume_ssl = true` — no `force_ssl`
5. Health at `/up` (liveness) and `/health` (Solid Cache/Queue/DB depth); rc.d per app in `OPENBSD/etc/rc.d/`
6. Secrets in `/etc/<app>.env` on VPS — no `config/master.key` in git

## Shared

`RAILS/shared/` — engine gem, concerns, Stimulus baseline, `WIRING_NOTES.md`

Copy-tree deploy mirrors shared at `/home/<app>/shared` (sibling of `app/`, not inside it). CI and jobs resolve OPERATOR tools via `Pub4::DeployPaths` (`shared/lib/pub4/deploy_paths.rb`) using `PUB4_RAILS_ROOT` or `/home/dev/pub4/OPENBSD/…` on vm23.

```ruby
include Shared.concern(:Votable)   # Notifiable, ActivityTrackable, GeoLocatable, …
```

## Gates

```zsh
ruby RAILS/check_production_gate.rb
cd RAILS/<app> && bin/ci    # per-app RuboCop, Brakeman, bundler-audit, test
MASTER/bin/probe rails
ruby RAILS/visual_contract_gate.rb
```

`visual_contract_gate.rb` defines the seeded desktop, compact, and mobile crawl for each app's happy, empty, error, and offline states. Under an app bundle, add `--capture --app <name> --base <url>` to write screenshots plus a manifest containing route, status, title, screenshot SHA-256, console errors, and accessibility violations.

On OpenBSD, use the package-qualified Ruby 3.4 commands:

```zsh
cd /home/dev/pub4/RAILS/<app>
bundle34 check
zsh OPENBSD/sh/vps_ci.sh brgen   # vm23: mutex + load gate
bundle34 exec bin/ci            # direct (auto-guarded on VPS via Pub4::CiGuard)
```

## PWA

Workbox workers via `/service-worker`. Rebuild: `npm ci && npm run build:pwa` from this directory. Source: `shared/pwa/service_worker.js`.

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

**Standalone apps:** amber (amber.brgen.no:61352), bsdports (bsdports.org:47312).

**Operator UI:** MASTER domain bar (`MASTER/web/public/domain_cluster.js`), CLI `/domain <name>` via `SubdomainOrchestrator`.

Gate: `ruby RAILS/domain_alignment_gate.rb`

## Production readiness

Last updated: 2026-06-28. Repo gates pass locally; public readiness needs VPS proof and city vanity TLS.

**Gates:**

```sh
ruby RAILS/check_production_gate.rb
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

Rails uses `Pub4::DeployPaths` to resolve MASTER media tools from a source checkout or a VPS copy-tree; never assume `Rails.root/../../postpro`. Newsletter hero rendering can use the same postpro/repligen pair as MASTER. Keep provider tokens in the app’s `/etc/<app>.env`; do not add them to Rails credentials or source. MASTER’s natural-language media routing is local to the agent runtime, while Rails callers should use the shared service boundary so jobs remain observable and retryable.

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
SKIP_MASTER_SCAN=1 zsh OPENBSD/sh/vps_on_vm_install.sh
doas rcctl restart relayd
ruby34 OPENBSD/health_check.rb --public --all-ready-apps
```
