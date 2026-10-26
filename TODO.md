# pub4 outstanding work

## Architecture tournament quality gates and UX inventory coverage (2026-10-26)

The `/fix` architecture tournament now treats generating 30–40 ideas as necessary, not sufficient: candidate evidence must be among the source excerpts and hashes actually supplied to the model, test anchors must be in the supplied test inventory, and each plan must state concrete benefits, trade-offs, risks, verification and rollback. Local scoring now includes consequence analysis, candidate diversity considers both prose and target-path overlap, and a winner requires at least 30 structurally valid plans plus at least three plans clearing deterministic score/dimension floors. Path checks resolve symlinks and reject top-level tree symlinks. The 90-entry UX catalog validates the complete ordered ID sequence, allowed areas/proof types/tree ownership and keeps every row `acceptance_required`; its manifest exposes coverage counts by area, owner tree and evidence type.

Focused regression tests were added/updated for these contracts, but could not be executed in this environment: the GitHub API is reachable through the repository connector while a local `git ls-remote` fails because the runtime cannot resolve `github.com`. Validation remains **INCONCLUSIVE** until the following run in the checkout and pass: `ruby -Itest test/test_architecture_exploration.rb`, `ruby -Itest test/test_ux_refinement_catalog.rb`, and `ruby -Itest test/test_fix_protocol.rb` from `MASTER/`. No UX item is marked implemented merely because it is catalogued.


## Constitutional runtime consolidation (2026-10-26)

Implemented the first lifecycle-tracing slice on MASTER's interactive Fold path with a persistent event sink, even when no host event bus is supplied: CoreBridge injects before/after effect events; payloads omit raw effect arguments; a before-event persistence failure prevents the effect; an after-event persistence failure terminates as trace_failed without retrying or claiming completion. Regression contracts cover event order, redacted payloads and both publication-failure cases. The shared event bus now has a required-persistence path, backed by a strict append variant on the canonical event log; ordinary telemetry remains best-effort. The modified Minitest files were not executed here: GitHub could be read through the connector, but the execution environment could not resolve github.com to obtain the checkout. Validation is INCONCLUSIVE until the focused Fold and bridge tests run on the pinned toolchain.

Rollback now gets its own before/after audit pair, linked to the failed effect and checkpoint. CoreBridge installs a persistent event sink when no host bus is provided, and the standalone bin/master-core path shares the same Trace::EffectObserver adapter. A `trace_failed` mission is mapped to terminal `unknown_outcome` rather than generic failed or deferred for automatic continuation; `recovery_failed` remains reserved for unproven rollback/restoration. The legacy core:turn stream no longer persists raw read output, command output, paths, prompts or note text; it retains safe action labels, status and byte/line counts.

Still outstanding: privacy-audit other persisted event families such as tool payloads and Fix transaction events; unify the distinct Fold and repository-repair coordination paths; settle ownership among FixLoop, its inner repair loop, Fix::Kernel, RunJournal and Transaction from call-site evidence; standardize findings and check results; and propagate the same audited effect contract to every tool, background job and deployment path. Do not claim these broader migrations complete until the canonical suites run on the pinned toolchain. No law or sacred constitutional file was changed for this slice.


## Shared execution contract and cooperative cancellation (2026-10-26)

Source changes on `main` now add `Master::Execution::Contract` with validated effect envelopes, typed evidence references, normalized verification outcomes, and the shared terminal-state vocabulary. `Master::Proof` adapts its claim states into that vocabulary without copying raw evidence. The adapter distinguishes pass/fail from partial, inconclusive and errored outcomes; it does not yet replace every existing scanner, tree check, Fix scorecard or delivery result.

The interactive Fold path correlates before/after lifecycle events with run, mission and persisted attempt IDs and stores a SHA-256 digest of effect scope rather than raw paths, URLs or command arguments. A per-turn cancellation token now passes through the interactive session and TurnRouter into both CoreBridge/Fold and the canonical /fix pipeline via PipelineContext. FixLoop checks it before preflight, between expensive preflight phases, and before/after repair passes; an active bounded pass is allowed to finish and record its receipt/checkpoint, and persisted active-transaction recovery happens before a resumed run is stopped. Cancelled, unknown-outcome and recovery-failed repair missions are non-resumable and do not claim delivery. Cancellation does not forcibly interrupt an already-running model, check or external operation; non-interactive/background runs and other commands retain their existing lifecycle.

The shared verification adapter maps check, proof and deterministic finding results into typed pass/fail/partial/inconclusive/error/blocked/timeout/unavailable/not-applicable states; deterministic `Finding#to_verification` records a violation without copying raw diagnostic text. Master::Proof#to_verification, the /fix instrument preflight, and the MASTER check runner use it; the runner ledger stores the typed receipt beside legacy counts. The OPENBSD runner and broader call-site migration remain outstanding. Skill execution contracts validate semantic version, risk, capability and Law references, fixtures, provenance and status. Declared skills require a separate operator-owned ~/.master/skill_approvals.yml entry bound to the exact content SHA-256; symlinked or group/world-writable manifests are rejected, and changing skill content invalidates approval. Legacy skills remain compatible as unreviewed. Enhancement now evaluates only the original user message and appends eligible skill content afterward, so a no-change editor response cannot discard the skill and the editor cannot rewrite its body. The /skill list/inspect/approve/revoke operator command now exists and writes exact-revision approvals atomically to the operator-owned private manifest; however, fixture references are not executed by that command, complete source-specific skill promotion coverage remains open, and the regression suite is unexecuted.

Persisted diagnostic privacy now also covers provider-health JSONL, LLM outcome and provider-canary events, transaction telemetry, SQLite learning feedback, shared reflexion events, model-authored core reasons, and public tool subjects/errors. Those records store operational dimensions and digests/counts rather than raw provider errors, tool inputs/outputs or reflection details. Terminal dmesg redacts legacy raw diagnostic payloads, and model-missing/pre-response call failures now reduce provider health consistently. The local bounded reflexion remains a redacted repair hint. This is a privacy-hardening slice, not proof that every persisted event family is safe: the commit/Phoenix journal and other runtime event families still need dedicated field-level review.

Regression tests were added or updated for the contract envelope, check/proof adapters, /fix preflight, transaction telemetry, provider outcomes/canaries, dmesg, learning-ledger metadata, reflexion records, cancellation boundaries, inferred-route propagation, terminal mapping, skill manifest validation, revision pinning, and skill-injection behavior. They are committed but unexecuted: the source checkout could not be fetched in the current execution environment, so validation remains INCONCLUSIVE until the focused tests run under the pinned Ruby.

Still outstanding: adapt all scanners, checks, visual results and delivery receipts to the normalized verification contract; propagate the strict before/after audit contract to every tool, MCP/browser action, background worker and deployment path; carry operation identity and reconciliation semantics into all external effects; and prove idempotency/recovery under duplicate events, restart, stale leases and unknown outcomes. The repair coordinator, inner repair loop, Fix kernel, mission/journals and transaction ownership must still be reconciled from call sites and recovery tests. Isolated worktree-based parallel repair, provider failover integration proof, common health/recovery diagnostics, and complete source-specific skill promotion plus fixture-result verification remain open. Do not claim these migrations complete until the canonical suites execute and evidence is attached. No constitutional law or sacred path was changed for this slice.

## GLM law-adherence port (2026-10-26)

Source-only port of the safe, evidence-backed layout proposals is committed on `main`. The MASTER dashboard poller is now an external same-origin asset with a regression contract for no-store fetches, hidden-tab throttling and terminal 401/403 handling. The chat stop control, anonymous guest name, private share-draft copy, changelog and mailer branding now use locale-owned copy; legal pages no longer repeat heading labels as eyebrows. Vertical promo child classes are role-named consistently across markup, CSS and their existing contract test, and the trailing decorative arrow was removed.

