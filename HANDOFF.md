# pub4 operator handoff

Repository: local checkout or VPS `/home/dev/pub4`, remote `anon987654321/pub4`, branch `main`.

SSH / VMM / GitHub workstation setup: `DEPLOY/openbsd/SSH_ACCESS.md` (`ssh brgen`, `ssh server4`, GitHub key split).

Checkbox backlogs (`TODO.md`, `MASTER/TODO.md`, `DEPLOY/TODO.md`) were retired 2026-06-24. Ship readiness is **executable proof**, not markdown checkboxes. See `MASTER/data/operator_playbook.yml` and `DEPLOY/rails/PRODUCTION_READINESS.md`.

## Intent

Strict `rules.yml` adherence across MASTER and DEPLOY. Rails production on OpenBSD (vm23) is the deploy target. Do not overclaim readiness — prove gates on the host that matters.

## Non-negotiable constraints

- TLS at `relayd`; Rails `config.assume_ssl = true` only — never `force_ssl`.
- No tracked `config/master.key`.
- Ruby 3.4 (`ruby34` / `bundle34`) on VPS; Mac may use rbenv 3.4 for full Rails runtime gates.
- VPS-installed files must live under `DEPLOY/openbsd/` and be committed.

## Local verification (before push)

```sh
ruby bin/probe all
ruby DEPLOY/rails/domain_alignment_gate.rb
ruby DEPLOY/rails/release_gate.rb
ruby DEPLOY/rails/check_phantom_foreign_keys.rb
cd MASTER && bundle exec rake test
```

## VPS proof (after push or pull)

```sh
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
cd /home/dev/pub4 && git pull origin main
SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_on_vm_install.sh   # when tree changed
doas rcctl restart master                                 # after MASTER/web edits
ruby34 DEPLOY/openbsd/health_check.rb
doas rcctl check master brgen amber blognet bsdports baibl hjerterom

# Per app (1 GiB VM — one at a time):
doas sh -c 'su -m brgen -c "cd /home/brgen/app && bundle34 exec bin/ci"'

# MASTER web face:
cd /home/dev/pub4/MASTER && MASTER_LOW_RESOURCE=1 bundle34 exec ruby bin/smoke --web
curl -fsS https://ai.brgen.no/up
```

Copy-tree deploys run each app from `/home/<app>/app`. `bin/ci` sets `PUB4_RAILS_ROOT=/home/dev/pub4/DEPLOY/rails` when the monorepo tree is present so cross-app contract tests resolve sibling apps.

## VPS recovery (SSH blocked)

```sh
ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam
vmctl console vm23
# login, then: doas pfctl -t bruteforce -T flush
```

## Deep references

| Topic | File |
|-------|------|
| Agent entry | `MASTER/QUICKSTART.md` |
| Production lessons | `MASTER/data/operator_playbook.yml` (`bin/playbook`) |
| Gate matrix | `DEPLOY/rails/PRODUCTION_READINESS.md` |
| Rails wiring | `DEPLOY/rails/shared/WIRING_NOTES.md` |
| Feature gaps | `DEPLOY/rails/apps.yml` |
| Snapshots | `MASTER_snapshot.md`, `DEPLOY_snapshot.md` |
| OpenBSD deploy | `DEPLOY/openbsd/README.md` |

## Known operator blockers

1. Apex DNS: `baibl.no`, `blognet.no`, `hjerterom.no` may NXDOMAIN off-VM — `*.brgen.no` subdomains are live.
2. `relayd` stale backend tables after mass restarts — `doas rcctl restart relayd` or wait for cron watchdog.
3. `resource_guard.sh` may shed optional apps — touch `/var/db/pub4_all_apps` or run `start_all_apps.sh`.
4. `openrsync` broken on vm23 — deploy uses tar sync.

## VPS proof log

### 2026-06-25 (commit `41c69225b+`)

