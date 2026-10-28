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

- **`Fix::FixLoop`**: compatibility constant for `Kernel::ConvergenceAdapter`
  in `lib/fix/kernel/convergence_adapter.rb`; responsibility modules remain in
  `lib/fix/fix_loop/`. Existing CLI/operator/build call sites remain routed through
  the public constant.
- **`Fix::RepairLoop`**: compatibility constant for `Kernel::RepairAdapter`
  in `lib/fix/kernel/repair_adapter.rb`; its budget, collapse guard and repair
  policy remain grouped in that adapter, with shared stage factories owned by Kernel.
- **`Fix::Mission`** (729): the durable objective that survives process death.
  Called from `cli/command_registry.rb`, `cli/core_bridge.rb`,
  `operator/services.rb`, `fix_loop/{background_runner,committer,lifecycle}.rb`,
  `heartbeat.rb`, `supervisor.rb`, `task_steward.rb`.
- **`Fix::RunJournal`**: compatibility constant for `Kernel::LifecycleJournal`
  in `lib/fix/kernel/lifecycle_journal.rb`. It retains the persisted run schema
  and metadata-only recovery contract; Kernel owns its shared accessor.
- **`Fix::RunLedger`** (231): in-memory accounting of one run's model phase:
  rejects per file, spent budgets, failing lanes. Called from
  `cli/command_registry/review.rb`, `file_repair.rb`,
  `fix_loop/pass_runner/stream_stage.rb`, `repair_loop.rb`,
  `repair_loop/file_budget.rb`, `run_budget.rb`, `run_pulse.rb`.
- **`Fix::Transaction`** (728 + `transaction/{delivery,recovery}.rb` (930
  lines)): staged writes, rollback, crash recovery and Git delivery of a pass.
  Called from `fix_loop.rb`, `fix_loop/{committer,lifecycle,pass_runner}.rb`,
  `fix_plan.rb`, `patch.rb`, `dead_css_sweep.rb`, `scale_snap.rb`,
  `tap_target_pad.rb`, `tools/dead_css_sweep.rb`.
- **`Fix::Kernel`**: verifies and appends the hash-chained `.master/log.jsonl`,
  owns run-level coordination/locking and start/terminal receipts, and provides
  shared journal and repair factories. Production entry: `lib/builder/ai_boot.rb`
  via `Kernel#build_fix_loop`; replay remains `Kernel.replay_cli`.

## What Kernel is now

Kernel began as the verifier/replay API for `.master/log.jsonl`. It now also owns
the production `/fix` run boundary: a process-shared `.master/fix-execution.lock`,
hash-chained start/terminal receipts, correlation of bounded repair outcome
summaries, and a shared accessor for the schema-preserving run journal. A separate
recovery lock serializes the inspect-and-terminalize sweep across Kernel instances. It reconciles a missing
terminal receipt to `unknown_outcome` only when same-host process-death evidence
exists; a live or unverifiable writer is left open.

The implementation classes moved under Kernel are `Kernel::ConvergenceAdapter`,
`Kernel::RepairAdapter`, and `Kernel::LifecycleJournal`. Historical constants
`FixLoop`, `RepairLoop`, and `RunJournal` remain aliases during the adapter
migration. `Mission` continues to own the durable objective and lease, and
`Transaction` continues to own write rollback and delivery recovery; namespacing
these classes does not make those contracts redundant.

The subprocess regressions in `test/test_fix_interruption_restart.rb` cover
transaction rollback after a killed writer, durable run resumption, orphaned
Kernel receipt reconciliation, and Mission/checkpoint retention after deleting
the run journal. They are authored but unexecuted: neither these tests, the full
MASTER suite, nor a repository-wide `/fix` trial has run on pinned Ruby 4.0.5.
The migration remains blocked on that runtime evidence and the adapter-parity
matrix; source movement alone is not the proof.

## Overlap that remains

- `RunJournal` (durable, per run) and `Mission` (durable, across runs) both
  persist progress; `RunLedger` (in memory, per run) overlaps `RunJournal`'s
  pass metadata. Merging any two of them needs the recovery tests first.
- `Transaction` owns delivery (commit and push) as well as staging; `FixLoop`'s
  `committer.rb` also decides what to commit.

## Recovery tests a merge must pass first

One per responsibility, each planting a defect, asserting red, then green:

1. Staging and rollback: an aborted `Transaction` restores byte-identical state.
2. Durable objective: kill the process mid-run; `Mission` reports the remaining
   work after restart.
3. Journal: delete the journal mid-run; Git and `Checkpoint` reconstruct, and the
   journal is never the only copy of anything.
4. Budget and collapse: a run over its file budget trips `collapse_guard`
   instead of looping.
5. Ledger honesty: a run that fixes nothing names why, per file, in one place.
6. Adapter parity: every CLI path above reaches the same receipt before and
   after the move.

`Supervisor`, `Governor`, `Homeostat`, `Watcher` and `WatchLoop` share names with
unrelated classes elsewhere in `lib/` and are outside this map.
