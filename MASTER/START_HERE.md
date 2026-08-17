# Start Here

MASTER is a constitutional AI runtime in Ruby. Models propose; the runtime validates against `data/soul.yml`, `data/rules.yml`, and its scanner rules before durable writes. The Rails face in `web/` mirrors runtime state at `https://ai.brgen.no`.

**Orientation:** `AGENTS.md` for task-scoped agent entry; this file for the full contract. Law and config live in YAML under `data/`. Prose stubs: `data/SOUL.md`, `data/IDENTITY.md`, generated `data/CANON.md`. Work is a sentence. The slash set is `/through` `/status` `/undo` `/commit` `/model` `/pair` `/doctor` `/help` `/clear`.

## Safe First Commands

- `bin/check` — default gate. Runs the **operator** profile (`test`, `spec`, `security_sweep`, `test:core`, `lint:data_singularity`), not the contributor one; `--profile=contributor` is the same list minus `test:core`.
- `bin/check --profile=agent` — `selftest` + `lint:data_singularity` only (may fail on known debt).
- `bin/check --profile=web` — face/assets; set `MASTER_WEB_LIVE=1` for live web checks.
- `bin/check --profile=full` — operator-grade probe path.
- `bin/check --format=brief` — structured pass/fail with debt hints (pair with any profile).
- Work: say the path. `/through [path]` is the one explicit pass (`--dry-run` previews).

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
lib/core.rb + lib/core/ — the constitutional fold spine (Effect → Constitution → World → Memory)
```

High-risk boundaries: `data/soul.yml`, `data/rules.yml`, `lib/master.rb`, `lib/core.rb`, `web/app/views/chat/index.html.erb`, `web/public/face*`, `lib/io/`, `.master/`.

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

**Do not optimize away:** the fold spine's independence from the rest of `lib/` — `lib/core*` requires nothing outside its own namespace, held by `test/core/test_no_lib_backedges.rb`; deferred WebGL until primer tap; constitution self-scan debt during unrelated UI work.

## Do Not Touch (unless the task requires it)

Every entry names the gate that fails when its claim stops being true, or says
why no gate can hold it. This is not decoration: item 2 of this list used to be
"rule data stays split, because each shard sits near its consumers", and that
reason had been false since the day the shards were created — the four of them
had one consumer between them. A conclusion does not rot loudly. A test does.
`rake lint:do_not_touch` checks that every entry below carries one and that the
gates it names exist.

1. `lib/core.rb` and `lib/core/` are the fold spine, and they must not require the rest of `lib/`. The two-spine *directory* split ended 2026-08-12 (`docs/SEVERANCE.md`); the dependency direction it was protecting did not, and is now a test rather than a folder boundary. `core_files: 7` in `data/spine.yml` makes a new concept a design decision — raised from 6 on 2026-08-12 for `Proof`, the first raise since the spine was written. — gate: `test/core/test_no_lib_backedges.rb`, `rake lint:spine`
2. `knowledge/` is local-only — do not commit without updating `SearchKnowledge`. — gate: `rake security_sweep`
3. WebGL / face boot stays deferred until primer tap. — gate: `rake test:web_ui`, `test/test_web_ui.rb`
4. `RAILS/apps.horizon.yml` is agent-ignore horizon — do not implement unprompted. — no gate: a horizon file is a list of things deliberately not built, so there is no artefact to assert on; the failure mode is an agent building one, which only a reader of the diff can catch.
5. VPS: one app CI/deploy at a time on vm23. — no gate: concurrency on a remote host, enforced by the deploy lock on vm23 rather than by anything in this repo; a local check would assert against state it cannot see.
6. Secrets in `/etc/*.env` on VPS — never commit keys or generated assets. — gate: `rake security_sweep`, `RAILS/test/tracked_secrets_test.rb`
7. After `git pull` on vm23, run `vps-deploy` before expecting live health. — no gate: an ordering rule for two commands run on the VPS; nothing in the repo observes whether the box was deployed after its last pull.
8. Feature truth: `RAILS/apps.yml`; debt: `OPENBSD/data/debt.yml`. — gate: `RAILS/gates/lib/source/apps_yml.rb`
9. Never autonomously run `vmctl console/stop/start` or kill `cu` on server4 — see `OPENBSD/RUNBOOK.md`. — no gate: a prohibition on an action, not a property of the tree; the guard is the human-only env var in item 11.
10. Production VM is vm23 only (`dev@brgen.no`). — no gate: a deployment fact about the world; the repo cannot assert which host is production, only which one its scripts name.
11. `I_UNDERSTAND_CONSOLE_RISK=1` and `I_UNDERSTAND_DNS_WIPE=1` are human-only gates. — gate: `OPENBSD/vps_safety_gate.rb`
12. Dmesg every file op — see `OPENBSD/RUNBOOK.md`. — no gate: a habit for the operator's own audit trail, checkable only against a session transcript, which is not an artefact this repo keeps.

## Data File Budget (why so many YAML files)

`data/` is 47 yml (38 at the root) as of 2026-08-16, after the 2026-05 defrag plan's Tier-5 pass (2026-07-15) and the rule-shard fold: 9 files removed outright (dead — no code path ever loaded their content, despite some claiming otherwise in their own header comments), 13 folded into `patterns.yml` under namespaced keys, 1 folded despite having no enforced consumer (kept as reference documentation). **Do not merge blindly** — each remaining path has Ruby loaders and tests.

A handful of Tier-5-looking files were deliberately left alone rather than folded: `council.yml` (8+ consumers across the whole deliberation subsystem, protected by its own scanner rule), `state.yml` (backs standing-orders/autocommit via `DATA_ALIASES`), `topologies.yml`/`tts.yml` (feed the live web boot payload and TTS), `tools.dynamic.yml` (two-tier repo+user-override merge), `exemplars.yml`/`openbsd.yml` (active read-modify-write targets, not static config — folding would make routine runtime events rewrite the shared source-of-truth file). Folding any of these needs a real design decision, not a mechanical move.

`visual_clusters.yml` and `mobile_web_opportunities.yml` were on that list, defended as "deliberately parallel sources in `ClusterRegistry`". `ClusterRegistry` was deleted 2026-08-03 — 109 lines with zero callers — so the defense described a reader that did not run. **Both files deleted 2026-08-11.** Checked before cutting, because `data/runtime.yml` still listed `visual_clusters.yml` as the "canonical cluster registry" and that file *is* loaded (`lib/ground/runtime_catalog.rb`): the entry was a claim, not a reader. The live cluster source is `web/public/cluster_miner.js`, which mines them from events at runtime and never opens the YAML, and nothing serves either file to the browser. The `SelfTest` `clusters` SINGULARITY exemption went with them — an exemption outliving its subject is a hole in a gate nobody can see (`soul.yml` EXEMPTIONS_EXPIRE).

**Tier 1 — Law (4 files, do not collapse without a migration):**

- `soul.yml` — constitutional schema, sacred paths, anti-simulation. Separate from `rules.yml` because it outranks it: the constitution cannot sit inside the law it governs.
- `rules.yml` — every normative statement, whether it binds code, prose, or visual design: scanner law under `rules:` (four scopes, `codebase`/`file`/`line`/`unit`), plus `design_rules:`, `style:` and `operator_principles:`. Read it through `Master.law(section)`; `Ground::Rules#data(stem)` answers the call sites that ask by file stem.
- `limits.yml` — budgets, scan profiles, standing orders. Values, not law: a number folded in among rules reads as a rule.
- `voice.yml` — persona, TTS, speech

Rules live in one file because rules split across several grow definitions that disagree with nothing to notice. Split, `typography` carried two — `65ch` against an ideal of `66ch` — under a `SelfTest` exemption that permitted the duplication by name, and Nielsen's heuristics carried two sets, ten feeding a prompt and twelve feeding nothing.

**Tier 2 — Registries (edit when adding providers, models, tools):**

- `models.yml`, `providers.yml`, `agents/*.yml`, `personas.yml`, `tools.yml`, `mcp_servers.yml`

**Tier 3 — Runtime catalog (`data/runtime.yml`):**

- UI/face topology, event registry, routing notes — consolidated behind `RuntimeCatalog.load(section)`.

Documents outside `data/` that nothing links to are found by nobody — this sentence was the only thing linking two of them, which is not the same as being read. The principle-map audit is gone: its eight closed gaps are in git and its three open ones are in `DEBT.md`, where open work is looked for. The rest live under `docs/`: `REPAIR_PLAYBOOKS.md` for a red gate, `UI_POLISH_PLAYBOOK.md` for visual authority, `GITHUB_WATCH.md` for external projects worth reading.

**Tier 4 — Prose (3 allowed markdown files in `data/`):**

- `SOUL.md` — human mirror of absolute tier (pairs with `soul.yml`)
- `IDENTITY.md` — negotiable operator tone (not law)
- `CANON.md` — generated rule index

**Tier 5 — Everything else:**

- `bootstrap.yml`, `project_context.yml`, `patterns.yml`, etc. — operational memory. Consolidation target: fold into `patterns.yml` per the 2026-05 defrag plan in `project_context.yml`.

**Target end state:** 4 law YAMLs + 1 patterns + registries + 1 runtime catalog + 3 data markdown stubs. Top-level MASTER markdown: this file + `README.md` stub + `DEBT.md` / `DECISIONS.md` / `EXAMPLES.md` / `REPAIR_PLAYBOOKS.md` only when they hold living entries.

OPENBSD mirror: `OPENBSD/START_HERE.md` + `OPENBSD/RUNBOOK.md` — not duplicate MASTER law.

## Repo shape (run before big refactors)

```bash
zsh OPENBSD/tree.sh . --pub4-overview
```

Far-away visual tree with noise pruned and alignment notes. Do this before merging YAML/MD or restructuring folders.

## Source And Local State

- Source: `lib/`, `data/`, `bin/`, `test/`, `spec/`, `web/app/`, `web/public/`.
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
