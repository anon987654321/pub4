# /fix coordinator and execution lifecycle ownership map

The map AGENTS.md requires before any of `FixLoop`, `RepairLoop`, `Kernel`,
`Mission`, `RunJournal`, `RunLedger` or `Transaction` is merged or removed:
one owner per responsibility, its size, and the production call sites that
reach it. Sizes are line counts of the class file (plus its subdirectory);
call sites are a text search of `lib/`, `bin/`, `tools/`, `checks/` and the
Rakefile, so a `send`, `const_get` or string-built require is not seen.

Source authority is `soul.yml` > `laws.yml` > executable laws and gates > tree contracts > Git history. Soul owns global identity, preservation and protected paths; the Law catalogue owns individual Law records.
Per-Law severity, mode, lifecycle, autofix and reach now live in
`laws.yml#law_catalogue`, consumed through `Master.law_catalogue`. Runtime
configuration remains in `law_runtime.yml`, which is not a second Law policy
surface. This file maps implementations; it is not a second policy surface.

## Owners

- **`Fix::FixLoop`** (compatibility entry point): the canonical implementation
  is `Fix::Kernel::ConvergenceAdapter` plus the modules under `fix_loop/`.
  It owns passes, lanes, council rounds, incremental scope, background-run
  hooks and terminal policy. Existing CLI, operator, builder and check callers
  retain the `FixLoop` constant while runtime proof gates remain open.
- **`Fix::RepairLoop`** (compatibility constant): the implementation is
  `Fix::Kernel::RepairAdapter` plus the existing `repair_loop/` policy modules.
  It remains one bounded batch per Law, including severity/size routing, autofix,
  collapse guard, file budget and verification. Legacy callers remain valid
  through `RepairLoop`; production PassRunner stages use the Kernel factory.
- **`Fix::Mission`** (729): the durable objective that survives process death.
  Called from `cli/command_registry.rb`, `cli/core_bridge.rb`,
  `operator/services.rb`, `fix_loop/{background_runner,committer,lifecycle}.rb`,
  `heartbeat.rb`, `supervisor.rb`, `task_steward.rb`.
- **`Fix::RunJournal`** (compatibility constant): canonical persistence lives in
  `Fix::Kernel::LifecycleJournal`. It maintains the existing metadata-only
  `.master/fix_runs.json` format, pass checkpoints and resume decisions. Kernel
  and `Operator::FixStatus` share one journal accessor; `Mission` remains the
  durable cross-run objective.
- **`Fix::RunLedger`** (231): in-memory accounting of one run's model phase:
  rejects per file, spent budgets, failing lanes. Called from
  `cli/command_registry/review.rb`, `file_repair.rb`,
  `fix_loop/pass_runner/stream_stage.rb`, `kernel/repair_adapter.rb`,
  `repair_loop/file_budget.rb`, `run_budget.rb`, `run_pulse.rb`.
- **`Fix::Transaction`** (728 + `transaction/{delivery,recovery}.rb` (930
  lines)): the per-pass source-write boundary for ordinary repairs: staged writes,
  rollback, crash recovery and Git delivery. Called from `fix_loop.rb`,
  `fix_loop/{committer,lifecycle,pass_runner}.rb`, `fix_plan.rb`, `patch.rb`,
  `dead_css_sweep.rb`, `scale_snap.rb`, `tap_target_pad.rb` and
  `tools/dead_css_sweep.rb`.
- **`Fix::Restructure`**: the multi-file commit path used by `RestructureSweep`.
  It validates the transformation plan and fresh source evidence, snapshots every
  touched path, applies the plan, runs adversarial review and tree-specific proof,
  then either restores the snapshot or makes one path-scoped commit and push.
  It is coordinated inside the Kernel-owned /fix run, but it does **not** use
  `Fix::Transaction`; its snapshot/undo and delivery contract must be assessed
  separately from per-pass transaction recovery.
- **`Fix::Kernel`**: production coordinator boundary and hash-chained receipt
  writer, while retaining `bin/master replay` and the existing log verification API.
  It owns the process-shared execution lock, run start/terminal receipts, the
  shared lifecycle journal accessor and the repair factory. It does not apply source
  edits. The hash-chained ledger is private and rejects symlinked paths, non-regular
  files, and non-private ledger permissions; retention/segmentation remains open.
- **`Fix::Kernel::ConvergenceAdapter`**: canonical class for the former `FixLoop`
  implementation and its pass modules. `FixLoop` remains a compatibility constant
  and entry-point file; existing command and operator callers keep their API.
- **`Fix::Kernel::RepairAdapter`**: canonical class for the former `RepairLoop`
  implementation and its policy modules. `RepairLoop` remains a compatibility
  constant, and bounded repair outcomes are emitted to the Kernel ledger.
- **`Fix::Kernel::LifecycleJournal`**: canonical implementation of the durable
  run journal and unchanged `.master/fix_runs.json` schema. `RunJournal` remains
  a compatibility constant; `Mission` continues to own the cross-run objective.

## What Kernel owns after this migration

