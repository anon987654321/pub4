# Production readiness

Last updated: 2026-06-28. Repo gates pass locally; public readiness needs VPS proof and city vanity TLS.

## Gates

```sh
ruby DEPLOY/rails/check_production_gate.rb
ruby DEPLOY/rails/rails_runtime_gate.rb
ruby DEPLOY/openbsd/deploy_smoke_gate.rb
cd MASTER && bin/probe all
```

VPS per app:

```sh
cd /home/dev/pub4/DEPLOY/rails/<app>
bundle34 check
RAILS_ENV=production bundle34 exec rails db:prepare
bundle34 exec bin/ci
curl -fsS http://127.0.0.1:<port>/up
ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps
```

Ports: `apps.yml`.

## Status

| App | Domain | Ready when |
|-----|--------|------------|
| brgen | brgen.no | VPS `bin/ci` + public `/up` |
| amber | amber.brgen.no | same |
| hjerterom | hjerterom.brgen.no | same |
| bsdports | bsdports.org | same |
| master | ai.brgen.no | auth smoke + `/up` |

Ship criteria: `MASTER/data/operator_playbook.yml`.

## Blockers

1. City vanity TLS — `openbsd.sh` stage 1 must issue certs for every apex in `ALL_DOMAINS`; relayd keypairs only exist for certs on disk.
2. Domain drift — `master.json`, `apps.yml`, `openbsd.sh`, and `relayd.conf` must agree.
3. relayd restart after route changes.
4. Seeds skipped in production unless `RUN_PRODUCTION_SEEDS=1`.
5. openrsync broken on vm23 — deploy uses git pull.

## Deploy

```sh
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
cd /home/dev/pub4 && git pull origin main
SKIP_MASTER_SCAN=1 zsh DEPLOY/openbsd/sh/vps_on_vm_install.sh
doas rcctl restart relayd
ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps
```
