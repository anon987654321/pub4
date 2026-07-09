# Start Here

MASTER is a constitutional AI runtime in Ruby. Models propose; the runtime validates against `data/soul.yml`, `data/rules.yml`, and scanner shards before durable writes. The Rails face in `web/` mirrors runtime state at `https://ai.brgen.no`.

**Orientation:** one file. Law and config live in YAML under `data/`. Prose stubs: `data/SOUL.md`, `data/IDENTITY.md`, generated `data/CANON.md`. Everything else defers to `/orient` or this section.

## Safe First Commands

- `bin/check` — normal contributor gate.
- `bin/check --profile=agent` — law, scanners, loop, routing (may fail on known debt).
- `bin/check --profile=web` — face/assets; set `MASTER_WEB_LIVE=1` for live web checks.
- `bin/check --profile=full` — operator-grade probe path.
- Runtime dumps: `/orient bootstrap`, `/orient soul`, `/orient rules`, `/orient conventions`.

## Runtime Map

```text
bin/cli → Master.bootstrap_container
       → lib/now (pipeline, commands, web adapters)
       → lib/judge (scanners, council, routing, review)
       → lib/loop (fix/watch/self-check)
       → lib/reach (tools, external actions)
       → lib/trace (evidence, session, telemetry)
       → lib/ground (constitution, memory, policy)
       → lib/voice (persona, TTS, SOUL evolution)
       → web/ (Rails chat face)
kernel/ — isolated constitutional fold spine (separate load path; do not merge with lib/ casually)
```

High-risk boundaries: `data/soul.yml`, `data/rules.yml`, `data/rules/*.yml`, `lib/master.rb`, `web/app/views/chat/index.html.erb`, `web/public/face*`, `lib/reach/`, `.master/`.

## Agent Contract

**Modes:** contributor (narrow patches + `bin/check`), operator (full gates + deliberate policy edits), agent (this contract + `bin/check --profile=agent` when touching law).

**Work rules:** preserve behavior first; read before writing; keep generated/local artifacts out of commits; report blocked checks with exact command and first failure class; document intentional exceptions.

**Checks by change type:**

| Change | Command |
|--------|---------|
| Ordinary code | `bin/check` |
| Law / scanners / loop | `bin/check --profile=agent` |
| Web face | `bin/check --profile=web` |
| Deploy / Rails | `DEPLOY/bin/check-rails --profile=contributor` |
| Operator / release | `bin/pub4 status` then `DEPLOY/bin/check-full` |

**Do not optimize away:** dual `lib/` + `core/` spines until absorption cutover; `data/rules/` shards (one consumer each); deferred WebGL until primer tap; constitution self-scan debt during unrelated UI work.

## Do Not Touch (unless the task requires it)

1. `lib/` and `core/` are two spines — do not merge before absorption completes.
2. `data/rules/*.yml` shards stay split — do not fold into `rules.yml` without retuning scanners.
3. `knowledge/` is local-only — do not commit without updating `SearchKnowledge`.
4. WebGL / face boot stays deferred until primer tap.
5. `DEPLOY/rails/apps.horizon.yml` is agent-ignore horizon — do not implement unprompted.
6. VPS: one app CI/deploy at a time on vm23.
7. Secrets in `/etc/*.env` on VPS — never commit keys or generated assets.
8. After `git pull` on vm23, run `vps-deploy` before expecting live health.
9. Feature truth: `DEPLOY/rails/apps.yml`; debt: `DEPLOY/data/debt.yml`.
10. Never autonomously run `vmctl console/stop/start` or kill `cu` on server4 — see `DEPLOY/VPS_SAFETY.md`.
11. Production VM is vm23 only (`dev@brgen.no`).
12. `I_UNDERSTAND_CONSOLE_RISK=1` and `I_UNDERSTAND_DNS_WIPE=1` are human-only gates.
13. Dmesg every file op — see `DEPLOY/OPERATOR_CONTRACT.md`.

## Data File Budget (why so many YAML files)

There are ~80 files under `data/`. That is too many. They exist because the runtime grew file-per-consumer before the 2026-05 defrag plan finished. **Do not merge blindly** — each path has Ruby loaders and tests.

**Tier 1 — Law (5 files, do not collapse without a migration):**

- `soul.yml` — constitutional schema, sacred paths, anti-simulation
- `rules.yml` + `rules/{codebase,file,line,unit}.yml` — scanner law (sharded on purpose)
- `limits.yml` — budgets, scan profiles, standing orders
- `voice.yml` — persona, TTS, speech
- `style.yml` — output shape, line order

**Tier 2 — Registries (edit when adding providers, models, tools):**

- `models.yml`, `providers.yml`, `agents/*.yml`, `personas.yml`, `tools.yml`, `mcp_servers.yml`

**Tier 3 — Runtime catalog (`data/runtime/*.yml`):**

- UI/face topology, event registry, routing notes — mostly reference material loaded by catalog helpers. **Merge candidate** for a single `data/runtime.yml` in a future pass.

**Tier 4 — Prose (3 allowed markdown files in `data/`):**

- `SOUL.md` — human mirror of absolute tier (pairs with `soul.yml`)
- `IDENTITY.md` — negotiable operator tone (not law)
- `CANON.md` — generated rule index

**Tier 5 — Everything else:**

- `bootstrap.yml`, `operator_principles.yml`, `project_context.yml`, `patterns.yml`, etc. — operational memory. Consolidation target: fold into `patterns.yml` + `operator_principles.yml` per the 2026-05 defrag plan in `project_context.yml`.

**Target end state:** 5 law YAMLs + 1 patterns + registries + 1 runtime catalog + 3 data markdown stubs. Top-level MASTER markdown: this file + `README.md` stub + `DEBT.md` / `DECISIONS.md` / `EXAMPLES.md` / `REPAIR_PLAYBOOKS.md` only when they hold living entries.

DEPLOY mirror: `DEPLOY/START_HERE.md` + `DEPLOY/OPERATOR.md` — not duplicate MASTER law.

## Source And Local State

- Source: `lib/`, `kernel/`, `data/`, `bin/`, `test/`, `spec/`, `web/app/`, `web/public/`.
- Local/generated: `.master/`, `knowledge/`, `output/`, `web/public/assets/`, `web/storage/`, `web/log/`.

## Law Ladder

1. Fatal invariant — behavior, intent, secrets.
2. CI gate — tests, syntax, YAML schema.
3. Scanner finding — triage violation vs false positive.
4. Design preference — when local code supports it.
5. Philosophy — context only.

## Before Editing

- Read the target file and nearby tests.
- Check `PATH_OWNERSHIP.yml` for risk.
- Prefer small patches; run the smallest check that proves the work.
- Update `DECISIONS.md` or `DEBT.md` when settling ambiguity.
- Face boot: read `web/BOOT_CONTRACT.md` first.