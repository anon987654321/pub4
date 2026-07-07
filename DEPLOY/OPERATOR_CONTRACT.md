# Operator Contract

This contract is for humans and AI agents working on DEPLOY.

## Modes

- Local contributor mode: edit repo files, run local gates, do not SSH.
- VPS operator mode: one SSH session, one CI/deploy operation at a time, tmux for long work.
- Recovery mode: use console/resource guard only to restore access or health, then document the fix.

## Rules

- Run `bin/pub4 status` before starting work; use `RECIPES.md` for copy-paste paths.
- Read `VPS_SAFETY.md` before live operations.
- Treat `rails/apps.yml` and `master.json` as inventories, not suggestions.
- Any `/etc` change made on vm23 must be copied back to `DEPLOY/openbsd/etc/`.
- Use `ruby34` and `bundle34` on OpenBSD.
- Use `zsh DEPLOY/openbsd/sh/vps_ci.sh <app>` for per-app CI on vm23.
- Never run parallel SSH deploys, parallel `bin/ci`, or broad app restarts casually on the 1 GiB VPS.
- Keep secrets in `/etc/*.env`; never commit them.
- Keep Rails `config.assume_ssl = true`; do not enable `force_ssl` behind relayd.

## Reporting

Good deploy closeout:

- exact host or local environment
- commands run
- gates passed, skipped, or failed
- services restarted
- remaining manual verification

Bad deploy closeout:

- "deployed" without host and command
- public health not checked
- asset precompile skipped after web changes
- route/cert changes without relayd/acme/NSD context
