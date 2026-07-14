# OPENBSD

OpenBSD production stack for pub4: VPS config backup (`etc/`, `usr/`, `var/`) plus deploy
tooling (`bin/`, `lib/`, `sh/`, gates). Start with `START_HERE.md`; the full runbook is
`RUNBOOK.md`. Per-app deploy scripts: `RAILS/<app>/<app>.sh` (inventory: `RAILS/apps.yml`).

Quick checks: `bin/pub4 status`, `OPENBSD/bin/check` (local), `OPENBSD/bin/check-vps` (live
vm23). Copy-paste paths: `RECIPES.md`.
