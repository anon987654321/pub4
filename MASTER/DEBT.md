# Debt Register

This file separates known debt from ordinary TODO work.

## Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## Current Tracks

### Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reports **0 findings as of 2026-08-03** (1 earlier that day —
`[DENSITY] Pub4::CheckRunner#run is 21 code lines`, closed by splitting the
announce and report halves out of it; 0 on 2026-08-01, was 2 earlier that day,
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

### Spine Ceiling — Breached Again And Closed By Deletion, 2026-08-03 (second pass)

`lib/` reached 47,568 against the freshly-ratcheted 47,530 ceiling (+38), so `rake audit`
and `bin/check --profile=full` were red on a clean tree. The whole +38 is one commit,
`44d8fc5d5`, and one file: `review/scan/rules/structural_question_rules.rb`, where
`CONFIG_HIERARCHY`'s duplicate-key check was rewritten onto Psych. That is a real bug fix
— the old check keyed on `"#{indent}:#{key}"` across the whole file and scored 8,166
findings tree-wide, every one of them false — so it is not a candidate for reverting.

Closed by deleting `lib/ground/cluster_registry.rb`, 109 lines with **zero callers**:
`ClusterRegistry` appears nowhere in `lib/ core/ bin/ test/ spec/ web/ tools/ data/ script/`,
the Rakefile or the gemspec, and is not named in `autoload.yml` or `load.yml`. Its only
mentions repo-wide were `START_HERE.md` prose and its own scan-log entries. Also dropped
the `require "set"` that the same commit orphaned when it deleted the `seen` set. `lib/` is
47,458, under the ceiling by 72.

**How it reached `main`:** `rake audit` could not have caught it. `task :selftest`
ended with `exit(summary.ok? ? 0 : 1)`, and `exit(0)` on success terminated the rake
process — so of the audit's seven prerequisites, only `constitution` and `selftest` ever
ran. `lint:frozen`, `lint:data_singularity`, `lint:spine`, `lint:autoload` and
`lint:principle_trace` were dead in the chain, and the audit's own `audit: passed` line had
never printed. It reported green by exiting before it measured, which is the same failure
`bin/gate`'s `INCONCLUSIVE` list exists to catch one layer up. Fixed by aborting on failure
instead of exiting on success; `:selfcheck` carried the identical bug and got the same fix.
Verified by forcing a spine breach: `rake selftest lint:spine` exited 0 before, exits 1 now.

Two things this leaves open. First, `lint:spine` counts comment lines and `[DENSITY]`
deliberately does not, so a commit that adds rationale prose above a tricky line satisfies
one rule and breaches the other — that tension is now three passes old and still unresolved.
Second, deleting `ClusterRegistry` orphaned `data/visual_clusters.yml` and
`data/mobile_web_opportunities.yml`, which have no other reader; `SelfTest`'s `clusters`
group is a scan exemption, not a loader. Delete both files or give them a consumer. They
were left in place rather than swept, because `START_HERE.md` records that folding them
needs a design decision, and so does removing them.

### Spine Ceiling — Closed 2026-08-03 By Deletion

`lib/` had reached 48,162 against a 47,660 ceiling (+502) with both raises spent.
Six files carried 656 lines that nothing referenced — no constant, no path, no
entry in `autoload.yml`, `load.yml`, the gemspec or the Rakefile:
`io/text_hygiene.rb`, `voice/visual_runtime.rb`, `pub4/status_report.rb`,
`ground/evidence_graph.rb`, `cli/orchestration/event_sequence_orchestrator.rb`,
`review/scan/unit_segmenter.rb`. Deleting them cleared the breach without
touching a threshold, and the ratchet cleared the raise log, so the allowance is
earned back rather than spent.

**`pub4/status_report.rb` was not an orphan, and deleting it broke `bin/pub4` for
six days.** Corrected 2026-08-09. `bin/pub4:12` requires it and `bin/pub4:48`
calls `Pub4::StatusReport`, so every subcommand died with a LoadError before
parsing argv — including the `bin/pub4 status` that the root `CLAUDE.md`
documents as the repo-level check and that `bin/todo-retire`'s own failure
message tells the operator to run. `bin/cli` execs `bin/pub4`, so it went with
it. Restored, plus one latent fix: the default argument called
`Environment.repo_root(__dir__)` positionally against a keyword parameter, which
never raised only because `bin/pub4` always passes `root:`.

The sweep was blind twice, and both are reproducible today:

1. **Extension filter.** It matched constants with a grep over `*.rb`, `*.yml`
   and `*.md`. `bin/pub4` has no extension. Re-run that grep now and it still
   returns zero callers for `StatusReport`, which plainly has one.
