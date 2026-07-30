# Start Here

MASTER is a constitutional AI runtime in Ruby. Models propose; the runtime validates against `data/soul.yml`, `data/rules.yml`, and scanner shards before durable writes. The Rails face in `web/` mirrors runtime state at `https://ai.brgen.no`.

**Orientation:** `AGENTS.md` for task-scoped agent entry; this file for the full contract. Law and config live in YAML under `data/`. Prose stubs: `data/SOUL.md`, `data/IDENTITY.md`, generated `data/CANON.md`. Everything else defers to `/orient` or this section.

## Safe First Commands

- `bin/check` — default gate. Runs the **operator** profile (`test`, `spec`, `security_sweep`, `test:core`, `lint:data_singularity`), not the contributor one; `--profile=contributor` is the same list minus `test:core`.
- `bin/check --profile=agent` — `selftest` + `lint:data_singularity` only (may fail on known debt).
- `bin/check --profile=web` — face/assets; set `MASTER_WEB_LIVE=1` for live web checks.
- `bin/check --profile=full` — operator-grade probe path.
- `bin/check --format=brief` — structured pass/fail with debt hints (pair with any profile).
- Runtime dumps: `/orient bootstrap`, `/orient soul`, `/orient rules`, `/orient conventions`.

## Runtime Map

```text
bin/cli → Master.bootstrap_container
       → lib/cli (pipeline, commands, web adapters)
       → lib/review (scanners, council, routing, review)
       → lib/fix (fix/watch/self-check)
       → lib/io (tools, external actions)
       → lib/trace (evidence, session, telemetry)
       → lib/ground (constitution, memory, policy)
       → lib/voice (persona, TTS, SOUL evolution)
       → web/ (Rails chat face)
core/ — isolated constitutional fold spine (separate load path; do not merge with lib/ casually)
```

High-risk boundaries: `data/soul.yml`, `data/rules.yml`, `data/rules/*.yml`, `lib/master.rb`, `web/app/views/chat/index.html.erb`, `web/public/face*`, `lib/io/`, `.master/`.

## Agent Contract

**Modes:** contributor (narrow patches + `bin/check`), operator (full gates + deliberate policy edits), agent (this contract + `bin/check --profile=agent` when touching law).

**Work rules:** preserve behavior first; read before writing; keep generated/local artifacts out of commits; report blocked checks with exact command and first failure class; document intentional exceptions.

**Checks by change type:**

| Change | Command |
|--------|---------|
| Ordinary code | `bin/check` |
| Law / scanners / loop | `bin/check --profile=agent` |
| Web face | `bin/check --profile=web` |
| Deploy / Rails | `OPENBSD/bin/check-rails --profile=contributor` |
| Operator / release | `bin/pub4 status` then `OPENBSD/bin/check-full` |

**Do not optimize away:** dual `lib/` + `core/` spines until absorption cutover; `data/rules/` shards (one consumer each); deferred WebGL until primer tap; constitution self-scan debt during unrelated UI work.

## Do Not Touch (unless the task requires it)

1. `lib/` and `core/` are two spines — do not merge before absorption completes.
2. `data/rules/*.yml` shards stay split — do not fold into `rules.yml` without retuning scanners.
3. `knowledge/` is local-only — do not commit without updating `SearchKnowledge`.
4. WebGL / face boot stays deferred until primer tap.
5. `RAILS/apps.horizon.yml` is agent-ignore horizon — do not implement unprompted.
6. VPS: one app CI/deploy at a time on vm23.
7. Secrets in `/etc/*.env` on VPS — never commit keys or generated assets.
8. After `git pull` on vm23, run `vps-deploy` before expecting live health.
9. Feature truth: `RAILS/apps.yml`; debt: `OPENBSD/data/debt.yml`.
10. Never autonomously run `vmctl console/stop/start` or kill `cu` on server4 — see `OPENBSD/RUNBOOK.md`.
11. Production VM is vm23 only (`dev@brgen.no`).
12. `I_UNDERSTAND_CONSOLE_RISK=1` and `I_UNDERSTAND_DNS_WIPE=1` are human-only gates.
13. Dmesg every file op — see `OPENBSD/RUNBOOK.md`.

