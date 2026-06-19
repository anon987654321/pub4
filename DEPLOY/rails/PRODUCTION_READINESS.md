# Production readiness — Rails family (pub4)

Last updated: **2026-06-19** (waves 1–7 complete — local repo gates pass; VPS runtime/bin/ci pending CPU headroom)

## Gate commands

```sh
# Local (Mac or dev checkout) — all waves
ruby bin/probe repo
ruby DEPLOY/rails/check_production_gate.rb
ruby DEPLOY/rails/rails_runtime_gate.rb          # static
ruby DEPLOY/rails/rails_runtime_gate.rb --runtime # VPS only (bundle34 + db:prepare + bin/ci)
ruby DEPLOY/security_sweep.rb
ruby DEPLOY/rails/frontend_production_gate.rb
ruby DEPLOY/openbsd/deploy_smoke_gate.rb         # repo relayd template + production configs
cd MASTER && bin/smoke                            # Ruby 3.4+ required

# VPS (ruby34 / bundle34) — per app after git pull
cd /home/dev/pub4/DEPLOY/rails/<app>
bundle34 check
RAILS_ENV=production bundle34 exec rails db:prepare
bundle34 exec bin/ci
curl -fsS http://127.0.0.1:<port>/up

# VPS health sweep (wave 6 live smoke)
ruby34 /home/dev/pub4/DEPLOY/openbsd/health_check.rb
```

Ports: see `DEPLOY/rails/apps.yml`.

## Wave completion (2026-06-19)

| Wave | Scope | Local | VPS |
|------|-------|-------|-----|
| 1 Rails runtime gate | `rails_runtime_gate.rb` + deploy `.sh` `rails_runtime_gate` hook | pass (static) | pending `bin/ci` per app |
| 2 DEPLOY de-duplication | `production_baseline`, `ApplicationSetup`, `SessionsActions`, `PasswordsActions`, shared env/ci | pass | n/a |
| 3 MASTER scanner accuracy | `test_web_scan_fixtures.rb` for HTML/CSS/JS rules | pass (Ruby 3.4) | n/a |
| 4 Frontend production pass | `frontend_production_gate.rb` layouts + MASTER/web | pass | n/a |
| 5 Security sweep | `security_sweep.rb` + `bin/probe` quarantine checks | pass | n/a |
| 6 OpenBSD deploy smoke | `deploy_smoke_gate.rb` (repo) + `health_check.rb` (VPS) | pass (repo) | pass (2026-06-16) |
| 7 Production readiness | this document + dated pass/fail matrix | pass | partial |

## Summary

| App | Local gate | Repo smoke | VPS /up (2026-06-16) | HTTPS route | Ready? |
|-----|------------|------------|----------------------|-------------|--------|
| brgen | pass | pass | 200 | `https://brgen.no` | **no** — VPS `bin/ci` not run |
| amber | pass | pass | 200 | `https://amber.brgen.no` | **no** |
| baibl | pass | pass | 200 | `https://baibl.brgen.no` | **no** |
| blognet | pass | pass | 200 | `https://blognet.brgen.no` | **no** |
| bsdports | pass | pass | 200 | `https://bsdports.org` | **no** |
| hjerterom | pass | pass | 200 | `https://hjerterom.brgen.no` | **no** |
| master (AI face) | n/a | pass | 200 | `https://ai.brgen.no` | **no** — needs VPS `bin/smoke` on pull |

**Local gate** = `check_production_gate.rb` + wave scripts via `bin/probe repo`.

**No app marked production-ready** until target-host `bundle34 exec bin/ci` passes on vm23.

## Open blockers (operator)

1. **Apex DNS**: `baibl.no`, `blognet.no`, `hjerterom.no` return NXDOMAIN — use `*.brgen.no` subdomains until NS/A records point at `46.23.89.226`.
2. **VPS bin/ci**: not run this pass (1GB VM, long runtime). Run when CPU headroom allows.
3. **db:seed**: brgen/amber seeds use `password123` fictive users — guarded, not production data.
4. **MASTER bundle on VPS**: `bundle install` in `MASTER/` before strict scan without `SKIP_MASTER_SCAN=1`.

## Deploy path

```sh
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
cd /home/dev/pub4 && git pull origin main
SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_on_vm_install.sh
ruby34 DEPLOY/openbsd/health_check.rb
```