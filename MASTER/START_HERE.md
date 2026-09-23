# Start Here

MASTER is a constitutional AI runtime in Ruby. Models propose; the runtime
validates against `data/soul.yml`, `data/rules.yml`, and its scanner rules
before durable writes. The Rails face in `web/` mirrors runtime state at
`https://ai.brgen.no`.

**Orientation:** `AGENTS.md` for task-scoped agent entry; this file for the full
contract. Law and config live in YAML under `data/`. Prose stubs:
`data/SOUL.md`, `data/IDENTITY.md`, generated `data/CANON.md`. Work is a
sentence. The slash set is `/review` `/fix` `/status` `/undo` `/commit` `/model`
`/pair` `/doctor` `/runtime` `/rules` `/why` `/orders` `/soul` `/help` `/clear`,
with `/rollback` as `/undo` and `/exit` or `/quit` to leave. `/fix` is the only
writing verb: it runs the complete observe, repair, re-observe and proof lifecycle.
Retired spellings such as `/scan`, `/sweep`, `/through`, `/workflow`, `/triad`,
`/self` and `/council` are normalized to the current command surface rather
than silently falling into conversation.

## Safe First Commands

- `bin/check` — default gate. Runs the **operator** profile, not the contributor
  one; `--profile=contributor` is the same list minus `test:core`. The step
  lists are `PROFILES` in `bin/check`, and that table is the only copy.
- `bin/check --profile=agent` — `selftest`, the data and dedup lints,
  `lint:word_boundary` and `studio`; no unit suite.
- `bin/check --profile=web` — face/assets; set `MASTER_WEB_LIVE=1` for live web
  checks. It is the only path to `test_web_ui.rb`, `test_web_http.rb` and
  `test_browser.rb`, which `rake test` excludes.
- Opt-in tests, off in every default run: `rake test:cli_e2e` boots `bin/cli`
  as a subprocess (`MASTER_CLI_E2E=1`), and `SUITE_AUDIT=1` runs
  `test_suite_actually_runs.rb`, one process per test file.
- `bin/check --profile=full` — operator-grade probe path.
- `bin/check --format=brief` — structured pass/fail with debt hints (pair with
  any profile).
- The other diagnose verbs each answer one question. `bin/ci` is
  `bin/check --profile=ci` under the name workflows call. `bin/doctor` asks
  whether this host can run MASTER: ruby, bundle, keys, the TTS socket, the web
  token. `bin/smoke` boots the runtime and checks its wiring, and `bin/smoke-web`
  asks the same of a running face over HTTP. `bin/dogfood` drives `bin/cli` and
  `bin/master-core` end to end, where `rake dogfood` proves law/ against its
  own fixtures. `bin/probe` runs any of them, and the RAILS and OPENBSD gates,
  as named subprocesses (`quick`, `all`, `deploy`). Staged lines go to
  `bin/operator lint --staged --changed-lines`.
- `/fix [path]` observes, critiques, repairs, and observes again until it converges or says why it stopped. For `RAILS` and `MASTER/web`, each pass also measures the rendered browser surface and feeds the real screenshot plus geometry to the existing UI Council. It can therefore correct visual hierarchy, typography, spacing, alignment, density and composition even when source rules already pass. The same pass detects high-confidence maintenance opportunities such as stale paths, dead task globs, duplicate mechanisms and coordinator sprawl, then sends them through the same guarded repair path. `/scan` does not exist.

