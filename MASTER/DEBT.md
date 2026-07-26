# Debt Register

This file separates known debt from ordinary TODO work.

## Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## Current Tracks

### Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reports **6 findings as of 2026-07-26** (was claimed clean at
0 since 2026-07-16 — that claim was stale, and `START_HERE.md`/`AGENTS.md`
both lean on it):

- `[ABSTRACTION]` `lib/review/council/critique.rb:7` — god class, 308 lines
- `[DENSITY]` ×5 — `lib/fix/conflict_resolver.rb:39`,
  `lib/fix/fix_loop/rule_order.rb:23`, `lib/io/media_intent.rb:76`,
  `lib/trace/snapshot_agent_guide.rb:74`, `lib/voice/speech.rb:301`

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

- `/mode` raises NoMethodError in every form. `work_commands.rb:119` defines
  `dispatch_mode(root:, ctx:)` and `command_registry.rb:180` defines
  `dispatch_mode(config, ctx: nil)` in the *same module*; the later load
  wins and receives a String where a Config is expected.
- `/mode list` returns blank lines — `work_commands.rb:125` has an empty
  block body.
- `/orient bootstrap` returns a message telling you to run `/orient
  bootstrap`. `BootstrapDocs.keys` has no `bootstrap` key, and it is the
  first runtime dump advertised in `START_HERE.md`.
- `core/world.rb:167` returns a nil status on the `Timeout::Error` path, so
  `git_repo?`, `git_has_head?` and `git_capture` all NoMethodError on
  `.success?` when git wedges — inside the core spine.
- `Ground::Orders::Backup` is unregistered, and its `src` expands to
  `/home` rather than the repo root.

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

**Orphans** — zero references repo-wide: `lib/cli/hot_reload.rb` (while
`/reload` hardcodes "not supported in this context"), `lib/memory.rb`,
`lib/cli/routing/risk_classifier.rb`, `lib/ground/axioms/web_vitals.rb`,
`lib/ground/brutalist_minimalism.rb`, `lib/ground/persistence/sqlite_*.rb`,
`core/world.rb:187 shell_git`, `Io::Gateway`'s whole adapter layer.

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
