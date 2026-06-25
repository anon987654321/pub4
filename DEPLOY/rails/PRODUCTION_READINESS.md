# Production readiness — Rails family (pub4)

Last updated: **2026-06-25** (waves 1–7 closed locally; frontend gates green; vm23 operator proof green)

## Gate commands

```sh
# Local (Mac or dev checkout) — all waves
ruby bin/probe repo
ruby DEPLOY/rails/check_production_gate.rb
ruby DEPLOY/rails/rails_runtime_gate.rb          # static
ruby DEPLOY/rails/rails_runtime_gate.rb --runtime # VPS only (bundle34 + db:prepare + bin/ci)
ruby DEPLOY/security_sweep.rb
ruby DEPLOY/rails/frontend_production_gate.rb
ruby DEPLOY/rails/frontend_auditor_gate.rb
ruby DEPLOY/openbsd/deploy_smoke_gate.rb         # repo relayd template + production configs
cd MASTER && bin/smoke                            # Ruby 3.4+ required

# VPS (ruby34 / bundle34) — per app after git pull
cd /home/dev/pub4/DEPLOY/rails/<app>
bundle34 check
RAILS_ENV=production bundle34 exec rails db:prepare
bundle34 exec bin/ci
curl -fsS http://127.0.0.1:<port>/up

# VPS health sweep
ruby34 /home/dev/pub4/DEPLOY/openbsd/health_check.rb
```

Ports: see `DEPLOY/rails/apps.yml`.

## Wave completion (2026-06-24)

| Wave | Scope | Local | VPS |
|------|-------|-------|-----|
| 1 Rails runtime gate | `rails_runtime_gate.rb` + deploy `.sh` `rails_runtime_gate` hook | pass | pass |
| 2 DEPLOY de-duplication | `production_baseline`, `ApplicationSetup`, shared env/ci | pass | pass |
| 3 MASTER scanner accuracy | `test_web_scan_fixtures.rb` for HTML/CSS/JS rules | pass | n/a |
| 4 Frontend production pass | `frontend_production_gate.rb` + `frontend_auditor_gate.rb` (0 warnings) | pass | n/a |
| 5 Security sweep | `security_sweep.rb` + `bin/probe` quarantine checks | pass | n/a |
| 6 OpenBSD deploy smoke | `deploy_smoke_gate.rb` (repo) + `health_check.rb` (VPS) | pass | pass |
| 7 Production readiness | this document + dated pass/fail matrix | pass | pass |

## Summary

| App | Local gate | Repo smoke | VPS bin/ci | HTTPS /up | Ready? |
|-----|------------|------------|------------|-----------|--------|
| brgen | pass | pass | pass | 200 | **yes** |
| amber | pass | pass | pass | 200 | **yes** |
| baibl | pass | pass | pass | 200 | **yes** |
| blognet | pass | pass | pass | 200 | **yes** |
| bsdports | pass | pass | pass | 200 | **yes** |
| hjerterom | pass | pass | pass | 200 | **yes** |
| master (AI face) | n/a | pass | smoke | 200 | **yes** |

**Operator proof** = `bundle34 exec bin/ci` per app on vm23 + `ruby34 DEPLOY/openbsd/health_check.rb` + `doas rcctl check` on canonical service names (`brgen`, `amber`, …).

Ship readiness is defined in `MASTER/data/operator_playbook.yml` — not checkbox backlogs (retired 2026-06-24).

## Open blockers (operator)

1. **Apex DNS**: `baibl.no`, `blognet.no`, `hjerterom.no` may return NXDOMAIN off-VM — `*.brgen.no` subdomains are the live routes.
2. **relayd stale tables**: after mass `rcctl restart`, run `doas rcctl restart relayd` or wait for cron `relayd-watchdog` (every 5 min).
3. **db:seed**: brgen/amber seeds use fictive `password123` users — not production data.
4. **openrsync**: broken on vm23 — deploy uses tar sync (set `SYNC_USE_OPENRSYNC=1` only when openrsync works).

## Deploy path

```sh
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
cd /home/dev/pub4 && git pull origin main
chmod o+x /home/dev && chmod -R a+rX DEPLOY/rails
SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_on_vm_install.sh
doas rcctl restart relayd
ruby34 DEPLOY/openbsd/health_check.rb
```