| Check | Result |
|-------|--------|
| `ruby34 DEPLOY/openbsd/health_check.rb` | pass |
| `doas rcctl check` (all 7 services) | pass |
| Local `/up` on all ports | 200 |
| `https://ai.brgen.no/up` | pass |
| `MASTER_LOW_RESOURCE=1 bundle34 exec ruby bin/smoke --web` | clean (7 checks) |
| `deploy_backlog_test` on VPS brgen | pass (after `PUB4_RAILS_ROOT` fix) |
| `bin/ci` brgen (env override) | partial — importmap/rubocop/brakeman/bundler-audit/seeds pass; 1 test fail `live_search_test` empty-query count on `.none` scope |
| copy-tree `config/ci.rb` on VPS | stale — `/home/brgen/app/config/ci.rb` inlined old CI without `BUNDLER_AUDIT_UPDATE` / `NPM_CONFIG_CACHE`; monorepo `shared/config/ci.rb` is current — redeploy after pull |

**sass-embedded on copy-tree deploys:** `bundle34 install` needs `node` (`doas pkg_add node`) and `NPM_CONFIG_CACHE=/home/<app>/.npm` when running via `doas su -m <app>` — otherwise npm writes to `/root/.npm` and native extension build fails.

## Open proof items

- [ ] All six Rails apps: `bundle34 exec bin/ci` green on vm23 (as app user; one app at a time on 1 GiB VM)
- [ ] Browser smoke on `https://ai.brgen.no/` (WebGL, palette, tap-to-start, history sidebar)

### 2026-06-25 (multi-city wiring)

| Check | Result |
|-------|--------|
| `CityTenantable` on posts, communities, marketplace, dating, TV, playlist, takeaway | landed |
| `city_id` migration + per-city community slug scope | landed |
| `LocaleBridge` + nl/de/fr locale files | landed |
| `CityContent` subreddit map + `PerCitySeeder` + city-aware `reddit_seed` | landed |
| `DomainRegistry` + tenant isolation tests | 7 runs, 0 failures locally |

### 2026-06-25 (land-all backlog)

| Check | Result |
|-------|--------|
| Shared auth: `require_authentication` → `require_real_user`; session-only `authenticated?` | landed |
| Amber mutating controllers → `require_real_user` | landed (6 controllers) |
| Amber `User`/`Session` validations + inverse associations | landed |
| MASTER `web/test/` (health, chat, canvas) | 6 runs, 0 failures locally |
| Amber auth + user tests | 4 runs, 0 failures locally |
| VPS six-app redeploy (`vps_retry_failed.sh`) | green (prior session) |
| Tap-to-start web fix (`31cef8e67`) | deployed to vm23 |

### 2026-06-25 (commit `defrag-final`)

| Check | Result |
|-------|--------|
| `voice.yml` split from `rules.yml` | done — prune/personality load via `Ground::Rules` |
| Shared `Master.prepare_runtime!` | `bin/cli`, web initializer, `bootstrap_container` |
| `Observation`/`Result` bridge | `ok?`/`err?`/`value!` on Observation; `Result.from_observation` |
| Guard + governor | shell-hint tier check on dangerous patterns |
| Root shrink | `index.html` → `web/radio_bergen.html`, `.mp3/` → `audio/` |
| `ci.rb` defaults | `BUNDLER_AUDIT_UPDATE=0`, `NPM_CONFIG_CACHE=~/.npm` |

### 2026-06-25 (commit `ef45e45c5`)

| Check | Result |
|-------|--------|
| Local `bundle exec rake test` (MASTER) | 479 runs, 0 failures |
| VPS `git pull` + `health_check.rb` | pass (after `f7b04ee0b` pull) |
| Data defrag | `workflow→limits`, `standing_orders→state`, `ruby_style→style`; `patterns.yml` absorbs injection + sweep techniques; 20 duplicate `data/claude/feedback_*.md` removed; `MEMORY.md` consolidated |

Update this section when VPS proof completes; do not recreate section-checkbox sprawl.