Recovery: `/runtime status` shows the last known-good commit, `/runtime promote` records the current committed HEAD, and ``/runtime rollback --confirm` restores that commit only when the checkout is clean.
- Work: say the path. `/fix [path]` is the operation that changes the tree —
  observe, critique, repair, observe again, until it converges or says why it
  stopped. `/review [path]` reads and argues without writing, and its stages are
  `--only critique` and `--only map`. `/fix --dry-run` stops after the reading
  and says what it would take on. There is no `/scan`.

## Runtime Map

The repo-root `TREE.md` is the map of every directory, `lib/` included. The
path a turn takes: `bin/cli` builds the container with
`Master.bootstrap_container`, `lib/cli` routes the turn, `lib/review` scans and
deliberates, `lib/io` acts, `lib/fix` repairs, and `lib/trace` records. Beside
that path sit `lib/core` (the fold spine: Effect, Constitution, World, Memory),
`lib/ground` (configuration and policy), `lib/voice` (persona and speech),
`lib/cognition` (perception and affect, argued in `COGNITION.md`),
`lib/operator` (the libraries behind `bin/operator` and `bin/check`), `law/`
(one domain file per body of law) and `web/` (the Rails face).

High-risk boundaries: `data/soul.yml`, `data/rules.yml`, `lib/master.rb`,
`lib/core.rb`, `web/app/views/chat/index.html.erb`, `web/public/face*`,
`lib/io/`, `.master/`.

## Agent Contract

**Modes:** contributor (narrow patches + `bin/check`), operator (full gates +
deliberate policy edits), agent (this contract + `bin/check --profile=agent`
when touching law).

**Work rules:** preserve behavior first; read before writing; keep
generated/local artifacts out of commits; report blocked checks with exact
command and first failure class; document intentional exceptions.

**Checks by change type:**

| Change | Command |
|--------|---------|
| Ordinary code | `bin/check` |
| Law / scanners / loop | `bin/check --profile=agent` |
| Web face | `bin/check --profile=web` |
| Deploy / Rails | `OPENBSD/bin/check-rails --profile=contributor` |
| Operator / release | `MASTER/bin/operator gate` — the whole ladder; `check-full`, `check-rails` and `RAILS/gates/runner.rb` are its rungs |

**Do not optimize away:** the fold spine's independence from the rest of `lib/`
— `lib/core*` requires nothing outside its own namespace, held by
`test/test_core_no_lib_backedges.rb`; deferred WebGL until primer tap.

## Do Not Touch (unless the task requires it)

Every entry names the gate that fails when its claim stops being true, or says
why no gate can hold it. This is not decoration: item 2 of this list used to be
"rule data stays split, because each shard sits near its consumers", and that
reason had been false since the day the shards were created — the four of them
had one consumer between them. A conclusion does not rot loudly. A test does.
`rake lint:do_not_touch` checks that every entry below carries one and that the
gates it names exist.

1. `lib/core.rb` and `lib/core/` are the fold spine, and they must not require
   the rest of `lib/`. The two-spine *directory* split ended 2026-08-12
   (the record of it went with `docs/`); the dependency direction it was
   protecting did not, and is now a test rather than a folder boundary. `core_files: 7` in
   `data/spine.yml` makes a new concept a design decision — raised from 6 on
   2026-08-12 for `Proof`, the first raise since the spine was written. — gate:
   `test/test_core_no_lib_backedges.rb`, `rake lint:spine`
2. `knowledge/` is local-only — do not commit without updating
   `SearchKnowledge`. — gate: `rake security_sweep`
3. WebGL / face boot stays deferred until primer tap. — gate: `rake
   test:web_ui`, `test/test_web_ui.rb`
4. `RAILS/apps.horizon.yml` is agent-ignore horizon — do not implement
   unprompted. — no gate: a horizon file is a list of things deliberately not
   built, so there is no artefact to assert on; the failure mode is an agent
   building one, which only a reader of the diff can catch.
5. VPS: one app CI/deploy at a time on vm23. — no gate: concurrency on a remote
   host, enforced by the deploy lock on vm23 rather than by anything in this
   repo; a local check would assert against state it cannot see.
6. Secrets in `/etc/*.env` on VPS — never commit keys or generated assets. —
   gate: `rake security_sweep`, `RAILS/test/tracked_secrets_test.rb`
7. After `git pull` on vm23, run `vps-deploy` before expecting live health. — no
   gate: an ordering rule for two commands run on the VPS; nothing in the repo
   observes whether the box was deployed after its last pull.
8. Feature truth: `RAILS/apps.yml`; backlog and debt: repo-root `TODO.md`. —
   gate: `RAILS/gates/lib/source/apps_yml.rb`
9. Never autonomously run `vmctl console/stop/start` or kill `cu` on server4 —
   see `OPENBSD/RUNBOOK.md`. — no gate: a prohibition on an action, not a
   property of the tree; the guard is the human-only env var in item 11.
10. Production VM is vm23 only (`dev@brgen.no`). — no gate: a deployment fact
    about the world; the repo cannot assert which host is production, only which
    one its scripts name.
11. `I_UNDERSTAND_CONSOLE_RISK=1` and `I_UNDERSTAND_DNS_WIPE=1` are human-only
    gates. — gate: `OPENBSD/gates/vps_safety_gate.rb`
12. Dmesg every file op — see `OPENBSD/RUNBOOK.md`. — no gate: a habit for the
    operator's own audit trail, checkable only against a session transcript,
    which is not an artefact this repo keeps.

## Data File Budget (why so many YAML files)

`data/` is YAML at the root as of 2026-08-19, after the
2026-05 defrag plan's Tier-5 pass, the rule-shard fold, and the
one-item-directory collapse (agents/ was empty, harnesses/ and skills/ had no
reader, prompts/ ops/ security/ templates/ web/ each held one item now folded to
the root or beside their consumer, traces/ was runtime output writing into the
law tree): 9 files removed outright (dead — no code path ever loaded their
content, despite some claiming otherwise in their own header comments), 13
folded into `patterns.yml` under namespaced keys, 1 folded despite having no
enforced consumer (kept as reference documentation). **Do not merge blindly** —
each remaining path has Ruby loaders and tests.

A handful of Tier-5-looking files were deliberately left alone rather than
folded: `council.yml` (8+ consumers across the whole deliberation subsystem,
protected by its own scanner rule), `state.yml` (backs
standing-orders/autocommit via `DATA_ALIASES`), `topologies.yml`/`tts.yml` (feed
the live web boot payload and TTS), `tools.dynamic.yml` (two-tier
repo+user-override merge) and `openbsd.yml` (the validator table
`Ground::OpenbsdConfig` reads). Folding any of these needs a real design
decision, not a mechanical move.

**Tier 1 — The constitution, the law, and the values beside it (4 files, do not
collapse without a migration):**

- `soul.yml` — constitutional schema, sacred paths, anti-simulation. Separate
  from `rules.yml` because it outranks it: the constitution cannot sit inside
  the law it governs.
- `rules.yml` — every normative statement, whether it binds code, prose, or
  visual design: scanner law under `rules:` (four scopes,
  `codebase`/`file`/`line`/`unit`), plus `design_rules:`, `style:` and
  `operator_principles:`. Read it through `Master.law(section)`;
  `Ground::Rules#data(stem)` answers the call sites that ask by file stem.
- `limits.yml` — budgets, scan profiles, standing orders. Values, not law: a
  number folded in among rules reads as a rule. Only the top-level keys
  `test/test_limits_split.rb` names have a reader; everything under `guidance:`
  is prose for people.
- `voice.yml` — persona, TTS, speech

Rules live in one file because rules split across several grow definitions that
disagree with nothing to notice. Split, `typography` carried two — `65ch`
against an ideal of `66ch` — under a `SelfTest` exemption that permitted the
duplication by name, and Nielsen's heuristics carried two sets, ten feeding a
prompt and twelve feeding nothing.

A rule has three homes and no fourth. `rules.yml` declares it; `law/*.rb`
defines domain law with `Law.define`, each carrying the example it must flag and
the one it must not; and `lib/review/scan/rules/*.rb` builds the scanner
registry, by `RuleDSL.rule` or a `Rule` subclass that calls `declare`. A rule
defined anywhere else reaches no gate.

**Tier 2 — Registries (edit when adding providers, models, tools):**

- `models.yml`, `providers.yml`, `personas.yml`, `tools.yml`, `mcp_servers.yml`

**Tier 3 — Runtime catalog (`data/runtime.yml`):**

- UI/face topology, event registry, routing notes — consolidated behind
  `RuntimeCatalog.load(section)`.

Documents outside `data/` that nothing links to are found by nobody — this
sentence was the only thing linking two of them, which is not the same as being
read. The principle-map audit is gone: its eight closed gaps are in git and its
three open ones are in the repo-root `TODO.md`, where open work is looked for.
The rest are gone. `docs/` was codified into `data/runtime.yml` in `3797afea7`
and its last four files went in `3e2f32f76`, a commit about a deploy gate that
swept them up — so `REPAIR_PLAYBOOKS.md`, `UI_POLISH_PLAYBOOK.md`,
`GITHUB_WATCH.md` and `SEVERANCE.md` have no successors and no section in the
catalog. For a red gate read the gate's own output and `TODO.md`; for visual
authority read `RAILS/shared/WIRING_NOTES.md`, which is maintained.

**Tier 4 — Prose (3 allowed markdown files in `data/`):**

- `SOUL.md` — human mirror of absolute tier (pairs with `soul.yml`)
- `IDENTITY.md` — negotiable operator tone (not law)
- `CANON.md` — generated rule index

**Tier 5 — Everything else:**

- `project_context.yml`, `patterns.yml`, etc. — operational
  memory. Consolidation target: fold into `patterns.yml` per the 2026-05 defrag
  plan in `project_context.yml`.

**Target end state:** 4 law YAMLs + 1 patterns + registries + 1 runtime catalog
+ 3 data markdown stubs. Top-level MASTER markdown: this file + `README.md` stub
+ `EXAMPLES.md` only while it holds
living entries (the debt register moved to the repo-root `TODO.md`).

OPENBSD mirror: `OPENBSD/START_HERE.md` + `OPENBSD/RUNBOOK.md` — not duplicate
MASTER law.

## Repo shape (run before big refactors)

```bash
zsh OPENBSD/bin/tree.sh . --pub4-overview
```

Far-away visual tree with noise pruned and alignment notes. Do this before
merging YAML/MD or restructuring folders.

## Music

`Music::Synth.render`/`.play` write a WAV and hand it to afplay/ffplay — one
buffer, one file, one shot. `Music::Realtime.play(shape:, hz:, seconds:)` and
`.morph(hz:, seconds:, shapes:)` skip the file: they generate frames in
1024-sample blocks and stream them straight to a live `AudioSink` (sox or
ffplay reading raw PCM on stdin), so a long or continuously-changing sound
never sits on disk. From `bundle exec ruby bin/cli`, call
`Master::Music::Realtime.morph(hz: 440, seconds: 6)` directly from the
console rather than through an agent turn — synthesis is cheap and
immediate, and no model call belongs on the path between a waveform formula
and the speaker.

## Source And Local State

- Source: `lib/`, `data/`, `bin/`, `test/`, `spec/`, `web/app/`, `web/public/`.
- Local/generated: `.master/`, `knowledge/`, `output/`, `web/public/assets/`,
  `web/storage/`, `web/log/`.

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
- Settle ambiguity in a present-tense comment beside the code, a bullet under
  "Refused, and why" in `AGENTS.md`, or the repo-root `TODO.md`.
- Face boot: read `web/CLAUDE.md` first.
- RAILS app CSS/visual work: read `RAILS/shared/WIRING_NOTES.md`'s "Visual
  design system" section first — x.com is the base reference, tokens live in
  `RAILS/shared/app/assets/stylesheets/_dialect_tokens.scss`, and the flat-only
  (no shadow/blur/glow) rule applies repo-wide.