2. **Scope.** It ran from `MASTER/`, where `bin/` means `MASTER/bin/`. The caller
   is in the *repo root* `bin/`, one directory above the scan root, and puts
   `MASTER/lib` on the load path itself (`bin/pub4:9`).

Pinned by `test/test_entrypoint_requires.rb`, which checks requires rather than
constants: every `require` in an executable under the repo-root `bin/` or
`MASTER/bin/` must resolve to a file on disk. A constant sweep can be fooled by
an extension filter; a missing file cannot. Mutation-tested — remove
`status_report.rb` and it fails naming the script, the feature and the path.

**Any future orphan sweep must include the repo-root `bin/` and must not filter
by extension.** The five other deletions above were re-checked against both
blindnesses and all five hold.

Two things worth carrying forward. The reference sweep matched this file's own
warning below: the *first* orphan list, built from filename globs, was mostly
wrong; the one that held matched each file's innermost constant across
`lib/ core/ bin/ test/ spec/ web/ tools/ data/` — which, as above, is a scope
that silently excludes the one caller that mattered. And ratcheting mid-session
is a trap — recording the new low at 47,506 immediately blocked the +10 that
closing the `[DENSITY]` finding required. Ratchet once, at the end.

The historical accounting of who grew it, kept because the ratchet exists to make
this legible:

- ~98 lines from work already uncommitted in the tree before this pass — the
  `AstFixer` split (`ast_fixer.rb` −128, new `ast_fixer/syntax_transforms.rb` +162)
  plus `voice/engines.rb`, `voice/mix_metrics.rb` and `voice/tts_supervisor.rb`.
- ~75 from the 2026-08-01 debt pass (the inert-config wiring, the two narrowed scan
  rules, the four defects the new tests found). Roughly half of that was rationale
  comments, since trimmed to a sentence each with the full accounting moved into
  this file.

The rule that made this end in a deletion rather than a ceiling edit:
`data/spine.yml` sets `consecutive_raises_allowed: 2` and both entries were used
(2026-07-31, 2026-08-01), so raising was refused. Its own note says why — "if it
is raised again without `lib/` ever falling back, the honest conclusion is that
'the spine never grows' is not the invariant anyone is holding". Keep that
refusal: a raise is a decision with a sponsor, not a ceiling edit.

Worth recording alongside: `lint:spine` counts every line in `lib/**/*.rb`,
comments included, while `[DENSITY]` was deliberately changed on 2026-07-28 to count
*code* lines precisely so this codebase's convention of a rationale paragraph above
the tricky line is not penalised. The two rules therefore pull opposite ways on the
same edit. Whoever resolves the ceiling should decide which of them means it.

### Constitution Scan Debt

**agent-ignore** — `rake constitution` is broader than `rake selftest` and still reports thousands of self-scan findings. Do not chase zero. Track the count down by removing false positives and fixing high-signal violations.

### Autofix Wrote Broken JavaScript — Closed 2026-08-04, With What It Cost

**operator-priority context, no action left.** `AstFixer`'s `template_literals`
transform converted a `+`-chain that ends in a *call* by taking only the callee:

```js
-  text.slice(0, cut) + ' — *cough* — ' + text.slice(cut + 1)
+  text.slice(0, cut) + ` — *cough* — ${text.slice}`(cut + 1)
```

`CONCAT_PART` matches a dotted identifier path and stops at `(`, so the argument
list was left outside the new literal. The result is a template literal invoked
as a function — a `TypeError` on every execution of that line, and **valid
syntax**, so `node --check`, the parse gate and the commit's own "All parse"
claim were all satisfied.

Four instances shipped in `e7e48eed1`'s mechanical sweep, two in
`web/public/chat.js` and two in `web/public/face_speech_runtime.js`, on the
paralinguistic filler and timestamp paths of the live face.

How long it hid, and why, is the part worth keeping:

- `face_speech_runtime.js` feeds `face.runtime.js`, which had not been rebuilt
  since. Production served the pre-sweep runtime and looked fine.
- `chat.js` was caught only *indirectly*, by
  `test_public_asset_manifest_matches_source_files`, and only because the
  digested copy in `web/public/assets/` still held the good version. That test
  reports "generated asset drifted" — a staleness message. Running
  `assets:precompile` to clear it copies the broken source over the good asset
  and turns the alarm off without fixing anything, which is exactly what
  happened first.

