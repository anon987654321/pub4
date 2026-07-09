# VPS Safety

vm23 is a small OpenBSD VPS. Treat live operations as scarce, serial, and recoverable.

## Forbidden for AI agents (unless the human explicitly requests recovery)

These actions have caused production downtime when run autonomously:

- `vmctl console`, `vmctl stop`, `vmctl start`, or `vmctl reboot` on server4
- `pkill` / `kill` of `cu`, `vmctl`, or other VMM console sessions on server4
- Any `DEPLOY/openbsd/sh/vps_console*.exp` or `vps_drop_install.exp` without human approval
- Running `DEPLOY.sh`, full app installs, or `pkill` deploy workers **from the serial console**
- Touching **vm27** or any VM other than **vm23** (owner `dev`)
- Parallel SSH deploys, parallel `bin/ci`, or broad `rcctl restart` without a named target

Agents may SSH to vm23 for routine work only when the task requires it. Prefer local gates first.

## Console automation gate

Recovery-only expect scripts refuse to run unless a human operator exports:

```zsh
export I_UNDERSTAND_CONSOLE_RISK=1
```

Same pattern as `I_UNDERSTAND_DNS_WIPE=1` for `DEPLOY.sh --stage-1`.

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
- Routine deploy on vm23: `cd ~/pub4/DEPLOY/openbsd && doas zsh DEPLOY.sh` (SSH, not console).

## doas.conf

OpenBSD rejects `/etc/doas.conf` without a trailing newline — `doas` breaks for everyone.
`DEPLOY.sh` fixes the repo copy before install, validates `su dev -c 'doas id'`, and rolls back on failure.
Cron heal paths use `DEPLOY/openbsd/sh/validate_doas.ksh` with the same validation.

## Recovery (human operator)

- Load shedding: `doas ksh DEPLOY/openbsd/resource_guard.sh`.
- Core health: `doas rcctl check master brgen relayd pf`.
- SSH lockout only: `ssh server4`, then `vmctl console vm23` (manual — not agent-automated).
- pf lockout from console: `doas pfctl -t bruteforce -T flush`.

## Backups (Litestream)

`etc/litestream.yml` replicates each app's SQLite to `file:///var/backups/litestream/` on the
same VPS disk. That protects against app-level corruption, not disk loss or provider failure.
Accepted RPO for full-disk loss: last manual off-host backup or git pull + redeploy. Add an
off-host Litestream replica (sftp/s3) before treating backups as disaster-recovery grade.

## Post-Change

- Run `ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps`.
- Copy any live `/etc` changes back into `DEPLOY/openbsd/etc/`.
- Record persistent lessons in `BACKLOG.yml`, `DEPLOY/DEBT.md`, or `DEPLOY/DECISIONS.md`.