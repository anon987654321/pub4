# Debt Register

This file separates known debt from ordinary TODO work.

## Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## Current Tracks

### Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reports **0 findings as of 2026-08-01** (was 2 earlier that day,
0 on 2026-07-28, 7 on 2026-07-27, 6 on 2026-07-26; the earlier "clean since
2026-07-16" claim in `START_HERE.md`/`AGENTS.md` was stale, so treat this number
as true only for the commit that carries it).

The 2026-08-01 pair were both introduced by feature work that did not re-run the
scan, which is the shape to expect: `[ABSTRACTION] AstFixer is 302 lines` (the
class had grown two lines past the 300 limit) and `[DENSITY]
TtsSupervisor#ensure_pool_worker! is 22 code lines`, from the pool-leak fix in
`3481e2638`. Both closed by extraction rather than by moving a threshold — a new
`ast_fixer/syntax_transforms.rb` joins the two mixins that already existed,
taking everything that has to know the source language and leaving `AstFixer` as
dispatch plus the four whitespace transforms that know nothing; and
`replace_worker` / `back_off_after_failed_spawn` split the supervisor's respawn
path out of the lock block.

A second mixin for the whitespace transforms was written and then removed: with
the syntax transforms gone the class was at 169 lines, so the extra file bought
nothing but 44 lines against the spine ceiling below.

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

### Spine Ceiling Is Over, And The Raise Budget Is Spent

**operator-priority** — `rake lint:spine` is red on the working tree as of
2026-08-02: `lib/` is 47,837 lines against a ceiling of 47,660 (+177). Naming who
grew it, since the point of the ratchet is that this is legible:

- ~98 lines from work already uncommitted in the tree before this pass — the
  `AstFixer` split (`ast_fixer.rb` −128, new `ast_fixer/syntax_transforms.rb` +162)
  plus `voice/engines.rb`, `voice/mix_metrics.rb` and `voice/tts_supervisor.rb`.
- ~75 from the 2026-08-01 debt pass (the inert-config wiring, the two narrowed scan
  rules, the four defects the new tests found). Roughly half of that was rationale
  comments, since trimmed to a sentence each with the full accounting moved into
  this file.

`data/spine.yml` says the next raise fails the check: `consecutive_raises_allowed:
2`, and both entries are used (2026-07-31 and 2026-08-01). Its own note says what to
do about it — "if it is raised again without `lib/` ever falling back, the honest
conclusion is that 'the spine never grows' is not the invariant anyone is holding,
and the number should be replaced by one that is." That is a decision with a
sponsor, not a ceiling edit, so no agent should grant it.

Worth recording alongside: `lint:spine` counts every line in `lib/**/*.rb`,
comments included, while `[DENSITY]` was deliberately changed on 2026-07-28 to count
*code* lines precisely so this codebase's convention of a rationale paragraph above
the tricky line is not penalised. The two rules therefore pull opposite ways on the
same edit. Whoever resolves the ceiling should decide which of them means it.

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

**Known flake — cause found and closed 2026-08-02**

`TurnRouterTest` failed intermittently with `assert result.ok?` false — recorded
on 2026-07-28 as order-dependent and unexplained, and seen again on 2026-08-02 as
`test_plain_language_routes_to_fold`, this time with a message that named the
mechanism: `fold errored: chat: undefined method 'call' for an instance of
#<Class:…>`.

`CLI#initialize` calls `set_visitor_mode_if_unauthenticated`, which sets
`Fiber[:master_visitor] = true` whenever the config carries no `web_token`. Every
container in `test_cli.rb` and `test_cli_bridge.rb` is tokenless, so building one
flipped the flag — and fiber storage outlives the test. Any later test reaching
`TurnRouter.call` then took the visitor branch to `casual_reply`, which calls
`agent.call` on a stub agent that only answers `:model`; hence a chat error inside
a test about the Fold. `TurnRouterTest` cleared the flag in `teardown`, which
protected it from itself and from nothing else.

Closed by clearing the flag in both CLI test files' `teardown` and, defensively,
in `TurnRouterTest#setup`. Verified two ways: a probe asserting that building a
tokenless CLI sets the flag, and that with the flag set `TurnRouter.call` leaves
the Fold path.

Not a product defect — a real CLI reads a 64-char `web_token` from
`.master/config.yml`, so the operator is not a visitor. But it is worth knowing
that constructing a `CLI` object anywhere flips a security-relevant process-wide
flag that nothing clears; the web path (`application_controller.rb`,
`chat_service.rb`) sets and clears it per request, the CLI sets it for the life of
the process.

