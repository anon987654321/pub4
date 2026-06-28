# DEPLOY

OpenBSD production stack for pub4. Operator runbook: `OPERATOR.md`.

## Layout

```
openbsd/   pf, relayd, nsd, acme, openbsd.sh
rails/     six Rails 8 apps + shared engine (apps.yml)
postpro/   libvips film pipeline
repligen/  Replicate CLI
sh/        VPS helpers (vps_ci.sh, install scripts)
```

## OpenBSD

```zsh
cd ~/pub4/DEPLOY/openbsd
tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

Config sync: `doas zsh openbsd.sh --sync-configs`. Details: `openbsd/README.md`.

## Rails

| App | Script | Domain |
|-----|--------|--------|
| brgen | `rails/brgen/brgen.sh` | brgen.no |
| amber | `rails/amber/amber.sh` | amber.brgen.no |
| bsdports | `rails/bsdports/bsdports.sh` | bsdports.org |
| baibl | `rails/baibl/baibl.sh` | baibl.brgen.no |
| blognet | `rails/blognet/blognet.sh` | blognet.brgen.no |
| hjerterom | `rails/hjerterom/hjerterom.sh` | hjerterom.brgen.no |

Inventory and feature matrix: `rails/apps.yml`. Shared engine: `rails/shared`.

Seeds: Faker base in each `db/seeds.rb`. Optional web augmentation: `SEED_FROM_WEB=1` with `OPENROUTER_API_KEY` and rakes under `lib/tasks/`.

## Checks

```zsh
ruby DEPLOY/rails/check_production_gate.rb
ruby DEPLOY/openbsd/deploy_smoke_gate.rb
```