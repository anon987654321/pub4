# Start Here

OPERATOR is the production surface for pub4: OpenBSD vm23, relayd, NSD/acme, Rails 8 apps, MASTER web, and operator recovery tools.

## Read First

1. `README.md` for the short layout.
2. `OPERATOR.md` for everything else: deployment map, agent contract, live-operation safety
   (read before any SSH, `doas`, rc.d, pf, relayd, or full-stack deploy), deploy commands, gates.
3. `MASTER/START_HERE.md` for MASTER agent rules and the **data file budget** (why ~80 YAML files exist and what merges next).
4. `REPAIR_PLAYBOOKS.md` when a gate fails.
5. `EXAMPLES.md` for good/bad deploy patch shapes.

## Golden Commands

- `bin/pub4 status` — one-screen repo/VPS posture and next command.
- `RECIPES.md` — copy-paste operator recipes.
- `OPERATOR/bin/check --profile=contributor` — fast static deploy gates.
- `OPERATOR/bin/check-rails --profile=contributor` — Rails source gates (skips runtime on Ruby mismatch).
- `OPERATOR/bin/check-openbsd` checks OpenBSD config/deploy identity locally.
- `OPERATOR/bin/check-vps` is the explicit VPS/live gate wrapper; run it only on vm23 or with SSH/operator intent.
- `OPERATOR/bin/check-full` chains the local checks and the integrity gate.
- `OPERATOR/bin/vps-state` / `bin/pub4 vps deploy <app>` — deployed vs dev tree on vm23.

## Source Of Truth

- App inventory: `RAILS/apps.yml`.
- Public/deploy identity: `OPERATOR/master.json`.
- OpenBSD configs: `OPENBSD/etc/`.
- Operator runbook: `OPERATOR/OPERATOR.md`.
- Feature inventory: `RAILS/apps.yml`. Open debt: `OPERATOR/data/debt.yml`. Horizon: `apps.horizon.yml` (agent: ignore). Runtime: `/orient deploy`.

## Safety Defaults

- Do not run parallel SSH or parallel app CI on vm23.
- Do not expose app ports publicly; relayd terminates TLS and forwards to loopback.
- Do not commit `/etc/*.env`, Rails master keys, generated assets, or local VPS state.
- After `MASTER/web/` changes, precompile assets and restart Falcon; no hot reload exists in production.
- Prefer local static gates before touching the VPS.
