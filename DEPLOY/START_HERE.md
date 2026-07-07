# Start Here

DEPLOY is the production surface for pub4: OpenBSD vm23, relayd, NSD/acme, Rails 8 apps, MASTER web, and operator recovery tools.

## Read First

1. `README.md` for the short layout.
2. `OPERATOR_CONTRACT.md` for safe deployment behavior.
3. `DEPLOYMENT_MAP.md` for how OpenBSD, relayd, Rails, and MASTER fit together.
4. `VPS_SAFETY.md` before any SSH, `doas`, rc.d, pf, relayd, or full-stack deploy.
5. `PATH_OWNERSHIP.yml` before editing deploy scripts or app inventories.
6. `REPAIR_PLAYBOOKS.md` when a gate fails.
7. `EXAMPLES.md` for good/bad deploy patch shapes.

## Golden Commands

- `DEPLOY/bin/check` runs local static deploy gates.
- `DEPLOY/bin/check-rails` runs Rails deploy gates that do not need the VPS.
- `DEPLOY/bin/check-openbsd` checks OpenBSD config/deploy identity locally.
- `DEPLOY/bin/check-vps` is the explicit VPS/live gate wrapper; run it only on vm23 or with SSH/operator intent.
- `DEPLOY/bin/check-full` chains the local checks and the integrity gate.

## Source Of Truth

- App inventory: `DEPLOY/rails/apps.yml`.
- Public/deploy identity: `DEPLOY/master.json`.
- OpenBSD configs: `DEPLOY/openbsd/etc/`.
- Operator runbook: `DEPLOY/OPERATOR.md`.
- Feature backlog: `DEPLOY/TODO.md`.

## Safety Defaults

- Do not run parallel SSH or parallel app CI on vm23.
- Do not expose app ports publicly; relayd terminates TLS and forwards to loopback.
- Do not commit `/etc/*.env`, Rails master keys, generated assets, or local VPS state.
- After `MASTER/web/` changes, precompile assets and restart Falcon; no hot reload exists in production.
- Prefer local static gates before touching the VPS.