The RAILS styles use existing `--leading-*` and easing tokens where their numeric values are unchanged; MASTER's standalone face uses its own declared leading tokens and named optical weight tokens preserve the same values. Those face-weight declarations live in maintained source and a custom `:root` block outside the generator-owned `generated-face-root`. The served `face.css` has now been rebuilt from the ordered source modules using the builder's generated-root marker; a source-to-bundle assembly check confirms exact byte-for-byte equality. Original music-button and selected-tab rendering was preserved rather than adopting unmeasured state changes. Brgen relies on the canonical shared `_animations.scss` reduced-motion reset forwarded by `_stack_brgen.scss`; no duplicate application-level `!important` reset is needed. Checkbox toggles retain a 44px outer hit target with the 26px track preserved, and dot-separated metadata was converted to independent elements with shared flex gaps. The dashboard endpoint now caps file previews at 16 KiB/eight lines and 400 bytes respectively, and returns a generic client error while logging diagnostic details server-side. Redundant eyebrows and a few non-semantic wrapper groupings were removed or replaced with appropriate elements; the renamed Amber mannequin caption now has role-based styling and a layout contract. Static regression contracts were added for the dashboard poller, bounded previews, line-scoped boot exceptions, face-token generator ownership, metadata, tap targets, localized share copy and mailer branding.

The law definitions and detector code were not changed. Where a source line is genuinely intentional, a reasoned `scan: intentional` marker is attached only to that line, using the scanner's existing one-line opt-out. No whole-view exclusion was added for the chat page. Also not ported: the proposed CSS-budget ceiling raises, unmeasured palette/shader/state-rendering changes, and lazy-loading hints on email artwork. The broad line-height substitutions were only accepted where the correct token source and affected selector were verified.

No Ruby/Rails test command, SCSS compilation, browser visual comparison, or live app boot was executed through the GitHub connector. Added/updated tests remain unrun; overall validation is **INCONCLUSIVE**, not PASS, until the focused contracts, full RAILS suite, CSS-budget measurement and `/fix` runtime verification execute on the pinned toolchain.

## Manual four-tree /fix simulation (2026-10-26)

**Verdict: INCONCLUSIVE — the real /fix loop and all four canonical suites remain unexecuted in this environment.** The exact remote tree was inventoried from GitHub; the pinned Ruby 4.0.5, zsh, local checkout, app boot, browser, OpenBSD host and provider credentials were unavailable here. A manual source review is not equivalent to /fix's required full execution trace, four assessment streams, two clean observations, or live evidence.

Source-level blockers and repairs identified during the simulation:
- MASTER wrapper preflight: fixed MASTER/bin/fix-here so a failed or malformed df -kP response reports unreadable disk rather than an incorrect low-disk diagnosis; added two regression cases. Tests remain unrun.
- STUDIO / scanner corpus: STUDIO/dilla/data/dilla.json is 11,829 lines and under 160 KB, but the generic 10,000-line cap made it a blocking corpus gap. Added a 20,000-line cap for JSON/YAML while retaining the 10 MiB byte ceiling, plus tests for the live Dilla catalogue and the cap boundary. Tests remain unrun.
- RAILS: verified its canonical isolated contract runner and required suite commands. No migration, application boot, rendered browser check or app suite was run; CSS/source changes still need compilation and rendered verification.
- OPENBSD: reviewed the check/deploy entrypoints, drift check and service-smoke boundaries. No OpenBSD-native suite, vm23 inspection, service restart, deploy or rollback was attempted. A commit message on the branch reports a prior OPENBSD run; this session did not execute or independently reproduce it.

Do not mark DONE or close the release proof obligations until the pinned toolchain runs the four canonical commands from the root README against the exact intended HEAD, the failures are repaired, generated outputs are synced, and rendered/live evidence is recorded. The current manual state is not a complete /fix result.
## Kernel audit-log append complexity (2026-10-26)

`Master::Fix::Kernel#append_event` now caches the last fully verified sequence/hash and byte offset per kernel instance. Subsequent appends reuse that head when the file identity and metadata are unchanged, or validate only the new suffix under the existing file lock when another instance has appended records. Truncation or inode replacement is refused. `verify_log!` and replay still validate the complete hash chain, including the final JSONL record boundary.

Added regression cases for cached-head reuse, suffix validation across kernel instances, truncation refusal, and incomplete final records in `MASTER/test/test_fix_kernel.rb`. These tests have not been run; source integration is not runtime verification. Keep the ledger/hardening status INCONCLUSIVE until the pinned Ruby focused suite passes.

Repository-wide audit baseline: code HEAD `3cd29c8389f7c777a4b7397c800c643bc0067426` on 2026-10-25. Targeted model-routing audit and repair: `a0dab52adc388f6e11699d672b2133842c3aa6f9`; unrelated later source commits have not been represented as covered by that targeted audit. Backlog reconciliation commits: `9dd60e3` and `9ab5958`. The baseline below is historical, not current HEAD.

Audit baseline: d9a008ba1f332a312122e342913486c54a32f18a. This is the one cross-tree backlog; do
not create separate project backlog files. A source edit, a static contract, an empty CI status
list, and a passing live run are different kinds of evidence. Close an item with the command or
browser evidence recorded in the commit.

## Remaining telemetry retention boundaries

The source scan also found local STUDIO `clips.jsonl` and per-subject billed-render `ledger.jsonl` writers. They are user-owned render/cost provenance, not merely diagnostic telemetry; do not truncate them automatically. Define an explicit archive/export contract, retention duration, and recovery proof before applying rotation. `Trace::Ledger::Reflexion` now serializes the 50-row read/retain/replace transaction with a private sidecar lock and atomic rename; a concurrent regression test was added but remains unrun. The STUDIO billing and clip indexes remain open until an explicit archive/export contract is agreed.

## Follow-on conflict log writer hardening (2026-10-26)

The /fix conflict log already retained three bounded generations, but its check-rotate-append sequence had no cross-process lock. It now serializes rotation and append with a private sidecar lock, writes complete JSONL records, enforces the cap including the incoming line, and keeps the existing three-generation policy. Added a concurrent 8-thread / 200-record regression case, and corrected the rotation test to inspect compacted tails without seeking past short valid records. These tests remain unrun.

## Follow-on canonical event-stream locking (2026-10-26)

`Master::Trace::Log::Event#append` now uses the common locked writer with the same 25 MiB cap, private file modes and complete-record rotation. The shared append helper retains the prior one-shot `ENOSPC` recovery behavior (discard a rotated generation or compact the active log before one retry), and now also attempts that one bounded reclaim if a failed rotation leaves the active file over its cap. Added a multi-thread event-stream test that checks all 200 JSONL rows, unique outcomes and private modes in `MASTER/test/test_trace_log_append_jsonl.rb`. The test remains unexecuted.

## Follow-on JSONL compaction integrity (2026-10-26)

The shared `Trace::Log.compact_rotated` and standalone Swallow compactor now drop a partial leading record when compacting a byte tail. This keeps retained backups parseable JSONL instead of making the first backup line a fragment. Tests for the shared writer, telemetry exporter and Swallow backup now parse both active and rotated files; Swallow's fixture uses actual newline-delimited records and asserts the retained tail is nonempty. These tests are not run.

## Follow-on Swallow log compaction (2026-10-26)

The standalone `Master::Ground::Swallow` logger now serializes append/rotation with a private sidecar lock, reserves room for the next complete record, and compacts a rotated backup to its newest bounded tail before retaining it. The backup retention filter explicitly excludes the sidecar lock so it cannot unlink a lock inode while another process waits. A generation cap keeps only the five newest bounded backups. Added regression coverage in `MASTER/test/test_swallow.rb`; it remains unexecuted.

## Follow-on provider state replay across rotation (2026-10-26)

Provider health scoring and quarantine-state lookup now replay the retained `.1` generation before the active log, in append order, and include both files in cache invalidation. This prevents the first bounded rotation from resetting provider scores or hiding a still-active quarantine/clear event. Added tests for a rotated failure followed by active success (score 0.78) and an active clear superseding a rotated quarantine; neither test has been run. State older than the retained generation remains outside the bounded history contract.

## Follow-on shared JSONL retention pass (2026-10-26)

