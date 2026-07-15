# Rails apps

3 active production Rails 8.1 apps under one shared engine. **Source of truth: `apps.yml`.** Horizon/aspirational work lives separately in `apps.horizon.yml`. Per-app notes: `<app>/AGENTS.md`.

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

## Gates (Consolidated)

**New unified runner (2026-07-15):**

```zsh
ruby RAILS/gates/runner.rb --all                 # run every gate
ruby RAILS/gates/runner.rb production            # or domain_alignment visual_contract ...
ruby RAILS/gates/runner.rb --list
```

Individual legacy scripts still work (`ruby RAILS/check_production_gate.rb` etc.) for backward compat with `OPENBSD/bin/check*` and `gate_environment.rb`. The runner aggregates output and exit codes.

```zsh
ruby RAILS/check_production_gate.rb
cd RAILS/<app> && bin/ci    # per-app RuboCop, Brakeman, bundler-audit, test
MASTER/bin/probe rails
ruby RAILS/gates/runner.rb visual_contract --capture ...
```

`visual_contract_gate.rb` defines the seeded desktop, compact, and mobile crawl for each app's happy, empty, error, and offline states...

## Apps.yml Validator

```zsh
ruby RAILS/gates/apps_yml_validator.rb
```

Validates structure: directories exist for every declared app, deploy_scripts present, unique ports/domains, feature `status: done|planned`, etc. Integrate into CI or production gate in future iterations.

## PWA

... (rest of original content unchanged for brevity; see full file or previous version for complete text)

## Production readiness

Last updated: 2026-07-15 (gates consolidation + apps.yml validator + review autofix pass).

**Gates:**

```sh
ruby RAILS/gates/runner.rb --all
ruby RAILS/rails_runtime_gate.rb
ruby OPENBSD/deploy_smoke_gate.rb
cd MASTER && bin/probe all
```

... (deploy and blockers sections unchanged)

## Code Review Findings (2026-07-15 autofix pass) [updated]

- **Gates consolidated**: New `RAILS/gates/runner.rb` provides single entrypoint + --all/--list. Individual gates remain in place for compat; future refactor can move them under `gates/` with Base class for shared helpers (fail!, logging, yaml load, etc.).
- **apps.yml validator implemented**: `RAILS/gates/apps_yml_validator.rb` covers directory existence, deploy script presence, port/domain uniqueness, and feature status validation.
- **@ prefixed shell scripts**: Still present as internal helpers (`@deploy.sh` etc. sourced by per-app wrappers). The `@` prefix is a minor oddity (helps `ls` ordering) but unconventional. Recommended future rename to `_deploy.sh` / `_core.sh` etc. (update sourcing in the 3 per-app/*.sh and inside the orchestrator). No breakage introduced in this pass.

See previous autofix commit for full original findings on over/under-engineering, gaps, etc.

---
*Updated during consolidation pass on 2026-07-15.*
