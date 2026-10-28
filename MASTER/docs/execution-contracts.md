# Execution contracts and architectural consolidation

**Status date:** 26 October 2026  
**Scope:** MASTER runtime and its integration boundaries. Vercel is deliberately out of scope.

This document describes what the current code has established and what remains to be migrated. A type or adapter existing in source is not evidence that every runtime path uses it, and a test being committed is not evidence that it passed.

## Implemented source changes

### Shared execution and evidence vocabulary

`MASTER/lib/execution/contract.rb` now owns a small set of validated, typed shapes:

- `EffectEnvelope` represents an effect's identity, verb, capability, operation, parent/checkpoint/run/attempt/mission IDs, optional idempotency key and deadline. Its optional scope is stored as a SHA-256 digest. Raw arguments and scope are not part of the envelope. It also records reversibility as `reversible`, `compensatable`, `irreversible` or `unknown`; the conservative default is `unknown`. Irreversible and unknown effects expose `replay_requires_reconciliation?` so retry policy cannot infer exactly-once behavior from an idempotency key alone. This is a typed declaration, not proof that every runtime caller has classified its effects correctly.
- `EvidenceReference` identifies evidence by ID, kind, status, verifier and optional digest. It carries a reference, not the underlying private content.
- `VerificationResult` adapts existing check results, `Master::Proof`, and deterministic scanner findings into a stable outcome vocabulary. `Finding#to_verification` converts a measured violation to a failed receipt and links it by a stable finding key instead of copying the diagnostic text. A check that ran but skipped declared coverage remains partial; an unavailable check remains inconclusive; a check error is not promoted into conclusive verification. The adapter uses duck typing and does not make MASTER import the sibling-tree `Deploy::CheckResult` implementation.
- The canonical repair terminal-state vocabulary now comes from this execution contract through `Master::Fix::OutcomePolicy`.

This is deliberately an adapter layer, not a second law registry or a replacement for `Master::Proof`, `Deploy::CheckResult`, or the repair loop's own state machine.

### Skill declaration and promotion gate

`Master::Execution::Contract::SkillContract` now validates an optional `execution_contract` declaration on a registry or Antigravity skill. It records a content-addressed revision, semantic version, risk classification, required capabilities, referenced Law IDs, fixture paths and provenance. The contract metadata does not grant those capabilities; every real tool operation remains subject to constitutional admission.

Legacy skills without a declaration retain the prior activation behavior as `unreviewed` for compatibility. A declared skill is not injected merely because its own YAML says `candidate` or `approved`. A valid declaration must also have an operator-owned approval entry in `~/.master/skill_approvals.yml` matching both the exact name and SHA-256 revision. Editing the body, triggers, metadata or included skill files changes the revision and invalidates the approval. Blocked, deprecated and malformed declarations remain inactive. The approval file must be a regular, non-symlink file that is not group/world-writable; malformed manifests fail closed for declared skills.

The approval manifest has this shape:

```yaml
schema_version: 1
approvals:
  - name: release-skill
    revision: "<exact SHA-256 revision reported by the operator inventory>"
    approved_by: "<operator identity>"
    approved_at: "2026-10-26T12:00:00Z"
```

The library exposes `contract_for(name)` and a compact `contract_inventory` containing status, revision, promotion readiness, operator-approval state and trigger eligibility. They omit the skill body and credentials. The local `/skill` command now exposes `list`/`review`, `inspect NAME`, `approve NAME FULL_SHA256 --confirm`, and `revoke NAME FULL_SHA256 --confirm`. It refuses visitors, requires an exact current revision for approval, and persists through the operator-owned manifest with a private lock and atomic mode-`0600` writes. Malformed or unsafe manifests are not overwritten. Approval records who approved the revision and when. This is a local terminal command, not a browser approval surface.

Approval verifies that the declared candidate has required metadata; it does not execute the referenced fixtures or certify that they passed. The fixture references remain claims until a separate verifier produces evidence. Complete source-specific coverage of every learned or dynamically loaded skill path is still outstanding.

### Persisted telemetry privacy

A privacy-hardening slice now applies the shared diagnostic representation to additional persisted event families:

- Provider-health JSONL records store error digests and byte lengths, not raw provider exception text. Missing-model and pre-response dispatch failures are also counted as health failures, consistent with the router's exclusion behavior.
- Provider outcome, provider-canary and health-recorder-failure bus events publish digest/length metadata instead of upstream error strings. The terminal dmesg adapter also refuses to print raw diagnostic text if it receives a legacy event. Local-provider preflight exceptions follow the same rule; their bus receipt carries only an error digest and byte count.
- SQLite feedback learning uses an allow-list of operational metadata, fingerprints content-bearing fields, and fingerprints unknown field names rather than persisting their values. Fix-improvement feedback records the number of affected files and a digest rather than filenames.
- Reflexion events on the shared event bus contain kind, counts and fingerprints only. The local bounded reflection record keeps a redacted, limited diagnostic hint so repair continuity still has context.
- The shared `core:reason` event now stores only the reason digest and byte count. Tool-call subjects and tool-return errors likewise use digest/length metadata on the public event bus. Dmesg renders only that metadata and treats legacy raw-text payloads as redacted; the model-authored reason and tool result remain local to the active call.
- Transaction telemetry contains path counts and digests, and digests/lengths for free-form error or output fields. The protected transaction manifest remains the source for path-level rollback and recovery.

