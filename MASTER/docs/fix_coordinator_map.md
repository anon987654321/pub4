# /fix coordinator responsibility map

The map AGENTS.md requires before any of `FixLoop`, `RepairLoop`, `Kernel`,
`Mission`, `RunJournal`, `RunLedger` or `Transaction` is merged or removed:
one owner per responsibility, its size, and the production call sites that
reach it. Sizes are line counts of the class file (plus its subdirectory);
call sites are a text search of `lib/`, `bin/`, `tools/`, `checks/` and the
Rakefile, so a `send`, `const_get` or string-built require is not seen.

Authority is unchanged: `soul.yml` > `laws.yml` > executable enforcement. This
file maps implementations; it is not a second policy surface.

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
  lines)): staged writes, rollback, crash recovery and Git delivery of a pass.
  Called from `fix_loop.rb`, `fix_loop/{committer,lifecycle,pass_runner}.rb`,
  `fix_plan.rb`, `patch.rb`, `dead_css_sweep.rb`, `scale_snap.rb`,
  `tap_target_pad.rb`, `tools/dead_css_sweep.rb`.
- **`Fix::Kernel`**: production coordinator boundary and hash-chained receipt
  writer, while retaining `bin/master replay` and the existing log verification API.
  It owns the execution mutex, run start/terminal receipts, the shared lifecycle
  journal accessor and the repair factory. It does not apply source edits.
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
does not compete with `Transaction`. The retained Kernel now owns the outer
`/fix` execution lock, hash-chained coordinator start/terminal receipts, repair
outcome summaries, journal access and adapter factories. Production boot enters
via `Kernel#build_fix_loop`; the convergence implementation is
`Kernel::ConvergenceAdapter`, the per-Law repair implementation is
`Kernel::RepairAdapter`, and the durable run-state implementation is
`Kernel::LifecycleJournal`. `FixLoop`, `RepairLoop` and `RunJournal` remain
compatibility constants for callers that have not been re-pointed.

The existing `FixLoop` / `Transaction` mutation and rollback path remains the
only source-editing path. Kernel appends a start receipt before execution and a
truthful terminal receipt after it. If a writer dies before terminalization,
a later process marks the orphan `unknown_outcome` only after same-host process
identity proves the writer is gone. It does not infer success. Pass outcomes
record law, status, bounded counts and run identity without source text or model
prompts.

The new `test_fix_kernel_lifecycle.rb` and `test_fix_interruption_restart.rb`
cover owner identity, outcome receipts, open-transaction rollback, durable-run
resume, journal deletion and Mission checkpoint survival, and orphan receipt
reconciliation. They are authored but **not run**: this environment cannot
provide the repository-pinned Ruby 4.0.5 checkout. The Phase 2 runtime gate is
therefore still blocked; source consolidation is not proof of behavioral parity.

## Overlap that remains

- `RunJournal` (durable, per run) and `Mission` (durable, across runs) both
  persist progress; `RunLedger` (in memory, per run) overlaps `RunJournal`'s
  pass metadata. Merging any two of them needs the recovery tests first.
- `Transaction` owns delivery (commit and push) as well as staging; `FixLoop`'s
  `committer.rb` also decides what to commit.

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
blocked until the tests run on pinned Ruby 4.0.5. Still required after the
process-boundary test: a real budget/collapse regression, truthful per-file
ledger behavior for zero repairs, the complete adapter receipt-parity matrix,
delivery-failure recovery, and one real repository-wide `/fix` run whose
terminal state and repair counts are recorded.

`Supervisor`, `Governor`, `Homeostat`, `Watcher` and `WatchLoop` share names with
unrelated classes elsewhere in `lib/` and are outside this map.
