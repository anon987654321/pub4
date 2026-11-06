# MASTER historical fix reviews

Preserved review records in chronological order. These are provenance, not
live task instructions; current authority and open work live in
`MASTER/AGENTS.md`, `MASTER/data/laws.yml`, `MASTER/data/law_runtime.yml`
and `TODO.md`.
Historical authority descriptions below reflect their dated review snapshots;
follow the live contract and configuration above when they differ.
Checklist markers in this preserved review were historical triage notation. The live, consolidated follow-up is in root `TODO.md`; this file is provenance, not a second task list.

## 2026-10-22 — Law authority, operational checks and /fix RAILS

Updated 2026-10-22. The source review began from main at 6214949c1f402d94e8d44e3e895d43eb8e3440be. Always re-read main before continuing; other sessions commit frequently.

## Decision and rationale

A Law and a check are related, but they are not the same kind of thing.

- soul.yml is the constitutional authority.
- laws.yml is the canonical declarative Law catalogue and execution policy.
- MASTER/law/*.rb contains executable constitutional Law definitions and their bad/good fixtures.
- MASTER/lib/review/scan/laws/*.rb and LawDSL provide executable source detectors. LawRegistryAudit is already the reconciliation instrument; its yaml_only, law_only, registry_only, and source_drift populations need to be read rather than hidden.
- MASTER/checks/checks.yml is the operational check-execution registry. It says which class or script runs, in what order, with what preconditions, and which composite covers a leaf. Operator::CheckChain supplies attribution, foreign-dirt handling, staged orchestration, and honest skipped outcomes.

The check registry must not be treated as a competing policy catalogue. A check measures or enforces a requirement; the requirement must remain traceable to the constitutional Law system where it is normative. Some checks measure environment capability or collect evidence rather than encode policy. Do not invent a Law ID for those measurements. Where a check enforces a real expectation and no existing Law explains it, record a coverage gap and propose an evidence-backed Law change through the proper authority process.

On 2026-10-22 gate was renamed to check throughout: Gate/GateChain/GateResult, file names, environment variables and the bin/operator gate alias, which is gone. This adds no second runner or second registry.

The glossary lives at MASTER/docs/synonyms.yml rather than MASTER/data/synonyms.yml because soul.yml marks data/ as a sacred path. No constitutional override was requested, so even adding a new file under that protected subtree would violate the current write boundary. The glossary has no runtime loader and cannot alter authority, IDs, severity, tiers, or machine outcomes.

Do not flatten skipped, inconclusive, and gap into one machine state. Skipped means the instrument did not run or did not measure its target; inconclusive means available evidence cannot settle the result; gap means a required instrument, input, or coverage item is absent. The preferred word in prose can be concise, but machine truth stays precise.

## Architecture simplification follow-through (2026-10-25)

The first Law-reader tranche is committed to `main`:

- `28a39324417f6a8f2562abdd17a7b17bb7592205`: `Fix::ConstitutionalCheck` reads priority Law IDs through `Master.law_entries`, removes the hard-coded fallback list, and blocks clean completion when the catalogue cannot be resolved. A regression test compares the IDs against the canonical reader.
- `68b6ea269c7e24a1ea770f75e43e69ec52303201`: `Fix::LawParity` uses the shared loaders for the catalogue and enforcement overlay and refuses an empty catalogue. A regression test covers the empty case.
- `83a3a9b26b2e9ec704ad6f641d08271fccc68a7b`: `Operator::Ratchets` reads the law-trace ceiling through `Master.law("law_map")`; the existing ratchet test compares it to the declared value.
- `b398fb45fb8112534cddd127ee28d690c06f556c`: `Master::Face::LawField.catalog` delegates to `Master.load_laws`, normalizes the root, and uses an inode/precise-mtime cache fingerprint. Its new test proves the shared loader is called for a custom root.
- `622c8b5`, `c43df95`, `5074f1c`, and `a2864fd`: move the operator's full catalogue declaration lookup into `Operator::LawInventory.catalogue_declaration`; `bin/operator laws` now uses `Master.load_laws` instead of a second YAML read and a local recursive parser. Tests cover the canonical `laws` section, other catalogue sections, key-derived IDs, and empty-catalogue refusal.
- `40b7253` and `d3d0fab`: the derived inventory's council personas also use `Master.load_yaml` rather than opening `council.yml` through an independent YAML call; a focused regression case checks the loader and persona shape.

These are source changes with regression tests added, **not verified test passes**. The Ruby commands have not been run in this session. Run the focused `test_constitutional_check.rb`, `test_law_parity.rb`, `test_ratchets.rb`, `test_face_law_field.rb`, and `test_law_inventory.rb` suites, then reader-singularity and law-trace checks, and record exact output before treating the tranche as verified.

The architecture target is intentionally conservative: one canonical Law catalogue; executable Law definitions and scanner detectors that trace back to it; one scanner/finding contract; one repository-repair coordinator; one transaction path; and one operational check registry/runner. `Core::Fold` and `/fix` are different workflows today. Before merging or deleting any of `FixLoop`, `RepairLoop`, `Kernel`, `Mission`, `RunJournal`, `RunLedger` or `Transaction`, trace their callers and prove rollback, restart, delivery-failure and evidence semantics through tests. Do not edit the sacred `data/` or `lib/review/scan/` paths without the required authorization.

One concrete Kernel boundary needs a measured decision: `MASTER/bin/master replay` exposes `Kernel.replay_cli`, while `test_fix_kernel.rb` directly exercises `Kernel#fix` and the small `Master::Fix::Laws::LAWS` list. The identifier `CAPABILITY_STATUS_MUST_BE_TRUTHFUL` appears both in `law/interface.rb` (currently scoped to `MASTER/lib/operator/services.rb`) and in the primitive kernel's observation-level check over changed files. Those scopes differ, so treat the kernel predicate as defense-in-depth until tests demonstrate a safe shared implementation. This source pass has not proved `Kernel#fix` unreachable across the repository; do not remove it based on the CLI entrypoint alone.

## Verified source facts as of this review

- soul.yml declares version 2.9.1 and includes data/ among the sacred paths. Do not edit it or laws.yml as part of a terminology cleanup.
- laws.yml identifies the canonical Law catalogue and broader execution policy. It should not get a parallel rules: subtree or a new hard/soft/ops schema for this work.
- core/constitution.rb already provides Master::Core::Constitution#admit as the admission point for proposed Effects. It is not the same thing as Operator::CheckChain, which orchestrates repository checks.
- LawRegistryAudit already reconciles executable law definitions and scanner registry entries, and reports source_drift. Use that report to guide any future registry cleanup.
- Amber's checked-in schema currently has version 2026_10_21_230200, which matches the latest migration 20261021230200_add_guest_account_merges_to_amber.rb. The earlier report of schema drift is stale on the reviewed main. Do not touch schema.rb by hand; if later check output shows genuine drift, use the app's migration and schema-dump workflow.
- RAILS/__shared/app/assets/stylesheets/_components.scss is already a short wrapper which imports base and six component partials. Its former 541-line size is stale; the old 541 debt entry has been removed from file_length_ratchet_test.rb. Do not repeat the split. Re-run the real CSS and file-length checks before splitting any other stylesheet.
- Current CSS source still has other historical ratchet rows. Names and old measured values are clues, not current check output; confirm current code-line counts and CSSConstitutionCheck findings before choosing the next file.
- The latest observed commit 6214949 contains a change intended to let the read-only pre-repair proof tolerate other sessions committing. This is not proof that a bounded /fix trial has completed or that repair quality is good.

## P0 — prove the current RAILS state and preserve trial integrity

- Identify whether a bounded /fix trial is still running, and record its pinned starting SHA, target tree, toolchain identity, Law digest, baseline output, repair output, and terminal state. Do not use a moving branch name as the only trial identity.
- Run MASTER/bin/operator check --scan-only --tree=RAILS on the actual checkout. Preserve the exact output for schema_migration, release, css_constitution, and rendered/visual status. Do not infer a green result from this handoff.
- Run the RAILS source checks and check suite on the same tree. If schema_migration is green, keep the schema untouched. If CSS is red, repair the reported files one at a time, re-measure, and compare the full check output before/after.
- Treat missing browser, closed app ports, missing baseline, and provider-unavailable results as INCONCLUSIVE or SKIPPED according to the existing result contract, never as a source failure and never as green proof.
- Read the actual rejection and ratchet records from the trial, if they exist: .master/rejections.jsonl, the run ledger, retained run logs, and the named proof envelope. Do not claim a file exists merely because an earlier handoff proposed it.

Rationale: C1 is the reported problem that main starts red, C2 is the reported long proof cycle, and C3 is the reported repair-quality risk. These claims came from a prior handoff and were not re-measured in this source-only review. The bounded trial and its evidence answer those questions; a narrative does not.

## P1 — prove write-path admission and transaction safety

- Trace every write, stage, and commit path from the actual call sites before writing tests: World Effect execution, Constitution#admit, Master::Io::Base, DiffStager, Committer, Fix::Transaction, rollback/recovery, direct File.write/IO.write and FileUtils mutation paths.
- Define the property before building the write-path audit. Core::Fold-proposed Effects must pass Master::Core::Constitution#admit before Master::Core::World performs them. Master::Io::Base, DiffStager, Fix::Transaction, Committer, and other /fix mutation sites are distinct write planes with their own guards and transaction responsibilities; they must not be assumed to be literal Core Effects.
- Instrument representative flows in each write plane and correlate every agent-originated write with the applicable admission/guard decision, normalized path, transactional owner, and outcome evidence. If a write bypasses its intended protection, fix that exact path. Only unify all planes behind Constitution#admit if source tracing proves that is the intended invariant and the shared API can preserve the distinct transaction and staging contracts.
- Add transaction end-to-end tests after inspecting the existing Transaction API. Cover atomic snapshot ownership, crash recovery, concurrent run serialization, rollback evidence/orphans, attempts to roll back after commit, and rollback on verification failure. Any assumed class or method signature in old notes is unverified until fetched from main.
- Prove semantic scan coverage: every applicable detector evaluates every target file in scope, and a Law change invalidates cached findings. Verify that FindingCache keys include all inputs a detector reads, including the Law/catalogue digest where needed.
- Implement or locate a trial-hygiene command that proves baseline and repair share the same source SHA or pinned worktree, laws digest, and toolchain identity. If an earlier artifact exists, inspect and repair it rather than creating a second command.
- Measure transaction snapshot bytes, elapsed time, and file count with a reproducible baseline. Do not add hand-entered cost estimates to checks.yml; use the existing ledger and measurements.
- Audit swallowed exceptions, including rescue nil, in load-bearing paths. Separate intentional nil-return contracts from true failure swallowing and make unhandled failure evidence visible.
- Prove a fresh clone can run the documented setup and canonical Minitest suite. Record actual wall time; the five-minute setup target is a measurement, not an assertion to fake.

Rationale: The central architectural property is one admission decision per Core Effect, not a simplistic replacement of all existing protection layers. Transaction, immutable-path, staging, I/O-tool and commit checks may have different jobs and operate on different APIs. The evidence must prove that each relevant write plane is governed and that the protections compose; it must not manufacture an architectural requirement that all internal writes literally call Constitution#admit.

## P1 — keep DesignSweep inside the transaction boundary

- Keep the standalone design command out of automatic /fix application until its write/apply phase is transaction-aware. The current standalone runner can commit each kept edit locally; a later check failure cannot undo those independent commits.
- Design a candidate/apply split: evaluate edits in an isolated candidate representation, validate the whole result, then apply through the existing Fix::Transaction and normal Committer only after admission and verification.
- Add failure tests showing rejected candidate, failed visual evidence, and failed final verification do not leave partial source changes or stray commits.
- Do not add a branch or worktree as a workaround. The repository contract says changes land on main; use a temporary disposable copy for any destructive experiment.

A later source pass fixed one narrower acceptance defect: `DesignLoop#keep` now checks the commit callback result. A definite refusal restores the original stylesheet and rebuilds CSS; it is returned as `:failed`, never `:kept`. A raised commit error is returned as `:delivery_failed` and leaves the candidate untouched for inspection because the commit outcome may be ambiguous. `test_a_refused_commit_restores_the_candidate_and_is_not_reported_as_kept` covers the definite-refusal path. This does not provide crash recovery or undo a local commit after a later full-run check.

Rationale: The visual sweep is useful, but its current commit semantics are not an atomic phase of /fix. Keeping it separate is more honest than saying the full lifecycle is transactional when it is not.

## P2 — consolidate the Law catalogue without inventing a second authority

- Run LawRegistryAudit and save yaml_only, law_only, registry_only, lexical_unwired, structural_unwired, semantic_only and dep_graph_gaps. Resolve each drift with an explanation backed by source and tests.
- Audit each check/check for whether it is a policy assertion, a factual measurement, an environment precondition, or a composite. Link policy assertions to real existing Law IDs when the mapping is accurate; record unmapped normative checks as coverage gaps instead of fabricating IDs.
- Define an enforced registry schema only after the audit shows which fields are necessary. Do not add parallel rule registries, a rules: subtree, or undocumented severity/tier values.
- Keep LawDSL positive and negative fixtures for every new detector. Run the fixture test, registry audit, law inventory, and autofix reach report whenever scanner registration changes.
- Inspect the real Law Definition contract before adding metadata. Proposed fields such as provenance, counter_law, rationale and last_reviewed are not proven requirements of the current schema; adding them must include migrations/schema validation, consumers, fixtures, and stale-data policy.
- If law review age matters, implement a report (for example, older than 90 days) only after there is a trusted, machine-readable review timestamp and a deterministic lint result.

Rationale: A detector ID, a constitutional Law ID, a check ID, and a test name can all be different identifiers because they answer different questions. The goal is traceable one-source policy, not false one-to-one identity or a global class/file rename.

## P2 — RAILS/CSS follow-through

- Confirm the component partial order and output with the existing CSS bundle and visual/source tests. The _components.scss wrapper currently includes base, forms, overlays, feedback, fields, progress_and_uploads, and content_controls in order.
- Use the real CSS check and current source line counts to select the next oversize candidate. Do not split _surface_chrome_endgame.scss or _minimal.scss from stale historical numbers alone.
- After each CSS split, compare all check output, keep cascade order, then lower/remove the exact ratchet entry. No line-count ceiling should be raised just to get green.
- Run the complete release composite after source blockers are resolved. Diagnose browser evidence separately from schema/CSS source defects.
- Centralize RailsApp detection only if a source trace confirms meaningful duplication among rails_app.rb, visual_pass, RailsProof and the RAILS/<app>/fix.yml profiles. Add tests before delegating callers.

## P2 — glossary, help, and contributor polish

- Add a glossary-only vocabulary file outside sacred data/, clarify Law/check/proof/result-state terms, and state that the execution registry has no policy authority.
- Make bin/operator check the one user-facing command for the ladder.
- Keep shell completion and its Minitest drift check in sync with both spellings.
- Add a Minitest contract that keeps checks.yml limited to execution metadata, preventing policy IDs/severity/tiers from silently growing into a parallel Law catalogue.
- Run rake docs:agent_contracts and rake lint:agent_contracts on a real checkout after synchronizing the generated agent files.
- Consider man pages for vocabulary and the write path only if they become the single source for command/help generation; avoid a second prose source.
- Derive CLI help from canonical command/docs once the existing registry supports it and test for drift rather than hand-maintaining another help list.
- Measure cold-start time before setting a 200 ms version-command ratchet. A target without a baseline is aspirational, not evidence.
- Keep commit subjects aligned with MASTER/data/commit_format.yml.

## P3 — test whether self-regeneration pays for itself

- Choose the smallest grain with a stable API and clear behavior (the prior proposal names ProseMetrics, which must be verified to exist and be suitable).
- Write a behavioral specification and independent oracle before deleting implementation. Run the deletion experiment only in a disposable copy outside the shared working tree.
- Measure regeneration tokens, wall time, human correction, and behavioral-evaluation pass rate. Compare regeneration cost to careful maintenance.
- Only generalize to neighboring grains if the smallest experiment succeeds or shows a measured positive return. A governed, non-regenerative MASTER remains a valid result if that is what the evidence supports.
- Treat whole-harness self-regeneration as long-range research, not a completion criterion for the current /fix repair.

## Verification commands to run on the real checkout

1. From the repository root: MASTER/bin/operator check --scan-only --tree=RAILS
2. From MASTER: rake lint:agent_contracts; rake test; the law fixture and registry audit tasks found in the current Rakefile.
3. From RAILS: run the focused file-length ratchet and CSS source-check tests using the app's documented bundle.
4. Run the bounded /fix trial with its SHA, Law digest, and toolchain identity recorded; capture its terminal report and rejection outcomes.
5. Re-run the checks after fixes, and report PASS, FAIL, INCONCLUSIVE, or SKIPPED with command output. Do not claim unexecuted validation.

## Guardrails

- Read soul.yml, then laws.yml, then executable laws and scanner laws before future MASTER policy changes.
- data/ and MASTER/lib/review/scan/ are sacred under soul.yml; do not modify these paths absent an approved constitutional override.
- Keep one Law authority, one registry of check execution, and one runner. No second rules registry.
- No mass Check-to-Check class/file rename in this pass.
- No runtime vocabulary loader, no fake Law IDs, no unvalidated hard/soft/ops tiers.
- Do not use Vercel or GitHub Actions as a substitute for local verification.
- Do not call the repair finished until the real tests, check outputs, and bounded trial provide evidence.

## 2026-10-26 — MASTER hardening follow-through

Updated: 2026-10-26 (Europe/Oslo; GitHub commit timestamps are UTC)  
Reviewed base: `1ef67fe10` (external review snapshot)  
Integration base: `0b59844318f2e5527b5d5d54328a44f433438c3c`  
P01–P11 integration head (historical; follow-on commits are recorded below): `73a45cc7a9800808fb7658e95dc3dceacf73bd67`

## Follow-on kernel audit-log append complexity (2026-10-26)

`Master::Fix::Kernel#append_event` no longer verifies the entire hash chain before every append. Each kernel instance validates the complete chain when it first needs a head and reuses the cached head while inode, size and timestamps remain unchanged. If another writer extends the file, it revalidates the **entire** chain before adopting the new head; it does not trust a cached prefix or only validate the appended suffix. An inode change or truncation fails closed. `verify_log!` and replay also retain complete-chain validation, including a final-newline check.

Regression tests cover cached-head reuse, a tampered cached prefix followed by an external append, refusal after truncation, and rejection of an incomplete final record. They are committed but unexecuted. No Ruby syntax check, focused suite, or full suite was run here; verification remains INCONCLUSIVE.

## Follow-on manual four-tree source pass (2026-10-25)

A manual source-only pass subsequently touched MASTER, the shared check runner used by RAILS, OPENBSD, and STUDIO. The work was committed directly to `main`; it was not an actual `/fix` execution. No app, suite, syntax check or live service was run in this environment.

- MASTER: `lib/boot/stale_bundle_sweep.rb` adds a 30-day, quarantine-timestamp-based cleanup for renamed stale Bundler stores. It is dry-run by default and is wired into `bin/cleanup`; `--apply` is required to remove eligible directories. Regression tests cover TTL age, dry-run, explicit pruning and symlink refusal.
- MASTER: the asynchronous builder self-test now uses `watched_thread`, and invalid check registry roots/headless rows are refused before the runner executes any checks. A static read found all 64 current rows in `MASTER/checks/checks.yml` have `class:` or `script:`; this census is source evidence, not a runtime pass.
- MASTER: LoopOwner preserves a live process claim when PID or timestamp metadata is malformed, logging the invalid metadata instead of deleting the claim. Tests added, not run.
- RAILS: the runner is shared; the invalid-registry guard is relevant to its declared checks. No Rails app, migration, HTTP or browser tests were run.
- OPENBSD: `vps-state` validates deploy-status PIDs through `Deploy::PidProbe`. Tests added, not run. No OpenBSD-specific execution, vm23 health check or deployment was attempted.
- STUDIO: Replicate schema audit/snapshot tasks without credentials now report inconclusive and exit 3. Tests added, not run; no provider call was attempted.

All related tests remain unexecuted. The one cross-tree backlog, `TODO.md`, records the precise verification commands and per-tree inconclusive states. Do not infer PASS from a commit, a test file, static census or a CI badge. The previously observed Vercel `build-rate-limit` status is not a Ruby test result and was not retried.

## Follow-on provider and deploy-status pass

A further code trace found two provider-health issues and one OpenBSD visibility issue:

- Provider quarantine now respects the latest append-only event, so `clear` actually releases a model even if quarantine and clear timestamps fall in the same second. Quarantine log caching keys on inode, size and mtime, so appends invalidate a cached view even when filesystem timestamp granularity is coarse.
- Provider canary outcomes now pass through `ModelRouter#record_provider_outcome` where available; this connects actual canary results to the existing health/quarantine path. Success and exception outcomes both enter telemetry, and `canary_failure` reduces health score. Focused tests cover clear, re-quarantine, stable-mtime append, success, provider exception, and router routing.
- The progress directory `/var/db/pub4/deploy_status` remains root-only. `pub4-admin deploy-status-read <app>` exposes one allowlisted, validated record, and `vps-state` uses it on vm23 rather than treating direct permission denial as no active deploy. Corrupt records are reported as corrupt. Tests cover the broker method, caller contract and damaged status data.

All newly added and modified tests remain unexecuted. No runtime PASS is claimed; the exact focused test list and per-tree INCONCLUSIVE state are recorded in root `TODO.md`. No deployment, Vercel retry, or OpenBSD host action was performed.

## Remaining telemetry retention boundaries

Local STUDIO `clips.jsonl` and per-subject billed-render `ledger.jsonl` remain open for an explicit archive/retention contract; they carry user-owned render and billing provenance and must not be silently truncated. `Trace::Ledger::Reflexion` now locks the 50-row read/retain/replace transaction and publishes the new file atomically; a concurrent regression case exists but is not run. The STUDIO clip index and billed-render ledger remain open for a deliberate archive/export retention contract.

## Follow-on provider state replay across rotation

Provider health and quarantine readers now merge the retained `.1` generation before the active log and invalidate caches on both file stamps. This preserves recent health scores and the latest quarantine/clear decision across a bounded rotation. Added two focused regression cases; neither has been executed. Events older than the retained generation remain outside the bounded retention contract.

## Follow-on conflict log writer hardening

The conflict log's existing three-generation retention is now wrapped in a sidecar flock across rotation and append. Each incoming line reserves capacity before the rotate, and the write remains private and complete-record based. Added a concurrent 200-record test and fixed the test's tail assertion to support short valid compacted records. Nothing has been executed; the proof status is still INCONCLUSIVE.

## Follow-on canonical event-stream locking

The canonical activity/evidence `Trace::Log::Event` writer now delegates to the shared private bounded JSONL appender, serializing rotation+append across processes. The helper retains one-shot disk-full recovery and also attempts a single reclaim when the legacy rotator returns without actually making enough room. Added an eight-thread / 200-event regression case that verifies complete, unique JSONL rows and private modes; it has not been run.

## Follow-on JSONL compaction integrity

The shared and standalone compactors now discard a partial leading line when a bounded byte tail begins mid-record. Regression tests parse active and rotated JSONL; the Swallow test checks a nonempty tail of complete records and confirms the lock sidecar survives pruning. The changes have not been runtime-tested.

## Follow-on Swallow log compaction

The standalone error logger now locks append+rotation, reserves space before append, compacts each rotated backup to a bounded tail, and retains only five bounded generations. Its pruning filter excludes the `.lock` sidecar so it cannot unlink the active lock inode. Added a rotation/retention regression test in `MASTER/test/test_swallow.rb`, not yet run.

## Follow-on shared JSONL retention pass

Added `Master::Trace::Log.append_jsonl` to own bounded private append, rotation, sidecar locking, symlink refusal, and per-record size caps. Reused it for provider health/quarantine, incident notes, Phoenix provenance, model metrics, OpenTelemetry trace output, and the tool-invocation audit. Existing smaller caps are preserved by passing them through. The OpenTelemetry exporter now opens the trace path per bounded append rather than retaining a descriptor that could bypass rotation.

Added shared-writer, exporter, metrics, incident and provenance tests; provider health tests also cover concurrency and retention. None have been run. The focused command inventory in root `TODO.md` includes the tests, but every runtime claim remains INCONCLUSIVE until the pinned Ruby and target-specific checks run.

## Follow-on telemetry append and broker privacy pass

- Provider health and quarantine share a private append primitive using a sidecar `flock`, complete-line writes, flush/fsync, and the existing 25 MiB trace-log ceiling. Rotation and append are serialized; oversized single events or failed rotation refuse the write. Added an 8-thread/200-event integrity test plus bounded-rotation and oversized-record tests; none have been run.
- The deploy-status read broker now requires status files to have no group/world permission bits. Added a regression case for mode 0644; it remains unexecuted.
- There is no live verification: no syntax or suite run, no OpenBSD service account check, and no deployment. The consolidated list and truthful status are in root `TODO.md`.

## Follow-on trajectory telemetry hardening

The opt-in trajectory writer now derives its 25 MiB ceiling from the existing trace-event log contract, serializes rotation and append through a private sidecar lock, reserves space for each complete record, rejects oversized records, enforces private file/directory modes, and refuses symlink destinations. This is important because the recorded task can contain the user's prompt. Added coverage for rotation, size limits, permissions and symlink refusal in `MASTER/test/test_ai_trajectory.rb`.

The new trajectory tests, like all other new tests in this continuation, remain unexecuted. See root `TODO.md` for the consolidated focused test sequence and the still-INCONCLUSIVE proof state. No full /fix run or live verification is claimed.

## State of the P01–P11 tranche

The patch tranche and follow-up corrections are committed directly to `main` in 15 commits, touching 24 files. The branch is 15 commits ahead of the integration base and zero behind it. This is direct-to-main integration, not a pull-request merge.

- **P01 — sacred paths:** the fail-closed implementation was already present on the integration base; it was retained rather than replayed.
- **P02 — secret veto:** covers write/note/exec/git effect inputs and refuses when the configured secret pattern is absent.
- **P03/P04 — monitors:** per-iteration watchdog and watcher recovery, including a follow-up protecting the watcher from a failed error-event publish.
- **P05 — stranded transaction:** transaction recovery is attempted before returning an expired-budget result.
- **P06 — provider quarantine wiring:** model outcomes are routed through the diagnostics/quarantine path.
- **P07 — web secrets:** config directories/files use private permissions, including existing config files.
- **P08 — TTS daemon probe:** accepts the daemon's versioned health response; the executable bit on `bin/tts-worker` was restored in a follow-up commit.
- **P09 — dependency boot:** subprocess capture and lock acquisition are bounded; gem-store destruction is replaced by a conservative stale-store rename; private bundle environment preserves frozen mode. Pipe draining was bounded in a follow-up.
- **P10 — law parity:** raises the audited priority ceiling and adds `tools/law_parity_check.rb` plus `rake lint:law_parity`. The `RENDERED_VALUES` gap is intentionally surfaced as a real gap; it must not be silenced without a detector or an authorized deferral.
- **P11 — constitutional self-test:** unreadable inputs and malformed YAML become findings; release manifest loading uses safe YAML.
- **Additional hardening:** parity loader errors are logged and re-raised, parity is not run twice by the lint entrypoint, and generic YAML duplicate census remains outside the constitutional self-test's stated boundary.

The review's exact snapshot and the integration base differed. Review line numbers and patch contexts must not be treated as proof of the current line layout; read current source and tests before extending a patch.

## Verification status — do not overstate

Regression tests were added or extended in these areas: constitution, dependency manager, fix convergence/run budget, law parity, provider-quarantine wiring, self-test, watcher, web server, and TTS worker contract.

**The Ruby suite, focused tests, syntax checks, and the requested live boot have not been run in this integration environment.** Source changes and tests existing in GitHub are not evidence that they pass. Do not mark this tranche verified until commands produce captured output on a compatible checkout/interpreter.

The latest combined commit status observed for `08c095f97cd3495269d6643bf3bc8918016bbf8d` shows the Vercel context failing with a `build-rate-limit` target. That signal is neither a Ruby test result nor proof of a code defect, and no Vercel rerun is requested here.

## Required next verification

1. On the dev Mac with the repository's supported Ruby, run focused tests for constitution, dependency manager, fix convergence/run budget, law parity, provider quarantine, self-test, watcher, web server, and TTS worker contract. Capture the actual exit status and output.
2. Run the repository's prescribed `bin/check --profile=agent` and the full `rake test` ladder when the supported toolchain and dependencies are available. Distinguish PASS, FAIL, INCONCLUSIVE, BLOCKED, and timeout; do not convert a toolchain or network failure into a pass.
3. Run `rake lint:law_parity`. An explicit `RENDERED_VALUES` gap is currently expected until an operator authorizes a sacred-overlay deferral or a tagged detector is implemented.
4. Test dependency-manager behavior using an offline/non-ABI failure and an ABI mismatch. Check the dev Mac boot log for the real `deps0` lines.
5. Verify the TTS worker's executable mode and health-probe behavior from two processes; check the socket inode as described in the review.
6. Run `test/test_stale_bundle_sweep.rb`; verify `bin/cleanup` lists eligible stale stores in dry-run mode and removes only stores older than 30 days with `--apply`.

## Outstanding review findings — reconciled against current main

The items below are the residual findings after the P01–P11 source changes and the 2026-11-05 reconciliation above. A source fix or authored test is not execution evidence; statuses remain NOT_RUN or INCONCLUSIVE until captured output exists.

- **Law/register truth — source state reconciled on 2026-11-05:** L4 now has stale-member and baseline-integrity detection in `lib/operator/self_findings.rb` with regression cases in `test/test_self_findings_drift.rb`; the persisted `SILENT_RESCUE` census is not refreshed or declared clean until the pinned Ruby 4.0.5 census/ratchet output is reviewed. L5 now detects direct positional prompt, heredoc, and `prompt:` call-site bypasses; Council ideation's proposer, critic, and synthesizer turns now use `InterModelContract`, with focused detector and exchange tests in `test/test_inter_model_contract.rb`. L7's `test_runtime_self_test_checks_match_laws_yml_contract` asserts exact declarative/runtime parity. L8's registry loader rejects rows without exactly one executable class/script, its regression tests cover headless rows, and the runner explicitly keeps errored checks non-successful; `CHECK_STRICT_INCONCLUSIVE` only controls inconclusive results. These source changes and tests are present, but all affected test execution remains NOT_RUN.
- **Resource bounds:** an age-bounded stale-store sweep is implemented in `lib/boot/stale_bundle_sweep.rb` and wired into `bin/cleanup`; it is dry-run by default, limits scope to expected `gems.stale-*` stores, skips symlinks, and requires 30 days of age. Its regression test remains NOT_RUN. The inter-model metrics ledger now uses the shared private `Trace::Log.append_jsonl` writer, with a 5 MiB cap, locked rotation, and a size-checked reader; privacy/retention assertions were added. Those tests are also NOT_RUN. The provider-health reader already scores only the last 900 seconds, reads at most 5 MiB and 20,000 records per retained generation, merges the active and `.1` generations, and includes success recovery; `test_provider_health_cache.rb` covers bounded reads, rotation, score recovery and cache invalidation. The Fix Kernel append-head cache already rejects inode changes/truncation and revalidates the full chain whenever another writer extends the ledger; `test_fix_kernel.rb` covers a tampered prefix followed by an external append. These are source-covered, not outstanding implementation gaps; their tests remain NOT_RUN. Still open: complete the census of any other append-only writers and run all retention/cache regressions on pinned Ruby.
- **Fix lifecycle:** R8 remains open for transaction/recovery-aware DesignRun candidate application and later-verification rollback; the definite commit-refusal reporting/restoration case is source-fixed and regression-covered, but not runtime-tested. R9 still needs truth checks for abort-on-stall, durable partial outcomes and skippable-stage deadlines. R10 still needs atomic undo-journal pruning and safe reference-aware reclamation. R11 still needs a load-bearing silent-rescue audit that preserves fatal exceptions.
- **Providers and I/O:** provider-health recovery and bounded recent history are already source-covered (tests NOT_RUN). The legacy `LLMDispatcher` Replicate chat poll now checks for a token, accepts only the exact HTTPS `api.replicate.com:443/v1/predictions/<id>` URL, sends auth only to that host, and applies an overall 240s deadline with 5s/10s open/read timeouts; no-network regressions cover those bounds (NOT_RUN). Do not close the wider Replicate item yet: `Io::ReplicateClient` pagination/download/token-file paths still need a separate origin, permission and timeout audit. Retry jitter, process-group probe termination, broader error redaction and Gemini key transport also remain to verify (R12/R13/H5).
- **Boot, device, and browser edges:** resolve the remaining R4 boot diagnostics and loop-claim recovery; pairing's claim race, unscoped process termination, pending-utterance TTL, wake-word timeout, bare device `system()` calls, and CDP handshake/nested-budget issues remain open (R4/R16/R17).
- **Security boundaries:** tool-hook fail-open behavior, MCP HTTP SSRF/package pinning, environment-file permissions, and scoped port/media kills remain open (H2/H3/H6/H7). The RAILS-side token timing, CSRF, and persistent ingress rate limiting remain **inconclusive**, because they were outside the review snapshot (H8).

The review roadmap remains the triage reference. Work on remaining items in small, path-scoped changes with a regression instrument for each. No item is closed by documentation alone, and no test is called green until its output exists.
