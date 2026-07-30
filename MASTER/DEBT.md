# Debt Register

This file separates known debt from ordinary TODO work.

## Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## Current Tracks

### Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reports **0 findings as of 2026-07-28** (was 7 on 2026-07-27,
6 on 2026-07-26; the earlier "clean since 2026-07-16" claim in
`START_HERE.md`/`AGENTS.md` was stale, so treat this number as true only for
the commit that carries it).

The `[ABSTRACTION]` finding closed by splitting `lib/review/council/critique.rb`
(308 lines) into three files with distinct jobs: `critique/modes.rb` (the mode
table — configuration, and a third of the old body), `critique/context.rb` (the
panel's briefing prose), and `critique/cherry_pick.rb` (idea/critique overlap
ranking). `Critique` itself is now orchestration only. `Critique::MODES` still
resolves.

The six `[DENSITY]` findings closed by two different mechanisms, and the
distinction matters when reading the count:

- Real extractions — `lib/fix/conflict_resolver.rb` (`priority_of`,
  `findings_introduced`), `lib/trace/snapshot_agent_guide.rb`
  (`binary_inlining_note`).
- A change in what DENSITY measures. `lib/review/scan/rules/structural_rules.rb`
  now counts *code* lines, excluding blank lines and whole-line comments,
  instead of the raw `start_line..end_line` span. The old measure penalised
  this codebase's own convention of a rationale paragraph above the tricky
  line — `Cli::TurnRouter.call` was reported at 22 lines while holding 10 of
  code and 8 of comment, so the only way to satisfy the rule was to delete the
  explanation. Do not read the drop as six refactors.

`lib/voice/speech.rb:301` is no longer reported. Note
`test/test_heartbeat.rb:44` (`self_test_heartbeat_publishes_clean_scan_metrics`)
fails *because* this count is non-zero — it is a symptom of this track, not an
independent defect.

Triage each new finding as:

- true violation to fix
- scanner false positive
- rule exemption needed
- rule threshold too strict
- known debt to leave alone during unrelated work

### Constitution Scan Debt

**agent-ignore** — `rake constitution` is broader than `rake selftest` and still reports thousands of self-scan findings. Do not chase zero. Track the count down by removing false positives and fixing high-signal violations.

### Web Face Verification

Voice Mode and boot contracts are covered by `web/test/face_boot.test.mjs` (static assertions on `face.runtime.js`). The WebGL primer guard has the same pattern. Manual iOS Safari tap-testing remains operator-priority when boot assets change materially.

Recent: Voice Mode re-arm, wake-word, browser-first TTS (`face.part1.txt`, `face.part5.txt`, `face_speech_runtime.js`).

### Audit Backlog (2026-07-26)

Full-tree audit of `lib/`, `core/`, `data/`, `bin/`. The crash-level items
found in the same pass are already fixed (see `git log` for 2026-07-26:
AST autofix engine, `council.yml` questions, `bin/pub4 status`, `tools.yml`,
two post-rename guard tests). What remains, unfixed and unverified beyond
the audit itself:

**Broken on contact — operator-priority**

All clear. Everything listed here on 2026-07-26 is fixed and covered.

Fixed 2026-07-28, each with a regression test
(`test/test_mode_and_orders.rb`, `test/core/test_world.rb`,
`test/test_workflow_inference.rb`, `test/test_heartbeat.rb`):

- `/orient bootstrap` answered by telling you to run `/orient bootstrap` —
  `BootstrapDocs` had no `bootstrap` key, so `cat_orient` fell through to the
  nil-path branch of `ORIENT_FILES`. It is now an index over the other
  sections, built from their own first lines so it cannot drift. A guard test
  asserts every fileless `/orient` topic resolves to a document.
- `ThroughPipeline` formatted stage crashes into the report as prose and still
  printed `through0: complete`. `NameError`/`TypeError` now propagate;
  operational failures degrade to prose *and* mark the run incomplete, naming
  the stage. `dispatch_critique` used `deliberation&.agent`, which guards nil
  but not a deliberation without an agent.
- `TestHeartbeat`'s fixtures wrote `data/heartbeat.yml`, a file the product
  does not read (`Heartbeat#load_jobs` reads `data/patterns.yml#heartbeat`), so
  all three tests silently exercised the *default* job list. The clean-scan
  case was additionally unreachable: a bare fixture root has no
  `data/principle_map.yml`, which is itself a self-test finding. This was not,
  as previously recorded here, a symptom of the selftest count.

- `/mode` raised NoMethodError in every form — two unrelated features both
  defined `dispatch_mode` in `Master::CLI::CommandRegistry`. The session
  posture keeps `/mode` (which is what `help.rb` documents); the
  reasoning-mode command is now `/reasoning`. A guard test fails if any
  `dispatch_*` name is ever defined in two of the command modules again.
- `/mode list` returned blank lines — the map block had an empty body. It
  now renders every posture through the same formatter as the status line,
  marking the active one.
- `core/world.rb` returned a nil status on the `Timeout::Error` path.
  `bounded_capture2e` now returns `World::TIMED_OUT`, which answers
  `success?` with false, so a wedged git surfaces as a normal failure
  instead of a NoMethodError inside the fold. `apply_patch_reverse` was
  also still on raw `Open3` and is now bounded like every other git call.