These changes reduce accidental leakage into logs, the learning database, and event subscribers. They are not a substitute for a complete data-retention review, and they do not make all event families privacy-safe. The commit/Phoenix journal and other event families still need a dedicated field-level review. Operational values such as model names, tool IDs, statuses and timing remain visible where they are required for routing and diagnosis.

### Fold lifecycle audit

The Fold's lifecycle observer now writes typed effect envelopes and can carry run and mission correlation IDs. Relevant local scope is hashed before persistence. The observer rejects untyped evidence references and continues to use the strict event-persistence path: if the before-event cannot be written, the effect must not run; if the after-event cannot be recorded, the Fold must not claim completion.

The interactive CoreBridge path supplies the durable mission ID and a mission-scoped attempt ID derived from its persisted attempt counter. A run with an interrupted or ambiguous outcome does not advance into verification unless that stage was actually reached; a completed Fold alone proceeds to the verification transition. A missing after-event receipt returns `trace_failed`, which the CLI maps to `unknown_outcome`: the external effect may have happened, but its result cannot be reconciled from durable evidence. The mission is marked terminal and non-resumable, not generically failed or `recovery_failed`, and it is never replayed blindly. `recovery_failed` is reserved for restoration/rollback that could not be proved. The standalone effect entrypoint can still use a run ID without a mission or attempt. These records cover the Fold's effect lifecycle; they do **not** mean every Fix transaction, tool, background job or deployment operation has been migrated to this contract.

### Cooperative cancellation

An interactive turn owns a `Master::Core::CancellationToken`. The token passes explicitly through the session and TurnRouter into CoreBridge and `Core::Fold`. For canonical slash commands, the same token is carried in the immutable `PipelineContext` through route/execute and into the `/fix` pipeline, `Pipeline::Pass` and `FixLoop`; no Fiber-local fallback is used for operation ownership.

The Fold observes cancellation before model work, after proposals and admission, before applying an admitted effect, and at the final turn boundary. `FixLoop` checks before preflight work, between expensive preflight phases, before each pass and after the current pass has returned. If cancellation arrives during a pass, that pass is allowed to finish its bounded transaction, pass receipt and convergence checkpoint; structural or later repair work must not start afterward. A persisted active transaction is reconciled before a resumed run is stopped.

Cancelled, unknown-outcome and recovery-failed repair missions are terminal and non-resumable. They do not count as successful completion or mark delivery complete. If a cancellation is already present before a run begins, it stops before creating a repair journal or mission; a run already underway records its terminal state.

**Limit:** cancellation is cooperative, not a thread kill. A model request, check command or external operation already in progress must return or reach its own timeout before the owner can observe the request. Other non-Fold commands and background/supervisor runs not attached to an interactive token retain their existing lifecycle. The universal before/after audit contract is still not integrated into every Fix transaction, tool, browser/MCP action, background job or deployment operation.

### Explicit interrupted outcomes

The result and repair outcome vocabularies distinguish `cancelled`, `unknown_outcome` and `recovery_failed`. These states are not successful outcomes and are classified as non-retriable without a new decision or reconciliation. The repair pass map stops rather than allowing these explicit statuses to fall through into another pass.

## Migration still required

The current changes are the first shared-contract slice. The following work remains and should be done in dependency order, with regression and recovery proof at every step.

