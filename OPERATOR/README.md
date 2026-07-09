# OPERATOR

OpenBSD production stack for pub4. Start with `START_HERE.md`; operator runbook: `OPERATOR.md`.

Use `OPERATOR/bin/check` for local deploy validation, `OPERATOR/bin/check-rails` for Rails deploy gates,
`OPERATOR/bin/check-openbsd` for OpenBSD config/deploy identity, and `OPERATOR/bin/check-vps` only for
live vm23 checks. Start with `bin/pub4 status` and `RECIPES.md`.

## Layout

```
openbsd/   pf, relayd, nsd, acme, OPERATOR.sh; sh/ VPS helpers (vps_ci.sh, install scripts)
rails/     four active Rails 8 apps + shared engine (apps.yml)
tools/     creative + utility scripts: postpro (libvips film), repligen (Replicate CLI),
           dilla, audio, burst, stipple, nmap, security_sweep, bp, bin, public
```

Top level also holds the deploy gates (`integrity_gate.rb`, `verify_deploy_identity.rb`,
`master.json`) and recovery pens (`archive/`, `quarantine/`).

## OpenBSD

```zsh
cd ~/pub4/OPENBSD
tmux new-session -d -s deploy "doas zsh OPERATOR.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

Config sync: `doas zsh OPERATOR.sh --sync-configs`. Details: `openbsd/README.md`.

## Rails

| App | Script | Domain |
|-----|--------|--------|
| brgen | `rails/brgen/brgen.sh` | brgen.no |
| amber | `rails/amber/amber.sh` | amber.brgen.no |
| bsdports | `rails/bsdports/bsdports.sh` | bsdports.org |
| hjerterom | `rails/hjerterom/hjerterom.sh` | hjerterom.brgen.no |

Inventory and feature matrix: `rails/apps.yml`. Shared engine: `rails/shared`.

Seeds: Faker base in each `db/seeds.rb`. Optional web augmentation: `SEED_FROM_WEB=1` with `OPENROUTER_API_KEY` and rakes under `lib/tasks/`.

## Checks

```zsh
OPERATOR/bin/check
ruby OPERATOR/integrity_gate.rb
ruby RAILS/crawl_probe.rb
MASTER_CRAWL_BROWSER=1 ruby RAILS/crawl_browser.rb   # VPS Ferrum crawl
cd MASTER && bundle exec ruby bin/probe integrity
```

The integrity gate chains production, phantom foreign keys, frontend, relayd smoke, domain alignment, and HTTP crawl inventory sync. `check_production_gate.rb` already includes `master_web_assets_gate` and `archive_restore_gate`.
