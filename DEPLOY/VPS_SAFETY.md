# VPS Safety

vm23 is a small OpenBSD VPS. Treat live operations as scarce, serial, and recoverable.

## Before SSH

- Know whether you need VM (`ssh brgen`) or VMM host (`ssh server4`).
- Use one SSH session for CI/deploy work.
- Avoid rapid reconnect loops; pf bruteforce can block you.
- Prefer local gates first: `DEPLOY/bin/check`.

## During Live Work

- Use tmux for long deploys.
- Use `ruby34` and `bundle34`.
- Use `zsh DEPLOY/openbsd/sh/vps_ci.sh <app>` for app CI; it has mutex/load gates.
- Do not run full stack deploy and app CI in parallel.
- Do not restart relayd, pf, nsd, or app services without knowing the affected domains.

## Recovery

- Load shedding: `doas ksh DEPLOY/openbsd/resource_guard.sh`.
- Core health: `doas rcctl check master brgen relayd pf`.
- Console recovery: `ssh server4`, `vmctl console vm23`.
- pf lockout recovery from console: `doas pfctl -t bruteforce -T flush`.

## Backups (Litestream)

`etc/litestream.yml` replicates each app's SQLite to `file:///var/backups/litestream/` on the
same VPS disk. That protects against app-level corruption, not disk loss or provider failure.
Accepted RPO for full-disk loss: last manual off-host backup or git pull + redeploy. Add an
off-host Litestream replica (sftp/s3) before treating backups as disaster-recovery grade.

## Post-Change

- Run `ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps`.
- Copy any live `/etc` changes back into `DEPLOY/openbsd/etc/`.
- Record persistent lessons in `BACKLOG.yml`, `DEPLOY/DEBT.md`, or `DEPLOY/DECISIONS.md`.