The old Kernel mutation prototype is still gone: it has not been restored and
does not compete with `Transaction`. The retained Kernel now owns the repository-wide, process-shared
`/fix` execution lock at `.master/fix-execution.lock`, hash-chained coordinator
start/terminal receipts, repair outcome summaries, journal access and adapter
factories. Independent Kernel instances and OS processes must acquire the same
advisory file lock before a production run can enter its mutation path. Production boot enters
via `Kernel#build_fix_loop`; the convergence implementation is
`Kernel::ConvergenceAdapter`, the per-Law repair implementation is
`Kernel::RepairAdapter`, and the durable run-state implementation is
`Kernel::LifecycleJournal`. `FixLoop`, `RepairLoop` and `RunJournal` remain
compatibility constants for callers that have not been re-pointed.

The Kernel enters cancellation through the adapter-owned `with_cancellation`
scope. The adapter installs and restores its token in an `ensure` boundary;
Kernel activates the token inside its receipt/rescue boundary and never reads
or writes adapter instance variables.

Ordinary per-file repairs mutate through `FixLoop` / `Fix::Transaction`.
Multi-file structural changes are the explicit second path: `FixLoop` owns the
sweep, while `Fix::Restructure` uses a bounded snapshot, proof, undo and one
scoped delivery commit rather than the per-pass Transaction journal. Do not
describe a restructure as Transaction-backed or collapse the two paths without
crash/recovery and receipt-parity evidence.

Kernel appends a start receipt before execution and a truthful terminal receipt
after it. If a writer dies before terminalization, a later process marks the
orphan `unknown_outcome` only after same-host process identity proves the writer
is gone. It does not infer success. Pass outcomes record law, status, bounded
counts and run identity without source text or model prompts.

The new `test_fix_kernel_lifecycle.rb` and `test_fix_interruption_restart.rb`
cover owner identity, outcome receipts, repair counts and breakdowns, independent
Kernel-instance and process serialization, symlink and writable-directory refusal for
both the execution lock and hash-chained audit ledger, open-transaction rollback,
durable-run resume, journal deletion and Mission checkpoint survival, and orphan
receipt reconciliation. They are authored but **not run**: this
environment cannot provide the repository-pinned Ruby 4.0.5 checkout. The Phase 2
runtime gate is therefore still blocked; source consolidation is not proof of
behavioral parity.

## Overlap that remains

- `RunJournal` (durable, per run) and `Mission` (durable, across runs) both
  persist progress; `RunLedger` (in memory, per run) overlaps `RunJournal`'s
  pass metadata. Merging any two of them needs the recovery tests first.
- `Transaction` owns delivery (commit and push) as well as staging; `FixLoop`'s
  `committer.rb` also decides what to commit.
- `Restructure` has its own in-memory snapshot/undo and one-commit delivery
  path. Keep it an explicit owner until a process-interruption test proves
  recovery parity with `Transaction`; ordinary pass receipts alone do not prove
  per-file rollback after a crash during a multi-file restructure.

## Recovery tests and gate status

The authored process-boundary regression in `test_fix_interruption_restart.rb`
starts a real Ruby subprocess using public `FixLoop#run`, opens a pass
`Transaction`, persists a controlled partial write, kills the writer, and then
restarts through the normal run entry point. It checks byte-exact rollback,
journal resume, the durable Mission/checkpoint, transaction cleanup, and the
orphaned Kernel receipt. A separate fixture deletes the run journal while
checking that the independent Mission checkpoint and transaction snapshot
survive. Owner and outcome regressions live in `test_fix_kernel_lifecycle.rb`.

These tests are source changes, **not passing results**. The merge remains
blocked until the tests run on the pinned Ruby 4.0.5, then the relevant
release-runtime verification is also recorded. The canonical repository pin is Ruby 4.0.5, shared by root, MASTER and Rails apps.
These tests remain unexecuted in this GitHub editing environment. Still required after the
process-boundary test: a real budget/collapse regression, truthful per-file
ledger behavior for zero repairs, the complete adapter receipt-parity matrix,
delivery-failure recovery, and one real repository-wide `/fix` run whose
terminal state and repair counts are recorded.

## Cross-cutting execution lifecycle

The lifecycle sections below preserve the distinct owners that surround
the /fix coordinator. They were mapped from production call sites on
2026-10-26; re-check those call sites before changing an owner. The overlapping
Kernel/journal section is intentionally kept only once above.

### Core::Fold

CoreBridge builds it (lib/cli/core_bridge.rb, build_fold), reached from the
TaskSteward and the interactive session; `bin/master core` builds the standalone
one. It keeps no state of its own. Every effect passes Constitution#admit,
compensations included, and EffectObserver brackets it with durable
core:effect:before and after events. A trace failure ends the turn as
unknown_outcome, which stops automatic continuation. Delivery is a path-scoped
World git commit; the Fold never pushes. `bin/master core` admits with the same
scan verifier and shell sandbox as CoreBridge since 50e3fc1e6.

### Core::Constitution and Core::World

The Constitution reads laws.yml and soul.yml's sacred paths; its Paths class
also backs the sacred-path refusal in GitOperations, AutofixGuard and the /fix
file collector. World dispatches each verb to a do_ method and checks
capabilities. Its checkpoints live in memory, so a crash loses them; the Fold's
compensations cover one path at a time.