1. **Complete the effect-boundary inventory.** Trace all real writers, tools, MCP handlers, browser actions, media tasks, background workers, repair transactions and deployment paths. Classify each as read-only, reversible, compensatable, irreversible or unknown. Every consequential effect must pass through constitutional admission and an appropriate execution boundary.
2. **Migrate lifecycle audit to every path.** Reuse typed effect IDs, run/mission linkage, redacted scope, mandatory before/after receipts and explicit unknown-outcome handling. In particular, audit Fix transaction and delivery events without logging raw prompts, file contents, credentials or unrestricted tool output.
3. **Unify findings and check results at call sites.** The new `VerificationResult` adapter is covered by source tests and is now exposed by check/proof adapters plus `Finding#to_verification`. The shared MASTER check runner now writes the normalized receipt beside its legacy ledger counts; this is not a full call-site migration. The Fix scorecard, OPENBSD runner, visual verification and delivery receipts do not emit it, and they move only when something reads the result: a receipt no consumer reads is the declaration-without-reader defect this tree keeps finding. Completeness is already enforced where green is decided: `/fix` withholds DONE while any file, stage or matrix cell is unmeasured (`Fix::FixLoop::Completion#blocked_by_gaps`), and the check runner names inconclusive and errored checks apart from passes while exiting 0 for them on purpose, because its deploy callers block on any non-zero exit (`checks/support/check_result.rb`, `errored!`). Preserve each source's semantics instead of reducing every outcome to a boolean.
4. **Finish one durable operation identity.** Carry mission, run, attempt, effect and parent IDs through every execution path. Use idempotency keys when an external API supports them; otherwise reconcile before replaying a result that may have happened but lacks a receipt. Do not claim exactly-once execution for arbitrary external effects.
5. **Consolidate coordinator ownership from evidence.** The candidate branch now places convergence, durable run journal and repair policy implementations under `Fix::Kernel`, retains `FixLoop`/`RepairLoop`/`RunJournal` compatibility constants, and routes production `/fix` through the Kernel lock and receipt boundary. Process-kill regressions cover transaction rollback, Mission checkpoint survival, journal deletion/resume and orphaned attempt receipts, but they are authored—not run on pinned Ruby 4.0.5. Run the focused and full suites, prove budget/collapse, delivery-failure and adapter receipt parity, then exercise one real repository-wide `/fix` before removing any compatibility aliases. Retain the existing transaction paths; the target is a shared execution contract, not a universal mega-loop.
6. **Harden isolation and parallel repair.** Candidate repair workers should use isolated worktrees, stable base revisions, bounded permissions and one integration/commit authority. Test conflicting edits, stale bases, worker loss, partial delivery and preservation of unrelated staged and unstaged work before making parallel repair the default.
7. **Complete skill promotion end to end.** A typed `execution_contract`, content-addressed revision and external operator approval manifest now exist, and a revision change invalidates approval. Still add the operator-facing candidate review/approval workflow; link fixture references to actual test results rather than trusting their presence; cover every Antigravity, registry and learned-skill source; and prove the new gate under the pinned runtime. A skill must never change the constitutional catalog or grant its own capabilities.
8. **Make model failover an observed contract.** Verify selected provider, actual credentials, structured-output/tool support, capability floor, timeout and retry class at the provider boundary. A routing log alone is not proof that the selected key or provider was used.
9. **Complete adapter and operations consistency.** Bring CLI, web, voice, browser, chat, device and background interactions onto shared session/mission semantics; expose degraded health and recovery instructions without letting adapters bypass constitutional admission.
10. **Keep policy, isolation and observability separate.** A policy decision is not an OS sandbox. A best-effort metric is not an audit receipt. A graph edge is not proof that every dynamic caller was found. Preserve these distinctions in APIs and terminal reports.

## Validation contract

The newly authored regression coverage includes the execution contract, cancellation token, CoreBridge persistence and cancellation, TurnRouter outcome mapping, Fix outcome policy and error classification. **These tests have not been executed in the current session** because a repository checkout could not be fetched in the available execution environment. Validation therefore remains **INCONCLUSIVE** until the focused tests run on the pinned Ruby runtime.

The focused set is:

```zsh
cd MASTER
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_execution_contract.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_proof_adapters.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_finding_metadata.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_skills.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_enhance_stage.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_core_cancellation.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_core_bridge.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_turn_router.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_cli.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_outcome_policy.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_err_classification.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_instrument_check.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_fix_transaction.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_provider_health_cache.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_provider_canary.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_llm_dispatcher.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_trace_support.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_feedback_ledger.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_reflexion_ledger.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_command_registry_dispatch.rb
```

After focused tests pass, run the full canonical MASTER suite and relevant operator checks. For changes that touch RAILS, OPENBSD or STUDIO, run their canonical checks too. Source inspection, a committed test, or a remote commit is never reported as an executed test or a verified deployment.

## Reversibility and replay semantics

Effect records now make reversibility explicit. `reversible` means the operation has a known restoration path; `compensatable` means a separate corrective action is required; `irreversible` means no reliable undo is available; and `unknown` means the system has not established the recovery semantics. The default is `unknown`, never an optimistic assumption.

The envelope marks irreversible and unknown effects as requiring reconciliation before replay. An idempotency key is only a request to deduplicate when the external target actually supports and honors that key; it does not itself prove exactly-once execution. This addition is backward-compatible at the schema-construction boundary, but the existing runtime callers still need an evidence-driven classification inventory and must propagate the declaration to the external-effect handlers.

### Adapter availability is not applicability

The /fix plan's adapter inventory now reports `unavailable` when the visual or opportunity assessor is absent, and `not_applicable_to_target` only when an installed assessor explicitly returns non-applicable. An adapter inventory is still only a capability statement: `SurfaceEvidence` receipts, source stability and actual browser/test/runtime evidence determine whether an assessment is complete. This distinction prevents a missing browser tool from being described as a target that does not need browser assessment.

### Rendered UI evidence integrity

A rendered surface is accepted only when the capture reports a clean render, a valid screenshot SHA-256, a valid geometry SHA-256 and a non-negative element count. The compact evidence retains the geometry digest and element count without persisting the page URL or page content. This checks receipt integrity and presence, not semantic correctness of the layout; geometry, accessibility and browser checks remain separate evidence sources.