**Scanner noise** — both named rules narrowed 2026-08-01. `rake selfcheck` went
**71 → 34**; `STALE_NAMESPACE` 25 → 0 and `COMPLETION_THEATER` 12 → 0.

`STALE_NAMESPACE` built `/\bMaster::CLI\b/`, and `\b` sits between a letter and a
colon — so it matched inside `Master::CLI::Stages`, and `Master::CLI`'s own recorded
replacement is `Master::CLI::CLI`. Every legitimate reference under any renamed
namespace was reported as a retired constant. A retired name now counts only as a
whole constant path: not followed by `::` or a word character, not preceded by one.
Its self-exemption also named `stale_namespace_rule.rb`, a file that no longer
exists — the rule lives in `naming_rules.rb`.

`COMPLETION_THEATER`'s etcetera half was `/\betc\.?\b/i`, matching `require "etc"`,
`Etc.nprocessors`, and every `/etc/…` path in the deploy code. It is now
case-sensitive (excluding the `Etc` constant), rejects a neighbouring slash
(excluding paths), and names the stdlib require outright. The one real finding it
had been hiding is fixed: `SubdomainOrchestrator::DESCRIPTION` listed five of twelve
clusters and closed with "etc." in a string the model reads to decide whether the
tool can serve a request, while `call` rejects anything outside `CLUSTER_DOMAINS`.

`test/test_scan_rule_false_positives.rb` asserts both directions for both rules —
the false positive is gone *and* the real violation still fires. The remaining 34
are `EMPTY_RESCUE` (10), `guard_expensive_ops` (9), `SILENT_RESCUE` (9),
`DEBUG_OUTPUT` (2), `UNBOUNDED_RETRY` (2), `bare_rescue` (1), `fail_visibly` (1);
the last two are the autofixer that repairs bare rescues flagging its own source.

**Inert law and config**

Roughly 28 of `data/limits.yml`'s 39 top-level keys have no reader, and the
generic accessor `workflow_rule(key)` has zero call sites — ~70% of 794
lines of Tier-1 "law" is decoration. **Still open.**

Three named instances closed 2026-08-01, each differently, and the difference is
the interesting part:

- `data/models.yml`'s `fallback_policy` was inert three ways at once: the key was
  written bare as `on:`, which YAML 1.1 parses as the boolean `true`; nothing read
  `fallback_policy` at all; and the category names it listed (`network_error`,
  `refusal`, `insufficient_balance`, `quota_exceeded`) are not categories any
  `Result.err` in this codebase carries, so wiring it as written would have matched
  nothing. It now speaks the real vocabulary and
  `ModelRouter#failover_skip_categories` reads it, replacing the hardcoded
  `Agent::FallbackChain::NON_RETRYABLE` (which stays as the no-router default). The
  behavioural change: a rate-limited or out-of-budget model is now skipped rather
  than retried in place, which it could never have succeeded at.
  `retries_per_tier` was removed — `failover.max_retries` is the one source.
  Pinned by `test/test_failover_policy.rb`.
- `data/style.yml`'s typography ratio was read as `typography["ratio"]`, one level
  above where the file puts it (`typography.scale.ratio`), so the hardcoded 1.25
  fallback was the only value the persona prompt ever carried. `measure` and
  `leading` were literals beside it for the same reason. Fixed in
  `lib/voice/personality_prompt_builder.rb`.
- `data/security/defaults.yml` had exactly one key with a reader
  (`tools.custom.require_review_for_destructive`) out of a file describing a
  "local-first, zero-listener, explicit pairing, fail-closed" system. The ingress
  rate limit was worse than inert — the same number was hardcoded in
  `IngressController`, so file and code could disagree silently. The file is now
  split into enforced keys and a `planned:` block holding the intent that has no
  implementation (gateway bind, dashboard, session trust tiers, pairing TTL and
  allowlist path, the five tool `deny_patterns`), and
  `test/test_security_defaults.rb` fails in both directions: an enforced key that
  loses its reader, and a planned key that gains one.

`data/limits.yml` is the remaining instance and the largest.

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

Same shape as the kill list in the old `core/ABSORPTION.md` (now
`core/SEVERANCE.md`), which was written from names rather than references and
turned out to be mostly load-bearing. Verify before deleting, even when this file
says a thing is dead.

