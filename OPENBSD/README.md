# OPERATOR

OpenBSD production stack for pub4. Start with `START_HERE.md`; the full runbook — repo layout,
deployment map, agent contract, live-operation safety, deploy commands, and gates — is
`OPERATOR.md`. Per-app deploy scripts: `RAILS/<app>/<app>.sh` (inventory: `RAILS/apps.yml`).

Quick checks: `bin/pub4 status`, `OPERATOR/bin/check` (local), `OPERATOR/bin/check-vps` (live
vm23). Copy-paste paths: `RECIPES.md`. Seeds: Faker base in each `db/seeds.rb`; optional web
augmentation via `SEED_FROM_WEB=1` with `OPENROUTER_API_KEY`.