Added `Master::Trace::Log.append_jsonl` as the common private, bounded append path. It serializes rotation+append with a sidecar `flock`, rejects symlinks and oversized single records, maintains restrictive modes, and refuses a write if rotation did not make enough room. The default cap reuses the existing trace-event 25 MiB limit; callers with an established smaller cap can supply it.

Migrated the canonical activity/evidence streams, provider health/quarantine, incident notes, Phoenix provenance, model metrics, OpenTelemetry trace output and tool-invocation audit to that common writer. The OpenTelemetry exporter no longer keeps one permanent open file descriptor that would bypass rotation. Tests added/updated: `MASTER/test/test_trace_log_append_jsonl.rb`, `MASTER/test/test_trace_telemetry.rb`, `MASTER/test/test_trace_metrics_log.rb`, `MASTER/test/test_cli_incident_log.rb`, `MASTER/test/test_phoenix.rb`, plus the provider health concurrency/retention suite. **None of these tests has been run.**

## Follow-on telemetry append and broker privacy pass (2026-10-26)

- MASTER provider health/quarantine now share a private append primitive that locks the log before seeking/writing, flushes and fsyncs a complete JSONL line, enforces file/directory permissions, and rotates both logs at the existing 25 MiB trace-event limit. Rotation and append are serialized through a private sidecar lock; an oversized single event or a failed rotation is refused rather than growing past the cap. Added an 8-thread/200-event regression test plus bounded-rotation and oversized-record cases in `MASTER/test/test_provider_health_cache.rb`; none has been run.
- OPENBSD's `deploy-status-read` broker now rejects progress records with group/world permissions, not just group/world write bits. Test coverage includes a readable-by-all status record. No real OpenBSD user/permission setup was exercised, and tests remain unexecuted.

## Follow-on trajectory telemetry hardening (2026-10-26)

The opt-in LLM trajectory writer previously appended indefinitely and used the process umask to choose file permissions. The records include the task/message and tool events, so an operator enabling `MASTER_LLM_RECORD=1` could accumulate an unbounded, readable-by-group log. `Master::AI::Trajectory::Record#append!` now uses the existing trace-event log byte ceiling (25 MiB), serializes rotation and append through a private sidecar lock, reserves room for each complete record before writing, rejects one record larger than the cap, enforces file mode 0600 and directory mode 0700, and refuses symlink destinations. Added rotation, cap, permission and symlink regression cases in `MASTER/test/test_ai_trajectory.rb`.

This is a source change plus regression coverage only. The suite and Ruby syntax checks remain **INCONCLUSIVE** because they have not been run. Add `MASTER/test/test_ai_trajectory.rb` to the focused proof run listed below. The 25 MiB maximum is shared from the existing trace-event log contract rather than introduced as a new independent policy number.

## Follow-on manual fix continuation (2026-10-26, Europe/Oslo)

Further source tracing found and repaired three state-observability defects after the first pass. These changes are committed to `main`, but none of their tests has been executed.