### The inner repair loop

Pass stages build RepairLoop; it writes source with write_atomic inside the
pass transaction and relies on the reflexion verifier, the consensus panel, the
collapse guard and the Committer's path validation. WatchLoop builds none: a
changed file wakes the background runner or starts an incremental FixLoop run,
so its repairs get a transaction and a run ledger like any other.


### Reactive, improvement and restructure lanes

- **`Fix::WatchLoop`** observes supported source changes, debounces and
  rate-limits events, then either wakes the live background runner or starts an
  incremental `FixLoop` run. It never edits files itself.
- **`Fix::Improve::Engine`** is the elevation sensor, not a writer. It emits
  Law-grounded findings, ideation and merge/flatten proposals.
  `FixLoop::PassRunner` turns those findings into the existing improvement
  lane; proposals enter `Fix::RestructureSweep`'s candidate, plan and review flow.
- **`Fix::RestructureSweep`** is built by `Kernel::ConvergenceAdapter` and
  runs inside the same Kernel-owned /fix execution.
  `Fix::Improve::Restructure` only proposes candidates. The final multi-file
  write is `Fix::Restructure`:
  validate operations and current source evidence, snapshot, apply, inspect the
  diff, run adversarial review and tree proof, then undo on failure or deliver
  one scoped commit. This is a distinct path from the per-pass
  `Fix::Transaction` journal.
- **Tool admission** belongs to `Fix::Governor`: guarded/dangerous tier rules,
  human-consent checks, the exact unattended allowlist and per-run dangerous
  budget live there, not in a watcher, pass stage or individual tool.
- **Model dispatch and redaction** belong to `Review::LLMDispatcher` and
  `Ground::Redactor`. Outbound system text and messages pass through the
  redactor; a loop must not construct provider requests or maintain a second
  secret-pattern list.

The improvement and watcher paths still have distinct budgets and clocks.
Their names do not imply one shared scheduler or cost ledger; measure and
reconcile those only after the runtime call graph and interruption behavior are
proved.

### Fix::Mission

Lifecycle, the background runner, the Supervisor, the TaskSteward and CoreBridge
build it. State is .master/mission.json under a lock and a lease. A handle that
claimed a mission may write only that mission while it holds the lease; any
other write raises Mission::Fenced (c296719e1). The Supervisor, Heartbeat and
TaskSteward read it and wake work whose lease expired. Two missions coexist: the
Fold's under MASTER's root and /fix's under the repository root
(FixLoop#mission_root); FixLoop's run mutex and the transaction lock already
serialise their writes. Heartbeat wakes /fix's, the TaskSteward tends the
Fold's, and /status mission, fix_status and the service check name each.

### Fix::Transaction and Delivery

The pass runner builds one per pass under <root>/.master/fix_transactions with
a root lock. States run open, delivering, then committed or rolled back, or end
in conflict. A committed or rolled-back transaction refuses rollback by name
(2ddc00247). At the start of every run, FixLoop recovers each persisted
transaction: an open pass rolls back unless its files changed since, which
keeps it as a conflict; a delivering one is finalised only when the recorded
HEAD still matches (43b53ec61). Each delivery commit carries "fix transaction
<id>" in its body, so a delivery the process died inside before recording its
commit is settled from git: the marked commit is the head to finalise, and no
such commit since head_before means it never landed and the pass rolls back.

### Tool dispatch, MCP and git

LLMDispatcher and McpCoordinator wrap every tool call in Trace::ToolObserver: a
durable before-receipt or no call, then an after-receipt with the outcome.
GitOperations does the same for add, commit, push and the rebase a rejected push
needs (ec589be8d). A new observer rebuilds the unknown-outcome quarantine from
those receipts, so a restart or a crash mid-call keeps it, and /doctor tools
lists and reconciles it. test_effect_boundary_inventory names every place outside
lib/builder.rb that builds a consequential tool.

### Deployment

/deploy runs bin/operator vps deploy over ssh. MASTER keeps no deploy state;
rollback on the box is the operator's (operator_seams.yml).

### Open gaps, by risk

1. Kernel now appends coordinator and repair-outcome receipts in production.
   Its hash-chained `.master/log.jsonl` reader refuses symlinked, hard-linked,
   non-regular or non-private ledger files, blank records and torn tails, and verifies path identity before
   and after reading. Runtime results remain unmeasured here: run the focused
   replay, lifecycle and process-kill regressions on pinned Ruby 4.0.5, then
   prove transaction rollback, durable resumption, orphan-receipt recovery,
   budget/collapse and zero-repair ledger honesty, and the adapter receipt-parity
   matrix. A real repository-wide `/fix` trial still has not run.
   Define hash-chain-preserving retention/segmentation with explicit checkpoints
   before long-running production use; never truncate arbitrary log prefixes.

`Supervisor`, `Governor`, `Homeostat`, `Watcher` and `WatchLoop` share names with
unrelated classes elsewhere in `lib/` and are outside this map.
