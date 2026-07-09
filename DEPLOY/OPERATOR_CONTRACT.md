# Operator Contract

This contract is for humans and AI agents working on DEPLOY.

## Modes

- Local contributor mode: edit repo files, run local gates, do not SSH.
- VPS operator mode: one SSH session, one CI/deploy operation at a time, tmux for long work.
- Recovery mode: human-directed console or resource guard only to restore access or health, then document the fix.

## Agent hard stops

AI agents must **not** autonomously:

| Action | Why |
|--------|-----|
| `vmctl console/stop/start` on server4 | Serial console sessions have caused VM reboots and site outages |
| `pkill cu` or killing VMM console processes on server4 | Disrupts other operators and can wedge vm23 |
| `vps_console*.exp` / `vps_drop_install.exp` | Gated by `I_UNDERSTAND_CONSOLE_RISK=1`; recovery-only |
| Deploy or install from serial console | Bypasses SSH safety, tmux, and load gates |
| Target vm27 or any non-vm23 VM | Wrong tenant; production is vm23 (`dev`) |
| `DEPLOY.sh --stage-1` without `I_UNDERSTAND_DNS_WIPE=1` | Destructive DNS wipe |

When SSH to vm23 is required, use normal paths: `doas zsh DEPLOY.sh`, `vps-deploy`, `vps_ci.sh`.

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

## Agent dmesg (verbose file operations)

External agents (Grok CLI, Claude Code, Cursor) and MASTER should log mutations in
OpenBSD dmesg style: terse, lowercase, one fact per line, path-first.

Format for each file touch:

```
write DEPLOY/openbsd/etc/rc.d/brgen 412B +12/-3
read MASTER/lib/reach/base.rb sha256=a1b2c3… 2048B
run zsh DEPLOY/bin/check-openbsd exit=0
```

Rules:

- Name the **path** (repo-relative) on every read, write, or delete.
- Show **evidence** on writes: unified diff stat (`+N/-M`) or byte size.
- Show **command + exit code** for shell, not "deployed successfully".
- Silence on success is fine for bulk gates; speak up for each mutated file.
- MASTER: `/dmesg` or `toggle dmesg` streams bus events; CLI thinking spinner prints
  `write path` / `touch path` lines during tool calls.

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