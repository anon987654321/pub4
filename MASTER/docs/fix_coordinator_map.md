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

- **`Fix::FixLoop`** (569 + 21 files under `fix_loop/` (6,176 lines)): the
  `/fix` lifecycle: passes, lanes, council rounds, background run, terminal
  state. Called from `cli/command_registry.rb`,
  `cli/command_registry/review.rb`, `cli/pipeline/pass.rb`,
  `operator/canary.rb`, `operator/fix_status.rb`, `operator/snapshot_pack.rb`,
  `builder/ai_boot.rb`, `tools/boot_smoke.rb`, `bin/check`, `Rakefile`, and 15
  `lib/fix/` collaborators.
- **`Fix::RepairLoop`** (595 + 6 files under `repair_loop/` (1,656 lines)):
  one repair batch for one Law: routing by severity and size, autofix policy,
  collapse guard, per-file budget, verification. Called from `fix_loop.rb` and
  its `council_round`, `evidence_stage`, `llm_stage`; `ground/laws.rb`,
  `review/scan/law.rb`, `review/scan/semantic_fingerprint.rb`,
  `cli/pipeline/proof/rails_apps.rb`, and 11 `lib/fix/` collaborators.
- **`Fix::Mission`** (729): the durable objective that survives process death.
  Called from `cli/command_registry.rb`, `cli/core_bridge.rb`,
  `operator/services.rb`, `fix_loop/{background_runner,committer,lifecycle}.rb`,
  `heartbeat.rb`, `supervisor.rb`, `task_steward.rb`.
- **`Fix::RunJournal`** (1,189): per-run lifecycle metadata and resume point
  (never file content). Called from `fix_loop.rb`,
  `fix_loop/{completion,lifecycle,pass_execution}.rb`,
  `fix_loop/pass_runner/assessment_matrix.rb`, `fix_plan.rb`, `fix_trace.rb`,
  `operator/fix_status.rb`.
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
- **`Fix::Kernel`** (107): read and verify the hash-chained
  `.master/log.jsonl` for `bin/master replay`. Called from `bin/master replay`
  (`Kernel.replay_cli`).

## What Kernel is now

`Kernel` was described as the canonical survivor, but `Kernel.new` and
`Kernel#fix` had no production caller: only `test/test_fix_kernel.rb` built one,
and the hash-chained log it appended to existed in no checkout. Its private Law
type and the two-Law list in `MASTER/laws.rb` restated a sacred-path guard that
`Ground::Immutability` and the commit hooks already enforce. The repair core,
`laws.rb` and their tests are gone; the replay reader stays, with tests that
build a valid chain and prove gaps, edits and torn records are refused. The
`.pub4` boundary manifests at each tree root were read only by the removed
`Kernel#manifest_for` and now have no reader.

`FixLoop` is the coordinator in fact: every production path to `/fix` enters
through it. Folding the others into it, or it into them, is still gated on the
recovery tests below.

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