Closed three ways: the four call sites restored to concatenation; the transform
now declines any chain followed by `(` (`web_transforms.rb`, with
`test_string_concat_declines_a_chain_that_ends_in_a_call` pinning both the
decline and the plain chain it must still convert); and
`test_public_js_has_no_template_literal_called_as_a_function` in
`test_web_ui.rb` fails on the shape directly, in the tree, rather than through a
drift message. A repo-wide sweep of `.js`/`.mjs`/`.ts` finds zero remaining, and
the detector was checked against the pre-fix blobs first — it reports 4 there.

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

`data/limits.yml` has 11 top-level keys and 94 second-level; **44 of the 94 have
no reader**, and the whole 29-key `guidance:` block is among them. The generic
accessor `workflow_rule(key)` still has exactly one occurrence — its own
definition. **Still open.** (Re-measured 2026-08-03; the earlier "28 of 39
top-level" counted a shape the file no longer has, so the fraction was right and
the denominator was not.)

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

Same shape as the kill list in the old `core/SEVERANCE.md` (now
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

**Doc drift** — closed 2026-08-01. `core/SEVERANCE.md` no longer exists (it is
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

## Scanner Convention — strip comments before matching source

Any check that greps source for a string must remove comments first. A rule and
the paragraph explaining the rule contain the same words, so a raw `include?` /
`refute_includes` over a file matches the prose about a thing exactly as readily
as the thing.

This is not a hypothetical. It fired **four independent times on 2026-08-10**,
across two agents working different parts of the same backlog:

- `brgen/test/services/deploy_backlog_test.rb` refused a partial for containing
  `popover` — the match was the comment recording why the popover was removed.
  The partial contains no popover.
- `RAILS/brgen/test/integration/front_page_weight_test.rb` counted three
  `data-controller="action"` in a partial that renders two, having read the
  comment that quotes the markup it replaced.
- The `nbsp_entity` rule flagged the comment explaining why an `&nbsp;` was
  removed.
- The pagy-helper rule flagged the comment naming the helpers it bans.

A fifth, one layer out: a CSS verification pass "confirmed" a rule had been
deleted from three compiled bundles when sass had simply preserved the `/* */`
comment naming it. Every assertion passed against comment text rather than CSS.

The fix is one line at the read site, and it differs per language:

```ruby
source.gsub(/<%#.*?%>/m, "")          # ERB
source.gsub(%r{/\*.*?\*/}m, "")       # CSS/SCSS block comments
source.lines.reject { |l| l.strip.start_with?("#") }.join   # Ruby, YAML
```

Two consequences worth keeping in mind. A check that passes may be reading
documentation, so prove a new source assertion can fail — plant the thing it
bans and watch it fire. And the failure mode is asymmetric: a `refute_includes`
that reads comments produces a *false alarm* the next author will "fix" by
deleting the explanation, which is how a codebase loses the reasons for its own
decisions.

## Scanner Convention — an exemption must outlive nothing

Sibling to the section above, found the same day and by the same kind of work.
When a gate carries an allow-list — exempt paths, baseline numbers, known
offenders — **the entries must be checked against reality, not just consulted.**
An exemption whose subject no longer exists is a hole in the gate that nobody can
see, precisely because the thing it excuses is invisible.

Deleting `RAILS/FINAL_TODO.md` on 2026-08-10 surfaced two, immediately, because
both tests named the file the moment it went: `doc_numbers` was still granting it
five dimension exemptions, and `doc_paths` was still excusing a generated schema
path on its behalf. Neither had had a subject for as long as it took to notice,
and nothing would have reported it — a baseline that exempts a file that does not
exist simply never fires.

(The numbers are deliberately not quoted here. Writing them out is what
`doc_numbers` exists to catch, and this section tripped it on its first run —
prose that prescribes a dimension without naming the token that owns it. The
remedy was to stop quoting them, not to add a baseline entry, which would have
been the very thing this section warns about.)

The failure is quiet in both directions. While the file existed the exemption was
load-bearing and correct; once it did not, the same line silently widened the
gate for every *other* file the rule covers, if the exemption is keyed on a value
rather than a path.

`rake lint:autoload` is the shape to copy: it does not merely read its 44 ignores,
it asserts each one is still necessary and fails naming any that is not. Any new
allow-list should be able to answer the same question about itself.

Cheap check when adding or reviewing one: every path in an allow-list should
resolve, and every numeric exemption should name the file it was granted for.
Note that "resolve" needs the right base directory — a probe that assumed repo
root reported 89 phantom stale entries in `data/autoload.yml`, whose paths are
relative to `MASTER/lib/`. Verify the instrument before believing the finding,
which is the other lesson of this week.

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
