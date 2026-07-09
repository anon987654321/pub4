# Agents

## Do not touch (unless the task explicitly requires it)

1. `lib/` and `kernel/` are **two spines** — both use `Master::`; do not merge or “fix” namespace collisions.
2. `data/rules/*.yml` shards stay split — each file has one consumer; do not merge into `rules.yml`.
3. `knowledge/` is gitignored and local-only — do not commit or move without updating `SearchKnowledge`.
4. WebGL / face boot stays **deferred until primer tap** — never eager `getContext('webgl*')`.
5. `DEPLOY/rails/apps.horizon.yml` items are **agent: ignore** — do not implement planned/horizon features unprompted.
6. VPS: **one app CI/deploy at a time** — never parallel `bin/ci` or parallel SSH on vm23.
7. Secrets live in `/etc/*.env` on VPS — never commit keys, master keys, or generated assets.
8. After `git pull` on vm23, **deployed trees do not move** — run `vps-deploy` before expecting live health.
9. Constitution self-scan debt is visible by design — do not chase zero during unrelated UI fixes.
10. Feature truth is `apps.yml`; open debt is `DEPLOY/data/debt.yml`; horizon is `apps.horizon.yml` (ignore).
11. **Never** autonomously run `vmctl console/stop/start`, kill `cu` on server4, or `vps_console*.exp` — see `DEPLOY/VPS_SAFETY.md`.
12. Production VM is **vm23** only (`dev@brgen.no`); never touch vm27 or other tenants.
13. VPS deploy is SSH + `doas zsh DEPLOY.sh` / `vps-deploy` — not serial-console automation.
14. `I_UNDERSTAND_CONSOLE_RISK=1` and `I_UNDERSTAND_DNS_WIPE=1` are human-only recovery gates.
15. **Dmesg every file op** — `write path/to/file`, `read path`, `run cmd exit=N`; see `DEPLOY/OPERATOR_CONTRACT.md` Agent dmesg section. MASTER bus emits `tool:before`/`tool:after` with `path`, `op`, `bytes`.

## Boot sequence

Read `START_HERE.md` (DEPLOY) or `QUICKSTART.md` (MASTER) and `AGENT_CONTRACT.md` before editing.

Runtime orientation: `/orient bootstrap`, `/orient agents`, `/orient conventions`.

Law: `data/soul.yml` + `data/rules.yml`. VPS deploy: `DEPLOY/OPERATOR.md`. Recipes: `RECIPES.md`.

## Default checks

| Change type | Command |
|-------------|---------|
| Ordinary code | `cd MASTER && bin/check --profile=contributor` |
| Law / scanner / loop | `bin/check --profile=agent` |
| Web face / assets | `bin/check --profile=web` |
| Deploy / Rails | `DEPLOY/bin/check-rails --profile=contributor` |
| Operator / release | `bin/pub4 status` then `DEPLOY/bin/check-full` |

Per-app notes: `DEPLOY/rails/<app>/AGENTS.md`.