## Data File Budget (why so many YAML files)

`data/` is down to 54 files (was ~80) after the 2026-05 defrag plan's Tier-5 pass (2026-07-15): 9 files removed outright (dead — no code path ever loaded their content, despite some claiming otherwise in their own header comments), 13 folded into `patterns.yml` under namespaced keys, 1 folded despite having no enforced consumer (kept as reference documentation). **Do not merge blindly** — each remaining path has Ruby loaders and tests.

A handful of Tier-5-looking files were deliberately left alone rather than folded: `council.yml` (8+ consumers across the whole deliberation subsystem, protected by its own scanner rule), `state.yml` (backs standing-orders/autocommit via `DATA_ALIASES`), `topologies.yml`/`tts.yml` (feed the live web boot payload and TTS), `visual_clusters.yml`/`mobile_web_opportunities.yml` (deliberately parallel sources in `ClusterRegistry`, not fragmentation), `tools.dynamic.yml` (two-tier repo+user-override merge), `exemplars.yml`/`openbsd.yml` (active read-modify-write targets, not static config — folding would make routine runtime events rewrite the shared source-of-truth file). Folding any of these needs a real design decision, not a mechanical move.

**Tier 1 — Law (5 files, do not collapse without a migration):**

- `soul.yml` — constitutional schema, sacred paths, anti-simulation
- `rules.yml` + `rules/{codebase,file,line,unit}.yml` — scanner law (sharded on purpose)
- `limits.yml` — budgets, scan profiles, standing orders
- `voice.yml` — persona, TTS, speech
- `style.yml` — output shape, line order

**Tier 2 — Registries (edit when adding providers, models, tools):**

- `models.yml`, `providers.yml`, `agents/*.yml`, `personas.yml`, `tools.yml`, `mcp_servers.yml`

**Tier 3 — Runtime catalog (`data/runtime.yml`):**

- UI/face topology, event registry, routing notes — consolidated behind `RuntimeCatalog.load(section)`.

**Tier 4 — Prose (3 allowed markdown files in `data/`):**

- `SOUL.md` — human mirror of absolute tier (pairs with `soul.yml`)
- `IDENTITY.md` — negotiable operator tone (not law)
- `CANON.md` — generated rule index

**Tier 5 — Everything else:**

- `bootstrap.yml`, `operator_principles.yml`, `project_context.yml`, `patterns.yml`, etc. — operational memory. Consolidation target: fold into `patterns.yml` + `operator_principles.yml` per the 2026-05 defrag plan in `project_context.yml`.

**Target end state:** 5 law YAMLs + 1 patterns + registries + 1 runtime catalog + 3 data markdown stubs. Top-level MASTER markdown: this file + `README.md` stub + `DEBT.md` / `DECISIONS.md` / `EXAMPLES.md` / `REPAIR_PLAYBOOKS.md` only when they hold living entries.

OPENBSD mirror: `OPENBSD/START_HERE.md` + `OPENBSD/RUNBOOK.md` — not duplicate MASTER law.

## Repo shape (run before big refactors)

```bash
zsh OPENBSD/tree.sh . --pub4-overview
```

Far-away visual tree with noise pruned and alignment notes. Do this before merging YAML/MD or restructuring folders.

## Source And Local State

- Source: `lib/`, `core/`, `data/`, `bin/`, `test/`, `spec/`, `web/app/`, `web/public/`.
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
- Face boot: read `web/CLAUDE.md` first.
- RAILS app CSS/visual work: read `RAILS/shared/WIRING_NOTES.md`'s "Visual design system" section first — x.com is the base reference, tokens live in `RAILS/shared/app/assets/stylesheets/_dialect_tokens.scss`, and the flat-only (no shadow/blur/glow) rule applies repo-wide.