- MASTER provider quarantine: an explicit `clear` event previously remained ineffective because lookup filtered clear events before choosing the latest decision. Lookup now uses append order (the log's source of truth), and a clear works even when ISO timestamps share one second. Quarantine telemetry is cached by inode, size and precise mtime, so appended clear/re-arm events are visible without reparsing the entire log for every provider.
- MASTER provider canaries: thrown canary dispatch failures were displayed in the canary summary but did not reach health or quarantine; successful canaries also were not reflected in health. Outcomes now flow through `ModelRouter#record_provider_outcome` when present, allowing the production health/quarantine path to record them, with the direct health adapter retained for isolated clients. `ProviderHealth` recognizes `canary_failure` as a failure signal. Added/expanded `test_provider_canary.rb`, `test_provider_health_cache.rb`, and `test_provider_quarantine_wiring.rb`.
- OPENBSD deploy progress: `/var/db/pub4/deploy_status` stays root-only. `pub4-admin deploy-status-read <app>` is a fixed, allowlisted read verb that validates the path, owner and record shape; `vps-state` uses it on vm23 instead of silently hiding records it cannot read as `dev`. Malformed records now report a corrupt state. Added broker and `vps-state` regression cases and documented the read contract in `OPENBSD/README.md`.

Proof state remains **INCONCLUSIVE**: this pass did not run Ruby syntax checks or any focused suite. No production service, VM, remote deployment, or CI service was invoked. The provider quarantine/canary and broker tests must be run on the pinned Ruby/OpenBSD environments before relying on the fixes.

## 2026-10-25 manual four-tree /fix simulation

Manual source review and narrowly scoped source/test edits were committed directly to `main`. This was **not** an invocation of `MASTER/bin/master /fix`, `MASTER/bin/operator check`, or a real runtime suite. The working environment could not clone the repository, so all source reads and commits used GitHub file APIs; Ruby 4.0.5, the app bundles, local services and the OpenBSD host were not available for execution.

Changes added during the pass:

- MASTER: stale Bundler-store cleanup with a 30-day quarantine-age TTL, dry-run default, explicit `--apply`, expected directory shape and symlink checks; corrected the TTL to use the quarantine timestamp, not the old store mtime. Added `test_stale_bundle_sweep.rb`.
- MASTER: background boot self-test now uses the existing `watched_thread` publisher/logger instead of suppressing thread exceptions. Added `test_watched_thread.rb`.
- MASTER: invalid check registry roots and rows without `class:` or `script:` now fail before checks start. Static inspection of the current `MASTER/checks/checks.yml` found 64 rows and all 64 have an executable declaration; the new guard's tests are not run. Added `test_check_registry_schema.rb`.
- MASTER: `LoopOwner.cleanup_stale!` no longer deletes its claim after a malformed PID or timestamp; the issue is logged as load-bearing. Added corrupt-metadata cases to `test_ops_loop_owner.rb`.
- RAILS/shared check runner: same parse-time registry protection as above; static row census only, no RAILS app suite, browser, migration or live HTTP checks were run.
- OPENBSD: `vps-state` delegates PID validation to `Deploy::PidProbe`, rejecting non-positive/non-decimal PIDs before probing. Added `OPENBSD/test/test_pid_probe.rb`. No OpenBSD-host tests, vm23 checks or deploy were run.
- STUDIO: `replicate:schema_audit` and `replicate:schema_snapshot` now exit 3 with an explicit inconclusive message when no Replicate token is configured, instead of looking successful without measuring anything. Added `STUDIO/test/replicate_schema_task_test.rb`. No STUDIO suite or live schema lookup was run.
- Documentation: root `CLAUDE.md` again identifies root `TODO.md` as the single cross-tree backlog; details and proof obligations stay here.

### Proof state

- **Source committed:** yes, visible on `main`.
- **Regression tests added:** yes, but none of the new tests were run in this environment.
- **Syntax checks / MASTER focused suite / MASTER full suite:** INCONCLUSIVE (not run).
- **RAILS contract and app suites / database migration / browser scenarios:** INCONCLUSIVE (not run).
- **OPENBSD suite / remote vm23 service health / deploy / rollback:** INCONCLUSIVE (not run; no deployment was attempted).
- **STUDIO check / tool suites / real Replicate schema call:** INCONCLUSIVE (not run; no token/network-backed call was attempted).
- **Law parity:** the known `RENDERED_VALUES` coverage gap remains an explicit gap until an authorized deferral or tagged detector lands; it is not cleared by this pass.
- **External status:** previously observed Vercel `build-rate-limit` failure is not a Ruby result. No Vercel retry was made.

Next proof commands on the dev Mac with the pinned Ruby 4.0.5: run the focused tests (`MASTER/test/test_stale_bundle_sweep.rb`, `MASTER/test/test_watched_thread.rb`, `MASTER/test/test_check_registry_schema.rb`, `MASTER/test/test_ops_loop_owner.rb`, `MASTER/test/test_provider_quarantine_wiring.rb`, `MASTER/test/test_provider_canary.rb`, `MASTER/test/test_provider_health_cache.rb`, `MASTER/test/test_trace_log_append_jsonl.rb`, `MASTER/test/test_trace_telemetry.rb`, `MASTER/test/test_trace_metrics_log.rb`, `MASTER/test/test_cli_incident_log.rb`, `MASTER/test/test_phoenix.rb`, `MASTER/test/test_swallow.rb`, `MASTER/test/test_reflexion_ledger.rb`, `MASTER/test/test_conflict_resolver_log_rotation.rb`, `MASTER/test/test_ai_trajectory.rb`, `OPENBSD/test/test_pid_probe.rb`, `OPENBSD/test/test_vps_state.rb`, `OPENBSD/test/test_pub4_admin.rb`, and `STUDIO/test/replicate_schema_task_test.rb`), then `cd MASTER && bin/check --profile=agent`, the full MASTER suite, RAILS contract/app suites, `ruby OPENBSD/test/run_all.rb`, and `cd STUDIO && rake check test`. Capture actual output and distinguish PASS / FAIL / INCONCLUSIVE / BLOCKED / TIMEOUT. Do not run a production deploy as part of a simulated pass.

## 2026-10-25 source-fix reconciliation

The direct-to-main repair batch reached source commit 4a7618ea5d86c2e637402b8b60ff19afbb19ea4e before this backlog update; commit 22df7a7173ff74eae89a172e6f8850e91728377e then added progress reporting and incomplete-suite evidence to the parallel test supervisor. These are source and regression-test changes, **not** a passing test run. The operator-provided terminal output predates many of them; its failure summaries must be rechecked against current main rather than copied forward as current results.

Repairs committed in this batch include:

- Restored valid MASTER/data/laws.yml syntax after the boot-blocking malformed default_disabled_scopes sequence. The current body count is 2,009 non-blank/non-comment lines against the existing 2,050 body-line budget; the 2,174/2,171 raw-line measurements in old output are not the metric used by the ratchet.
- Restored MASTER's canonical Ruby pin to 4.0.5 and fixed same-version inline ruby -e re-exec, which previously attempted to load a nonexistent MASTER/-e file.
- Added a bounded phrase-energy signal, generation-checked native TTS recovery, and current digest checks for the generated face loader; repaired split-source voice assertions and the orbital-field fixture.
- Bounded subprocess waits across output-reader threads and process groups; kept configured Ollama lanes eligible when live model discovery is inconclusive; fixed denial-round constraint placement, JSON namespace-report exit status, and inter-model fixture responses.
- Restored the /pair command route/help/completion, corrected browser hostname normalization, and made critical event-log warnings emit once to stderr.
- Made PWA, CSS coverage, asset URL, layout-stability, locale-reader, and keyboard/gesture inventories follow RAILS/__shared and the extracted sibling engines rather than the retired shared/ and brgen/engines/* layouts.
- Corrected architecture and test contracts that pointed at removed component layouts, old locale owners, old CSS aggregation files, stale voice bundle assumptions, or the wrong Stimulus boot module. Lowered the measured Rails opacity baseline from 27 to 22 rather than masking the improvement with a larger ceiling.
- Added an Amber account-erasure entry and regression fixture for user-linked dating location pings, and guarded a marketplace-order table rebuild with a copied-row-count check and a local migration-safety rationale.
- Added regression coverage for the parallel test supervisor's timeout, progress reporting, and incomplete-worker evidence. Commit 22df7a7 adds the suite report/progress plumbing, but its new tests and the real serial/parallel suite remain unexecuted.

### Required verification for this batch

- [ ] Run the focused tests affected by these changes on the exact current commit, including the MASTER boot/YAML/law-order, subprocess-timeout, model-pool, voice, /pair, and event-log tests, and the RAILS locale, erasure, CSS/asset/layout/gesture, PWA, campaign, migration-safety and face contracts. Record each command and its actual output.
- [ ] Re-run the MASTER suite serially and then in the configured parallel mode; check for incomplete workers, missing Minitest summaries, timeouts, or mismatched test-start/result counts.
- [ ] Re-run the full RAILS contract suite and each active app suite. Investigate the expanded CSS-corpus counts and any new findings individually; do not raise existing baselines or ratchets merely to obtain green.
- [ ] Rebuild generated outputs where the source-of-truth contract requires it, then prove their digests are current. Specifically verify generated RAILS/__shared/design_tokens.yml and the RAILS/master/public/face.runtime.js manifest against their sources.
- [ ] Finish the bounded four-tree release pass and real browser/viewport evidence already listed below. No test suite, rendered validation, deploy, or merge is marked PASS by this source reconciliation.

## P0 — evidence before calling the system complete

- [ ] Run a fresh bounded release pass against the exact commit intended for deployment:
  constitutional and repository checks, all RAILS contract tests, active app suites, OPENBSD
  tests, and STUDIO fast tests. Record PASS, FAIL, INCONCLUSIVE, BLOCKED, or TIMEOUT separately.
  GitHub previously reported a failed Vercel status whose target points to a build-rate-limit condition. That status does not prove the new evidence helper or runbooks pass; no full local release run has been performed on the current checkout. Do not use Vercel or a status badge as a substitute for running the documented checks on the exact checkout.
- [ ] Complete the requested 200–400 scenario interaction matrix across MASTER CLI, MASTER web,
  keyboard/touch, session state, routes, errors, models/tools, speech, reconnects, offline mode,
  and PWA updates. Use the existing `RAILS/test/interaction_campaign_400.json` as the canonical
  400-case inventory: validate its declared 20 surfaces × 20 cases, action/fault setup, expected
  outcomes and evidence paths; do not create a second matrix. Run cases against real CLI, browser
  and HTTP surfaces where applicable. A static parse confirms 20 surfaces and 400 unique action
  records in the current manifest, but this is inventory evidence only. Record scenario ID, setup,
  action, observed result and evidence; scripted mocks and the presence of this file do not
  constitute runtime passes.
- [ ] Run the live rendered-layout suite with screenshots and geometry evidence at 320, 360,
  375, 390, 430, 480, 640, 768, 1024, and 1280 CSS-pixel widths. Include keyboard-only use,
  zoom/reflow, safe-area, forced-colors, and reduced-motion checks. Do not report visual
  completion from source inspection alone.
- [ ] Run MASTER/bin/operator triangle up before relying on rendered checks, then run the
  repository check runner. Inspect every INCONCLUSIVE or BLOCKED result rather than counting it
  as success.
- [ ] Prove deploy and recovery on the intended OpenBSD host. Check the deployed commit, service
  health, logs, backups, and a restore path. Keep deployment separate from local-source test
  evidence.
- [ ] Run `ruby OPENBSD/test/test_evidence_tool.rb` from the exact checkout and smoke-test PASS,
  FAIL, BLOCKED, INCONCLUSIVE, and TIMEOUT outcomes, including process-group termination and
  attachment hashes. An isolated temporary-Git-repository exercise of the draft helper passed
  9 runs / 35 assertions; the committed test has not been executed from this checkout, so this is
  not yet a checkout-level pass. Inspect emitted JSON and text logs before committing artifacts.

## MASTER CLI, web, voice, and shared session

- [ ] Run `cd MASTER && ruby -Itest test/test_keyless_routing.rb` on the exact pushed code commit. The model-router patch makes the shared reachability check honor `Io::LaneQuota` and keeps manually excluded Codex out of the live pool even when login reports success. Regression coverage is committed but this test was not executed during the audit.
- [ ] Run `cd MASTER && ruby -Itest test/test_owner_preferences.rb` and the relevant agent/command-registry tests on the exact current commit; then smoke-test two repeated correction turns through CLI and web, verify the pending suggestion is surfaced, and prove acceptance is owner-only. Source and regression cases are committed, but runtime execution is not yet evidenced. Acceptance must also prove that an accepted preference changes the intended prompt, model-routing, CLI/web or face behavior without overriding `soul.yml`/`laws.yml`; a saved preference alone is not adaptive behavior.
- [ ] Finish the Ghostty-inspired web-console pass with rendered visual review. The canonical
  palette now separates graphite shell surfaces, muted violet focus, neutral text, and the
  sparse lime semantic signal; the face renderer remains the focal point. Source-level mobile
  rules are in place, but final spacing, face/prompt coexistence, dashboard density, contrast
  measurements, and desktop/mobile screenshots remain unverified.
- [ ] Verify the installed PWA end to end: install, launch, safe-area and keyboard-open layout,
  a useful offline surface, stale-asset recovery, service-worker update and failed-request recovery.
  Confirm the shared manifest stays host-aware and only intended stable resources are cached.
  The update must not auto-reload mid-typing; expose a deliberate update/reload path and preserve
  the draft/session. Queue offline sends only where a supported queue actually exists.
- [ ] Validate parity across CLI and browser for conversation/session state and the requested
  /connect, /join, and /msg channel flows. Check destination, reconnect, history, interruption,
  and error behavior; do not assume parity from shared naming. The browser must visibly distinguish
  connected/reconnecting/offline, and each outgoing message must expose confirmed pending/sent/
  delivered/failed states. Verify reload preserves history, scroll and unsent draft, and double
  Enter/network retry cannot duplicate a send.
- [ ] Run the full /fix phase loop per tree and demonstrate truthful DONE, PLATEAU,
  HUMAN_DECISION, BLOCKED, VALIDATION_FAILED, DELIVERY_FAILED, and TIMEOUT states. Verify
  dirty-tree preservation, interrupted writes, disk exhaustion, retry convergence, and
  rollback/undo behavior. On 2026-10-22 three bounded MASTER trials each stopped on a /fix
  defect before any repair, and each is now fixed with tests: a spent run journal was resumed
  instead of replaced, the read-only baseline was voided by any other session committing (it now
  brackets working bytes, so commits pass and edits still block), the ratchet stage measured
  every RAILS ceiling for a MASTER target, and the known-red record named failed steps rather
  than tests, so a narrow proof could not tell old red from new. Rails targets are now
  recognised from their files. The parallel test runner now polls worker exit status, applies a
  configurable 1,800-second per-worker deadline (`MASTER_TEST_WORKER_TIMEOUT`), terminates a
  timed-out worker process group, reports the offending PID/log and includes the final worker
  log in its report; relay-thread exceptions are surfaced, and a worker without a final Minitest
  summary, matching verbose result count, and matching test-start count cannot pass with exit 0.
  The normal `rake test` task uses this supervisor for both one-worker diagnostics and parallel
  runs. Worker logs record the active test (`test-start0`) so a timeout or abrupt exit identifies
  the last test entered. The 2026-10-25 diagnostic follow-up adds a run-time configurable
  completed-result progress cadence (`MASTER_TEST_PROGRESS_EVERY`), a JSON worker outcome report at
  `.master/check/suite-report.json`, last-entered-test markers for incomplete workers, and rejects
  exit-zero runs whose Minitest summary or verbose result lines report failures/errors. The progress
  counter means completed result lines relayed, not tests started or total suite completion. These
  source changes are not yet runtime-verified: run
  `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test` to isolate
  a serial hang, inspect the report/logs, then `MASTER_TEST_JOBS=3 rake test`, and record exact
  test/output before closing.
  No trial has reached a repair, so repair
  quality remains unmeasured on both MASTER and RAILS. Run /fix again only when the operator asks.
- [ ] Validate the OpenBSD Operator CLI and /help against the requested plain dmesg style,
  correct checkout/tree-relative location, no decorative status, and useful scrollback. Re-check
  that ASCII art never appears outside the face.
- [ ] Complete real voice-path checks: English uses Christopher; Norwegian uses Pernille/Finn and
  Malay uses Yasmin/Osman according to the declared voice policy. Verify single-voice playback,
  no overlap, natural turn timing, interruption/barge-in, microphone permission denial, STT/TTS
  timeout and declared fallbacks. Measure latency on the target machine rather than relying on a
  mocked worker.
- [ ] Capture real-browser face boot/render evidence: first-tap behavior, failed asset recovery, context loss, lifecycle cleanup, reduced motion, renderer budget, phone thermal/battery behavior, and GPU/device performance claims. Include the requested grayscale palette, original single CLI prompt when the face is exposed, micro-/nano-expressions, duration-based lip-sync against actual TTS playback, and face/prompt coexistence. Inspect the generated runtime bundle, not only its split source parts.
- [ ] Measure input acknowledgement, time-to-first-token, completed reply and greeting independently. Proposed targets for review are input acknowledgement <=100 ms, first token <=2 s, greeting <=3 s and --help/--version/--status <=200 ms. Establish the current baseline first, test CLI and web separately, and enforce only a measured ratchet; a target is not a result.
- [ ] Verify CLI cancellation and terminal restoration on Ctrl-C during generation, Ctrl-D, SIGTERM, child-process timeout and exceptions. Preserve partial output as specified, terminate owned child processes, and restore raw mode, bracketed paste and alternate-screen state. Test resize/scrollback, long-output history/search, NO_COLOR, TERM=dumb and non-TTY piping; suppress the face in dumb/non-interactive terminals.
- [ ] Verify browser cancel/stop, socket loss, reconnect and offline-mid-reply outcomes with visible status. Ensure each state label corresponds to the actual server/runtime state, the mobile prompt remains above keyboard/safe area, drafts are not resent on reload, and reduced-motion/forced-colors retain usable status and focus.
- [ ] Review the existing `CAPABILITY_STATUS_MUST_BE_TRUTHFUL` Law and surface detectors against the invariant that UI progress, success, pending and delivery state must match observed system state. Reuse an existing Law if it already covers the behavior; if it does not, propose the narrowest canonical Law/enforcement change with positive and negative fixtures. Do not create a parallel policy registry or edit sacred Law paths without the required authority process.

## MASTER personal assistance

- [ ] Complete one real read-only non-Google-Calendar calendar or email workflow end to end.
  Start with a narrowly scoped adapter, subject-bound permission, inspectable local state,
  current-data freshness, explicit failure states, and regression tests. Do not claim a live
  provider integration from a parser or fixture alone.
- [ ] Add one operator-selected external messaging channel through the existing MASTER runtime
  and shared session contract; Telegram is not a target. Prove identity isolation, permission
  checks immediately before effects, reconnects, attachment limits, delivery receipts, and safe
  handling of untrusted inbound instructions before adding further channels.
- [ ] Evaluate real advice quality against realistic personal-assistance scenarios for practical
  usefulness, factuality, calibration, safety and actionable next steps. Static contract
  fixtures are not evidence of model behavior; label mocked, model-backed and human-reviewed
  results separately.
- [ ] New-user trial of `bin/master` in a PTY, 2026-10-22 (16 turns: life, relationship,
  medical, sexual, workplace, philosophical and religious questions, then weather, flights,
  news, an email, a reminder and a repo search). The medical answer was right and short
  (legevakt 116 117, 113 for rest pain). Fixed since, each with a test: prose starting with an
  installed command ran as shell (`what`, `find`, `write`; 2608de39b); the operator's Claude
  Code Stop hook fired inside MASTER's claude lane and every reply opened "I did not run
  vps-deploy" (dc749128b); /clear sat 104s in council review and was vetoed (5a05b202a); "should
  I quit my job to make music" started dilla, which crashed on the fallback kit's missing `open`
  voice (71a3a97ff and 7ad060f92); a BINARY web result raised "incompatible character encodings"
  on every lane and opened every circuit (c1e3cef26); "what can you do" described only the
  repository (59e067d1f). Still open, unmeasured since the fixes:
  - Rerun 2026-10-23 on f507369b4: every answer was direct and useful, the capability answer
    covers a person's needs, and the reminder was kept as a task with an honest "nothing will
    ring". It found one more: "write an email asking him to fix the broken heater" started /fix
    in write mode (fixed in 6806b6fdc; its blank-line edits were restored). Still slow: boot
    17.6s, the greeting at 26.7s, each reply 13–16s end to end. Make replies stream their first
    words.
  - Reproduce the latency on the current HEAD with a monotonic timeline for boot, first visible token, completed reply, model/provider, retries and fallback hops. Test CLI and web separately. Confirm that streaming begins on the first usable provider chunk and that a failed stream emits a truthful error before switching lanes; do not claim a latency win from mocks or source inspection.
  - "does god exist? give me your actual view" ran two web searches (the second appending
    "official documentation") for a question that asks for a view, not evidence. Weather then
    said web tools were unavailable, and no answer cited a source. Define and test the lookup policy:
    separate opinion/advice from factual/current-information requests, request approval only where
    the declared policy requires it, and never run unrelated searches. If a requested lookup is
    unavailable, say so plainly instead of presenting an uncited answer as researched.
  - "remind me tomorrow at 9" is kept as a task, but nothing alerts at the time; an alert needs
    a real delivery channel (the face, push or the operator's messaging channel above). Implement
    scheduling/delivery and retry evidence, resolve relative times in the user's declared timezone,
    and disclose at acceptance time whether anything will actually alert. A stored task alone is
    not a delivered reminder.
  - Pre-existing reds found on the way: `test/test_media_intent.rb` went green in d8efe79db
    (each failure was a real misreading of postpro requests) and
    `test/test_ground_standing_orders.rb` in 40fd09ff7 (stale fakes), the two prompt tests in
    ffb4552ea, and `test/test_dialogue_rubric.rb`, which could not load, in 84d09daa1 and
    20028b7e5 ("what should I do next?" after a manipulation account kept no support protocol),
    and `test/test_self_test.rb` in abc31c68a (rename fallout).

## RAILS 8+ and mobile-first PWA products

- [ ] Run an independent /fix and bin/ci pass for every active app in RAILS/apps.yml, plus
  RAILS/test/run_all.rb. Shared-engine changes must be verified in each consumer app and in the
  deploy copy-tree layout.
- [ ] Run `ruby RAILS/test/contract_runner_contract_test.rb` and then the full `ruby RAILS/test/run_all.rb`
  on the current checkout. The contract runner now rejects a missing Minitest summary, zero-run output, and
  a failure summary paired with exit status zero; committed source and regression tests are not a test pass.
- [x] Brgen's account-erasure suite ran on 2026-10-22: `test/jobs/user_purge_job_test.rb` 16
  runs, 223 assertions, green after 0866cf75b let the job destroy message metadata under strict
  loading (it raised on Vote#votable and rolled the erasure back) and classified
  activity_events, reactions, votes, outbound_clicks and conversation_participants as destroyed.
  Full brgen suite at a6fa4ac29: 1,432 runs, 0 failures, 0 errors.
- [x] Amber's suite ran on 2026-10-23 with its identity and merge migrations in the test schema:
  355 runs, 0 failures (47fe43c83), `test/jobs/user_purge_job_test.rb` 3 runs, 78 assertions.
  Getting there fixed two real faults: no account had a profile or privacy settings (a block
  passed to strict_loading! never ran), and erasure rolled back on a strict-loading refusal. The
  recurring 03:50 schedule is still unobserved on vm23, and amber's CI there died after 25 tests
  on dc749128b while the box was out of swap; rerun it.
- [ ] Verify the shared OAuth callback end to end in Brgen and Amber after the Amber
  federated-identity migration runs: provider-subject reuse (including BankID without email and
  legacy placeholder recovery), account cleanup, email-verification boundaries, and real
  configured Google/Facebook/Vipps/BankID callbacks. The 2026-10-25 source pass adds
  provider-row uniqueness recovery, recovery of eligible unverified non-guest non-BankID synthetic
  placeholders, merge-pair model validation with Brgen/Amber regression tests, and user/IP-scoped
  Amber AI rate limiting. These commits are source changes, not runtime evidence. The tracked Amber schema is already at
  version `2026_10_21_230200`, matching the latest migration; verify migration application on a fresh
  test database, run both app suites, and exercise real configured provider callbacks before closing this item.
- [ ] Execute the shared guest-to-account conversion tests in Brgen and Amber after Amber's
  `account_merges` and federated-identity migrations run. Verify anonymous post presentation
  survives, both sender and recipient sides of Amber's MASTER chat move to the registered
  account, Brgen conversation participants merge without colliding on unique conversation/user
  pairs, message receipts deduplicate while preserving earliest delivery/read evidence, typing
  indicators are cleared, trust signals deduplicate, and a failed merge leaves guest history
  untouched. Confirm old guest-session IDs are destroyed rather than promoted into authenticated
  sessions and the source guest row is anonymized with unusable credentials while retained only
  as the account-merge audit referent. Add a real-browser continuity check: the same posts,
  conversations and trust signals must remain visible without a flash that looks like lost history
  or an unexplained reload. Amber's tracked schema is already at version
  `2026_10_21_230200`; verify that a fresh test database applies these migrations. Source and regression
  tests are committed but runtime proof remains open.
- [ ] Run the guest-transfer failure and retry tests through password sign-in, magic-link
  sign-in, OAuth, and both signup controllers. The shared flow now checks for a committed audit
  record before rotating sessions, keeps the anonymous session active when transfer fails, and
  logs a retryable failure; confirm cookies, email verification, and already-created accounts
  behave correctly after migrations and app suites run.
- [x] The BankID legacy-account recovery guard is measured in both apps: brgen at a6fa4ac29,
  amber at 47fe43c83 (`test/controllers/bankid_identity_persistence_test.rb`, 9 runs). Recovery
  needs the synthetic `uid@bankid.oauth` address, no verification token and a returned
  `urn:bankid:bid;LOA=4`; a lower ACR is refused, and a BankID member without email can post as
  themselves.
- [ ] Brgen: finish and simulate the end-to-end hyperlocal social and marketplace journeys
  across feed, posts/comments, identity/moderation, discovery/maps, marketplace listings,
  dating, messenger, radio, and takeaway. Cover authorization boundaries, empty/error states,
  tenant/city resolution, upload limits, and mobile one-handed use.
- [ ] Verify Brgen's PWA share-target private-draft lifecycle before calling the journey complete.
  The source now stages incoming images/video in owner- and city-scoped `ShareDraft` rows, exposes a
  review-and-publish action that reuses email verification, community authorization and `PostModeration`,
  transfers media only on explicit publish, and has an hourly expiry cleanup job. Regression coverage
  was added for staging without a public post, image/video handling, explicit publication, unverified
  accounts, foreign-city communities, cross-member access and expiry. These source/tests are not yet
  runtime-verified: run Brgen's `test/integration/share_target_test.rb`, `test/jobs/share_draft_cleanup_job_test.rb`,
  `test/jobs/job_concurrency_test.rb`, fresh migration/schema loading, and the full app suite on the
  current checkout before closing this item.
- [ ] Brgen revenue readiness: verify the intended listing/offer/payment or monetization path,
  entitlements, moderation and abuse handling, privacy/terms, accounting/audit trail, and
  production configuration. Do not call it revenue-ready until the real configured path works
  end to end.
- [ ] Amber: run full outfit-combination and garment-scoring scenarios with real catalogue/media
  data. Verify diversity, garment identity/colour fidelity, user preference handling,
  provider/media limits, retries, caching, and any actual purchase or affiliate path.
- [ ] bsdports: complete a real package-index refresh and port lifecycle test. Verify signed
  archive manifests, DNS/public-HTTPS pinning, bounded response bodies, preserved metadata and
  dependency edges, CVE relationships, disk-space fallback, rollback safety, and OpenBSD package
  installation on a supported host.
- [ ] Audit all Rails mobile journeys at narrow widths, including keyboard-open layouts, focus
  visibility, 44px preferred primary targets, safe-area insets, 320px reflow, offline/read
  freshness, and install/update behavior. Keep product dialects distinct rather than flattening
  them into one palette.
- [ ] Re-measure generated CSS/JS and PWA budgets from a fresh source-to-build pass. Compare
  budgets to tracked ratchets; never raise ceilings to make a regression look green.

## OPENBSD deployment and operations

- [ ] Exercise the full deploy/canary/rollback sequence against a test target and then the
  intended host, including detached-commit behavior. Confirm deploy never leaves the production
  worktree attached to an unintended branch.
- [ ] Verify backup integrity and a real restore drill, scheduled jobs, health/uptime
  monitoring, certificate renewal, service restart permissions, bounded logs, and actionable
  alarms. A local fixture is not proof the remote host is healthy.
- [ ] Run relevant OPENBSD tests on OpenBSD itself for ksh/zsh, package signatures, service
  paths, permissions, pledge/privilege separation, and deployment scripts; label host-specific
  checks unmeasured when no OpenBSD host is available.

## STUDIO and Dilla

- [ ] 2026-10-25 source-only mix pass: the showcase now has a separate restrained `dilla_bed` rig and a two-layer support arrangement; regression expectations and engine notes were updated. This is not closed until the focused Dilla tests pass and the rendered WAV is auditioned against the previous take for punch, low-end weight, clarity, and groove.

- [ ] Finish Dilla defragmentation only where one musical decision truly shares an owner. Keep
  dilla.rb as the thin public shell and one authoritative engine for theory, progressions,
  arrangement, drum feel, effects, mix, and master; avoid one-use wrapper files.
- [ ] Prove the default 92 BPM pocket and target sound in generated audio, not just parameter
  tests: 2–3-bar minor progressions, varied swing/dillatime, believable kick/snare/hat
  programming, saturation/tape/dub effects without muddying the drums, and restrained lead
  tones. Avoid overwriting an existing take; keep deterministic seeds reproducible.
- [ ] Render and inspect the requested dilla.wav and dilla.mp4 outputs, including the live path,
  postpro/three.js output, audio-analysis report, and failure cleanup. Compare against
  operator-supplied J Dilla reference tracks and document which musical characteristics are
  measured versus subjective.
- [ ] `STUDIO/test/dilla_test.rb` recorded 7 failures on 2026-10-23 (25 min run). A
  source/test follow-up was committed on 2026-10-24: the README reference heading, six-cent
  `prophet_pad` detune, tracked-tree expectation, eight-section 92 BPM showcase, five Rhodes
  layers, and guitar stereo group were reconciled. **Not rerun**; do not count these as closed
  until the fast suite and full suite run. The prior render-overwrite and bar-drift findings are
  still unverified. Decide each from fresh output before the `dilla.wav` overhaul.
- [ ] Run STUDIO fast tests and at least one full render on the target machine. Record audio
  peaks/loudness, clipping, duration, BPM, file integrity, and visual output; do not infer
  quality from a successful process exit.


## /fix transaction safety and Law coverage

- [ ] Trace the write planes from real call sites: proposed Core::Fold Effects must pass
  `Master::Core::Constitution#admit` before `Master::Core::World` performs them; `Io::Base`,
  DiffStager, `Fix::Transaction`, Committer and direct filesystem mutation are distinct planes
  with their own guards and transaction contracts. Prove each plane is governed; do not assume
  every internal write is literally a Core Effect or replace protections before tracing them.
- [ ] Instrument representative writes with the applicable admission decision, normalized path,
  transactional owner and outcome. Add end-to-end recovery tests for atomic snapshot ownership,
  crash recovery, concurrent run serialization, orphan/rollback evidence, refusal to roll back
  after commit, and rollback when final verification fails. Inspect the actual Transaction API
  before writing the tests.
- [ ] Keep DesignSweep out of automatic `/fix` application until it has a candidate/apply split:
  evaluate an isolated candidate, validate the whole result, then apply through the existing
  `Fix::Transaction` and Committer after admission and verification. Prove rejected candidates,
  failed visual evidence and failed final verification leave no partial changes or stray commits.
  Use a disposable copy for destructive experiments; do not introduce a branch/worktree workaround.
- [ ] Prove semantic-scan coverage over every target file and that finding-cache keys include all
  detector inputs, including the Law/catalogue digest where relevant. Run positive and negative
  LawDSL fixtures when scanner registration changes.
- [ ] Run `LawRegistryAudit` and record `yaml_only`, `law_only`, `registry_only`,
  `lexical_unwired`, `structural_unwired`, `semantic_only`, `dep_graph_gaps` and
  `source_drift`. Explain each drift with source and tests; distinguish normative Laws from
  factual measurements, environment preconditions and composite checks. Never fabricate Law IDs
  or add a second policy registry.
- [ ] Prove baseline and repair evidence refer to the same pinned source SHA, Law digest and
  toolchain. Inspect/reuse an existing trial-hygiene instrument before adding one. Measure
  transaction snapshot bytes, elapsed time and file count; audit `rescue nil`/swallowed
  exceptions in load-bearing paths; prove fresh-clone setup and canonical tests on a real checkout.
- [ ] Recheck the shared RAILS CSS import order and the current CSS/file-length check output before
  selecting any next stylesheet split. Preserve cascade order, compare all outcomes, and change
  only the exact measured ratchet. Consolidate RailsApp detection only if a source trace proves
  meaningful duplication among `rails_app.rb`, visual pass, RailsProof and app fix profiles.

## Cross-tree security, RubyLLM, and efficiency

- [ ] Finish the security review across MASTER, RAILS, OPENBSD, and STUDIO: outbound HTTP/SSRF,
  DNS pinning, body/time limits, authentication/authorization, rate limiting, CSP/CORS, upload
  paths, secret redaction, unsafe command construction, and safe failure states. Source-level
  hardening on 2026-10-25 keys Amber AI limits by user/IP and makes Brgen's generated avatar
  responses independent of account existence. Shared CSP nonce initializers exist, but real
  response headers/enforcement and targeted `html_safe` data-flow review remain unverified.
  Re-test the actual production boundary; do not close this item from source inspection alone.
- [ ] Verify model-pool selection and fallback on the exact current HEAD with Ollama unavailable or quota-dead, each actually configured provider, and at least one healthy fallback. Exercise `test_route_policy.rb`, `test_lane_selection.rb`, `test_fix_fresh_checkout_models.rb`, `test_compute_pool.rb`, `test_fallback_chain.rb`, and `test_lane_pool.rb`; record exact output on MASTER's pinned Ruby. Isolated policy checks were run in a scratch harness on system Ruby 3.3.8 against byte-identical `RoutePolicy` and `OutcomePolicy` source: 12 route-policy behavior tests / 35 assertions and 9 outcome-policy tests / 46 assertions passed. The route-policy harness intentionally omitted the router module-owner integration case and used a minimal result/test-helper shim; these counts are not a run of the repository's native test files. The integrated route suite has not run in this session. The available execution environment has no mounted checkout, no `zsh` or `bundle` executable, lacks required gems including `sqlite3` and `ruby_llm`, and cannot resolve `github.com` for a clone. It has Ruby 3.3.8 while `.ruby-version` pins 4.0.5. Therefore native suites and live provider probes remain unmeasured here—not passed or failed. Check stale saved-model pins, unreachable local/cloud lanes, and single-provider failure with at least one live fallback. Keep this item open until the full targeted suite passes on MASTER's pinned Ruby.
- [ ] Benchmark RubyLLM routing/provider gains using representative workloads: latency, success
  rate, token/context use, cost, retries, circuit breakers, and fallback quality. Keep
  measurements per provider/model and distinguish observed values from estimates.
- [ ] Re-run the DRY/KISS and duplication census across the current tree. Review duplicate
  decisions, one-use abstractions, generated files, single-child directories, stale
  pointers/docs, and concepts that should have one authoritative owner. Preserve public
  paths/contracts and compare structural ratchets before and after changes.
  Initial Law-reader tranche landed on 2026-10-25: commits
  28a39324417f6a8f2562abdd17a7b17bb7592205 (canonical constitutional-priority reader),
  68b6ea269c7e24a1ea770f75e43e69ec52303201 (shared LawParity loaders and empty-catalogue
  refusal), 83a3a9b26b2e9ec704ad6f641d08271fccc68a7b (canonical law-trace ceiling reader),
  and `b398fb45fb8112534cddd127ee28d690c06f556c` (face Law field uses the shared Law loader).
  The follow-on `622c8b5` / `c43df95` / `5074f1c` / `a2864fd` changes move operator Law
  declaration lookup into `Operator::LawInventory.catalogue_declaration`, remove the duplicate
  recursive parser and direct YAML read from `bin/operator`, and add cases for canonical/nested
  catalogue sections, key-derived IDs and empty-catalogue refusal. Follow-up commits `40b7253`
  and `d3d0fab` route LawInventory council personas through `Master.load_yaml` and test that
  loader contract. These are source changes, not verified test passes. The canonical architecture docs and agent contract were updated to distinguish
  policy authority from detector registration, describe the current Fold-versus-/fix boundary,
  and keep registry and repair-loop consolidation open. The generated root agent files were
  reconstructed from the exact generator template; still run
  `cd MASTER && rake docs:agent_contracts && rake lint:agent_contracts` on a real checkout.
  Run the focused constitutional-check, LawParity, ratchet, face-law-field and law-inventory tests,
  reader-singularity/law-trace checks, and then a bounded suite before closing any part of this
  work. The full LawRegistryAudit reconciliation and FixLoop/RepairLoop/Kernel ownership analysis
  remain open, including the primitive `Master::Fix::Laws::LAWS` scope map and proof of any
  `Kernel#fix` reachability claim. The repair loop's terminalization, lifecycle and pass execution
  are now separate collaborators, and the model route policy is pure; still run
  `test_fix_terminal_vocabulary.rb`, `test_fix_protocol.rb`, `test_execution_trace.rb`,
  `test_reliability_kernel.rb`, `test_fix_convergence.rb` and the integrated route suites on
  MASTER's pinned Ruby. Do not infer completion from these source changes or fixtures alone.
  Also reconcile the historical /fix `--dry-run` zero-proposal failure report with current
  behavior; do not infer it is fixed without a current regression run.
- [ ] Re-run the four-tree performance sweep with before/after evidence: boot, CLI response, web
  first paint and interaction latency, JS/CSS payloads, memory/CPU, background work, and Dilla
  render time. Avoid claims based only on source size or unrepresentative local machines.
- [ ] Reconcile older conversation requests against executable source/tests before closing them.
  The current scoped GitHub API check returned no open issues or pull requests; older issue
  numbers surfaced in broad search results but are not confirmed open. Prior chat commitments
  still outstanding include the larger DRY/KISS census, Dilla/Postpro and Brgen SCSS source
  consolidation, the complete DeepSeek/Master findings audit, and fresh bounded tests across all
  four trees. Reconcile each distinct finding from the available DeepSeek handoff/chat material
  against current source, regression tests and commit evidence; classify it as verified, changed
  but unverified, superseded, open or blocked, and deduplicate it against the items above. Do not
  treat a summary of older chat logs as a substitute for locating and checking the underlying
  finding. Keep unresolved commitments represented here until proven complete.

## Closure rule

Evidence procedures and the code/evidence split are indexed in `docs/todo-triage.md` and `docs/runbooks/`; these documents do not create another backlog or close items themselves.

An item is closed only when the owning command or interaction ran on the current commit, the
result is recorded, and any generated artifact is in sync with its source. For rendered/UI work,
include before/after screenshots, viewport, device/runtime, and relevant console/network errors.
If a tool or host was unavailable, record that state explicitly instead of guessing.


## Architecture tournament and 90-point interaction acceptance (2026-10-26)

Added a read-only architecture tournament to requested /fix runs on the repository root
or an exact top-level tree. The default is 36 architectural candidates per eligible tree,
bounded to 30–40; a repository-root run gives MASTER, RAILS, OPENBSD and STUDIO separate
candidate sets. One structured generation request is used per tree. Candidates must be
source-grounded, use valid in-tree paths, describe verification and rollback, and survive
near-duplicate rejection. A deterministic local score compares source evidence, test
anchors, verification, rollback, scope and Law alignment. Model-provided scores are ignored.
The winner and a five-plan shortlist guide repair; they do not authorize broad rewrites or
replace ordinary Law and verification gates. Candidate tests remain NOT_RUN until the
repository's actual suites run.

Added MASTER/data/ux_refinements.yml with all 90 UI, UX, CLI, REPL, terminal, browser
recovery and visual/accessibility contracts. Each row names owner trees and expected proof
types and remains acceptance_required. The catalogue is validated, fingerprinted into the
/fix protocol report and scoped into the relevant repair context. No item is claimed passing
from source review alone.

Validation status: INCONCLUSIVE until the added focused tests, protocol tests, full MASTER
suite and top-level /fix execution run on the pinned toolchain. The GitHub source connector
does not provide a checked-out repo/runtime for this session. No GitHub Actions workflow was added.

## /fix plan generations and Law × stream × surface runtime proof (2026-10-26)

The requested /fix path now pins an immutable FixPlan after the durable run journal and
inside the measured run budget. The plan records eligible-file SHA-256 values, scope and
exclusion digests, governing soul/laws files, executable Law sources, runtime/toolchain
identity, adapter inventory, and a plan digest. The existing RunJournal binds plan
generations; changes to source, scope, Law, authority, toolchain, exclusions, or adapters
invalidate prior convergence checkpoints. Terminal receipts include plan and assessment
matrix provenance.

The runtime assessment ledger is built from the canonical executable Law population plus
scanner-only identities, not the LawBridge/Semantic wrapper adapters. It records the four
independent violation/opportunity streams across the canonical surface vocabulary. Scan
receipts are tied to the pinned plan generation; drift, unscanned inputs, semantic gaps,
missing AST receipts, malformed structured data, failed adapters, and unsupported surfaces
remain INCONCLUSIVE. The aggregate opportunity heuristic does not yet publish per-surface
negative evidence, so an empty opportunity result cannot satisfy a clean cell. /fix DONE is
withheld unless the current-generation matrix is complete and clean.

Validation for this handoff: source/API review and static source assertions only. Native
tests and live four-tree /fix were NOT_RUN in this chat (per request); do not claim the
new behavior is test-green. Remaining implementation gaps include general rendered-UI
and interactive-behavior evidence outside the current Rails visual adapter, complete
cross-file and media/compiled-asset assessors, test/runtime/deployment probes, and a
per-surface clean-receipt contract for opportunity assessment. A full matrix that exposes
these missing assessors will correctly finish BLOCKED rather than report DONE.

## Architecture tournament evidence (2026-10-26)

- [ ] Run `MASTER/test/test_architecture_exploration.rb` on the pinned repository toolchain; this environment only reviewed the source and did not execute Ruby tests.
- [ ] Exercise requested `/fix` against the repository root and verify four independent reports (MASTER, RAILS, OPENBSD, STUDIO), each with 30–40 materially distinct candidates, grounded evidence, a local scorecard, qualified alternatives, and explicit NOT_RUN execution proof until actual verification runs.
- [ ] Inspect the new tournament decision fields in emitted run events and confirm their persistence across process interruption; source-level integration is not durability proof.
- [ ] Keep all 90 UI/UX micro-refinements canonical in `MASTER/data/ux_refinements.yml`; they remain acceptance contracts, not blanket styling instructions or completed implementation claims.


## Effect replay safety (2026-10-26)

The shared `Master::Execution::Contract::EffectEnvelope` now records explicit reversibility (`reversible`, `compensatable`, `irreversible`, `unknown`), defaults to `unknown`, rejects invalid classifications, and exposes `replay_requires_reconciliation?` for irreversible/unknown effects. This prevents the contract from implying that an idempotency key alone proves exactly-once behavior. A regression test covers the default, invalid values and irreversible replay. The declaration is intentionally not presented as complete runtime enforcement: the strict Fold lifecycle observer now accepts and persists the reversibility classification on both before/after receipts, defaulting to unknown. Inventory and classify actual effect handlers, propagate classification from callers, and add reconciliation tests before claiming replay safety across every tool/background/deployment path. Validation remains INCONCLUSIVE until the focused contract suite runs on Ruby 4.0.5.