**Test coverage** — the eight named constants are covered as of 2026-08-01:
`SsrfGuard` (`test/io/test_ssrf_guard.rb`), `CommitGuard`
(`test/lib/review/commit_guard_test.rb`), `Permissions`
(`test/lib/review/security/permissions_test.rb`), `StandingOrders`
(`test/lib/ground/standing_orders_test.rb`), `PatchApplier`
(`test/fix/test_patch_applier.rb`), `AtomicWrite`
(`test/lib/ground/atomic_write_test.rb`), `GitOperations`
(`test/io/test_git_operations.rb`), `KeyRotator`
(`test/lib/ground/key_rotator_test.rb`). Writing them found four live defects, all
fixed in the same pass — which is the argument for the rest of the list:

- `lib/io/ssrf_guard.rb` never required `uri`. `safe_uri?` does
  `uri.is_a?(URI::HTTP)` inside a blanket rescue, so in any process that had not
  already loaded `uri` the NameError was swallowed and the guard answered false for
  every URL: web_fetch silently disabled, one `Swallow.log` line, no other symptom.
- `Permissions.blocked?` matched its whole blocklist with bare `include?`, so
  "sudo" inside "pseudo" and "halt" inside "shalt" made `grep -rn
  shutdown_handler lib` and `grep -rn pseudocode lib` both refuse as dangerous.
  Bare-word entries now match on word boundaries; operator/path entries stay literal.
- `PatchApplier` kept only stderr, but `patch(1)` reports a failed hunk on stdout —
  the most common real failure produced `Failure.new(reason: "")` and the autofix
  loop logged a rejection with no reason.
- `GitOperations#dirty_count` counts status *lines*, not files: git collapses a
  wholly-untracked directory to one `?? lib/` line. Documented in the test rather
  than changed, since callers only ask "is anything dirty".

188 of ~400 `lib/` files still have no test naming their primary constant.

`rake test:subsystems` now runs in the `operator` and `contributor` profiles
(17s), so the 14 files under `test/{cli,io,fix,lib}/` are no longer skipped by the
gate `START_HERE.md` tells contributors to run.

**Doc drift** — closed 2026-08-01. `core/ABSORPTION.md` no longer exists (it is
`core/SEVERANCE.md`, a record rather than a plan) and `AGENTS.md` no longer sends
agents there; the retired folder names `reach/`, `judge/`, `now/`, `loop/` appear in
no current doc. `START_HERE.md:10` already describes `--profile=agent` correctly.
What was still stale and is now fixed: `START_HERE.md` described the two spines as
lasting "until absorption cutover" and told agents not to merge them "before
absorption completes", contradicting `DECISIONS.md`, which frames them as
permanent.

### Host TTS Binaries

**operator-priority** — TTS end-to-end audio depends on host binaries such as `edge-tts` and `espeak`. Web wiring can be correct while synthesis is unavailable locally. Check `GET /health` deploy.tts_socket and `test -S .master/tts.sock` on vm23.

**ffmpeg** — closed 2026-08-01, both halves. `OPENBSD/OPERATOR.sh:399` does
pkg_add ffmpeg at stage 1 (the entry above said it did not; that was true on
2026-07-27 and stale by the time it was read). And the silent-degradation half
is gone: `lib/voice/engines.rb`'s two `ffmpeg?` fallbacks — `concat_mp3` and the
WAV→MP3 conversion — used to return quietly, so a host without ffmpeg served
un-concatenated or unconverted audio with nothing logged anywhere. They now
report through `Swallow.log(..., severity: :load_bearing)` naming the
consequence, so the degraded state is visible instead of merely quiet. `ffmpeg?`
is also memoized; it was a fork+exec of which(1) per synthesized phrase.

Any future post-synthesis DSP should call `report_missing_ffmpeg` on its own
fallback path rather than returning silently.

Still true, and the reason this section exists: `pkg_add` succeeding at install
time is not evidence ffmpeg is on the box now. Check `GET /health`
deploy.tts_socket and `test -S .master/tts.sock` on vm23.

## Not Debt

- Two `Master::` spines.
- Split rule registries.
- Local `knowledge/` corpus.
- Generated `output/` artifacts.
- Deferred WebGL boot.
- Media-generation severance: re-severed 2026-07-14 (`76b11fec4`) after the
  2026-07-08→09 reintroduction; operator decision confirmed permanent
  2026-07-15. `core/SEVERANCE.md` is the source of truth. If the Ragnhild
  LoRA training loop needs generation capability again, express it as
  `core/world.rb` handlers per the original absorption plan — do not restore
  `lib/io/lora_pipeline.rb`/`video_chain.rb`.
