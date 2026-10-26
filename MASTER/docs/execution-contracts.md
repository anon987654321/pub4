# Execution contracts and architectural consolidation

**Status date:** 26 October 2026  
**Scope:** MASTER runtime and its integration boundaries. Vercel is deliberately out of scope.

This document describes what the current code has established and what remains to be migrated. A type or adapter existing in source is not evidence that every runtime path uses it, and a test being committed is not evidence that it passed.

## Implemented source changes

### Shared execution and evidence vocabulary

`MASTER/lib/execution/contract.rb` now owns a small set of validated, typed shapes:

- `EffectEnvelope` represents an effect's identity, verb, capability, operation, parent/checkpoint/run/mission IDs, optional idempotency key and deadline. Its optional scope is stored as a SHA-256 digest. Raw arguments and scope are not part of the envelope.
- `EvidenceReference` identifies evidence by ID, kind, status, verifier and optional digest. It carries a reference, not the underlying private content.
- `VerificationResult` adapts existing check results and `Master::Proof` into a stable outcome vocabulary. A check that ran but skipped declared coverage remains partial; an unavailable check remains inconclusive; a check error is not promoted into conclusive verification. The adapter uses duck typing and does not make MASTER import the sibling-tree `Deploy::CheckResult` implementation.
- The canonical repair terminal-state vocabulary now comes from this execution contract through `Master::Fix::OutcomePolicy`.

This is deliberately an adapter layer, not a second law registry or a replacement for `Master::Proof`, `Deploy::CheckResult`, or the repair loop's own state machine.

### Fold lifecycle audit

The Fold's lifecycle observer now writes typed effect envelopes and can carry run and mission correlation IDs. Relevant local scope is hashed before persistence. The observer rejects untyped evidence references and continues to use the strict event-persistence path: if the before-event cannot be written, the effect must not run; if the after-event cannot be recorded, the Fold must not claim completion.

The interactive CoreBridge path supplies the durable mission ID. The standalone effect entrypoint can still use a run ID without a mission. These records cover the Fold's effect lifecycle; they do **not** mean every Fix transaction, tool, background job or deployment operation has been migrated to this contract.

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
3. **Unify findings and check results at call sites.** The new `VerificationResult` adapter is available and tested in source, but scanners, the Fix scorecard, tree check runners, visual verification and delivery receipts have not all been migrated to emit or consume it. Preserve their specific semantics instead of reducing every outcome to a boolean.
4. **Finish one durable operation identity.** Carry mission, run, attempt, effect and parent IDs through every execution path. Use idempotency keys when an external API supports them; otherwise reconcile before replaying a result that may have happened but lacks a receipt. Do not claim exactly-once execution for arbitrary external effects.
5. **Consolidate coordinator ownership from evidence.** Map `Core::Fold`, `FixLoop`, `RepairLoop`, `Fix::Kernel`, `Mission`, `RunJournal`, `RunLedger` and `Transaction` against actual call sites and restart/rollback tests. Retain one public `/fix` coordinator and the existing transaction paths until behavioral equivalence is proven. The target is a shared execution contract, not a universal mega-loop.
6. **Harden isolation and parallel repair.** Candidate repair workers should use isolated worktrees, stable base revisions, bounded permissions and one integration/commit authority. Test conflicting edits, stale bases, worker loss, partial delivery and preservation of unrelated staged and unstaged work before making parallel repair the default.
7. **Promote skills by validation, not trust.** Existing skills already have content revisions; that is not the same as an approved, executable skill contract. Add explicit provenance, required capabilities, compatibility, fixtures, risk, verifier and promotion state before automatically learning or changing skills. A skill must not change the constitutional catalog.
8. **Make model failover an observed contract.** Verify selected provider, actual credentials, structured-output/tool support, capability floor, timeout and retry class at the provider boundary. A routing log alone is not proof that the selected key or provider was used.
9. **Complete adapter and operations consistency.** Bring CLI, web, voice, browser, chat, device and background interactions onto shared session/mission semantics; expose degraded health and recovery instructions without letting adapters bypass constitutional admission.
10. **Keep policy, isolation and observability separate.** A policy decision is not an OS sandbox. A best-effort metric is not an audit receipt. A graph edge is not proof that every dynamic caller was found. Preserve these distinctions in APIs and terminal reports.

## Validation contract

The newly authored regression coverage includes the execution contract, cancellation token, CoreBridge persistence and cancellation, TurnRouter outcome mapping, Fix outcome policy and error classification. **These tests have not been executed in the current session** because a repository checkout could not be fetched in the available execution environment. Validation therefore remains **INCONCLUSIVE** until the focused tests run on the pinned Ruby runtime.

The focused set is:

```zsh
cd MASTER
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_execution_contract.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_core_cancellation.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_core_bridge.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_turn_router.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_cli.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_outcome_policy.rb
RBENV_VERSION=4.0.5 rbenv exec ruby -Itest test/test_err_classification.rb
```

After focused tests pass, run the full canonical MASTER suite and relevant operator checks. For changes that touch RAILS, OPENBSD or STUDIO, run their canonical checks too. Source inspection, a committed test, or a remote commit is never reported as an executed test or a verified deployment.