- `Ground::Orders::Backup` is registered (`callable: backup`) and declared
  in `data/state.yml` as manual + disabled — it pushes the whole tree to a
  remote host, so it is reachable but does not turn itself on. Its source
  is `File.expand_path("..", root)`, the repo root, not three levels up.

**Known flake — unreproduced**

`TurnRouterTest#test_run_promotes_to_fold` failed once during the
2026-07-28 pass (`assert result.ok?` returned false) and did not recur in
four further full runs; it passes in isolation and alongside the new test
file. Order-dependent, cause not established.

**Scanner noise — agent-ignore until scan rules are the task**

38 of `rake selfcheck`'s 76 findings are false positives from two rules:
`COMPLETION_THEATER` matches `require "etc"`, `Etc.nprocessors` and
`/etc/*` paths; `STALE_NAMESPACE` flags every legitimate `Master::CLI::*`
reference because `\b` matches before `::`.

**Inert law and config**

Roughly 28 of `data/limits.yml`'s 39 top-level keys have no reader, and the
generic accessor `workflow_rule(key)` has zero call sites — ~70% of 794
lines of Tier-1 "law" is decoration. Same shape in `data/security/defaults.yml`
(`deny_patterns`, `code_ttl_seconds`, `rate_limit_per_minute` enforce
nothing), `data/models.yml` (`on:` parses as boolean `true`), and
`data/style.yml` (typography ratio read at the wrong depth, so edits do
nothing).

**Orphans** — closed 2026-07-30. Six files deleted (396 lines):
`lib/cli/hot_reload.rb` (`/reload` still hardcodes "not supported in this
context", which is now honest), `lib/cli/routing/risk_classifier.rb`,
`lib/ground/axioms/web_vitals.rb`, `lib/ground/brutalist_minimalism.rb`,
`lib/ground/persistence/sqlite_findings.rb`, `sqlite_memory.rb`. Plus
`lib/memory.rb`, a five-line `Memory = Ground::Memory` alias that only
`test/test_web_ui.rb` named; its three call sites now name
`Master::Ground::Memory`.

Three entries on the old list were **wrong**, and the reference sweep is why
this is worth recording rather than just deleting:

- `lib/ground/persistence/sqlite_store.rb` — the `sqlite_*.rb` glob overreached.
  `lib/ground/knowledge_store.rb:12` includes it and `test/test_sqlite_store.rb`
  covers it. Load-bearing.
- `Io::Gateway` — instantiated at `lib/builder.rb:228` in the live boot, with
  `test/test_gateway_client_actions.rb` over it. Not an adapter layer nobody
  calls.
- `core/world.rb:187 shell_git` — already gone; the line reference was stale.

Same shape as `core/ABSORPTION.md`'s kill list, which was written from names
rather than references and turned out to be mostly load-bearing. Verify before
deleting, even when this file says a thing is dead.

**Test coverage** — no test names these constants: `SsrfGuard`,
`CommitGuard`, `Permissions`, `StandingOrders`, `PatchApplier`,
`AtomicWrite`, `GitOperations`, `KeyRotator`. 188 of ~400 `lib/` files have
no test naming their primary constant. Separately, `rake test:subsystems`
runs in no `bin/check` profile except `full`, so 14 files under
`test/{cli,io,fix,lib}/` are skipped by the documented contributor gate.

**Doc drift** — `core/ABSORPTION.md`'s subsystem table still uses the
retired folder names `reach/`, `judge/`, `now/`, `loop/`, and `AGENTS.md`
sends agents there as the canonical guide. `START_HERE.md:10` describes
`--profile=agent` as "law, scanners, loop, routing"; it is exactly
`rake selftest` + `rake lint:data_singularity`.

### Host TTS Binaries

**operator-priority** — TTS end-to-end audio depends on host binaries such as `edge-tts` and `espeak`. Web wiring can be correct while synthesis is unavailable locally. Check `GET /health` deploy.tts_socket and `test -S .master/tts.sock` on vm23.

**ffmpeg is not installed on vm23** (verified 2026-07-27). `OPENBSD/OPERATOR.sh:391`
pkg_adds `… fd espeak` with no ffmpeg, and nothing else in `OPENBSD/` installs it.
`lib/voice/engines.rb` gates on `ffmpeg?` (:307), so `concat_mp3` (:234) and the
WAV→MP3 conversion (:297) **silently skip in production** — no error, just
un-concatenated or unconverted audio. Works on a Mac, degrades on the VPS,
which is the worst failure shape. Either add `ffmpeg` to that pkg_add line or
make the guard report through `lib/voice/output_guard.rb` instead of returning
quietly. Any future post-synthesis DSP would no-op the same way.

## Not Debt

- Two `Master::` spines.
- Split rule registries.
- Local `knowledge/` corpus.
- Generated `output/` artifacts.
- Deferred WebGL boot.
- Media-generation severance: re-severed 2026-07-14 (`76b11fec4`) after the
  2026-07-08→09 reintroduction; operator decision confirmed permanent
  2026-07-15. `core/ABSORPTION.md` is the source of truth. If the Ragnhild
  LoRA training loop needs generation capability again, express it as
  `core/world.rb` handlers per the original absorption plan — do not restore
  `lib/io/lora_pipeline.rb`/`video_chain.rb`.
