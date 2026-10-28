# /fix coordinator responsibility map

The map AGENTS.md requires before responsibilities are moved or adapters are
removed: every responsibility, its production call sites, and the recovery
proof each deletion has to pass. The original call-site inventory was static
analysis. The 2026-10-28 Kernel integration is source-reviewed only; this
environment cannot access a working repository checkout with pinned Ruby 4.0.5,
so no Ruby/Minitest result is claimed. Text search is not runtime proof.

Authority is unchanged: `soul.yml` > `laws.yml` > executable enforcement. This
file is a map of implementations, not a second policy surface.

## The one-sentence target

AGENTS.md already states it: one canonical `/fix` coordinator, one scanner and
finding contract, one transaction path, one operational check runner. `Kernel`'s
own header names it the survivor: "The small, auditable repair core. Existing
/fix stages remain its compatibility adapter until their laws have migrated
with proof." Everything here serves that sentence.

## Per-class map

| Class | Size | Self-description (docstring) | External call sites | Verdict |
|---|---|---|---|---|
| `Fix::Kernel` | Core ledger/observation/repair API plus `kernel/` lifecycle adapters | `bin/master replay`, production /fix via `lib/builder/ai_boot.rb` | Canonical owner. Production execution, the journal accessor, bounded repair receipts, and factories are routed through Kernel. |
| `Fix::FixLoop` | Compatibility constant for `Kernel::ConvergenceAdapter`; pass modules remain split under `fix_loop/` | `lib/builder/ai_boot.rb`, CLI/operator callers | The implementation class is now nested under Kernel. Kernel owns the top-level lock and terminal receipts; the adapter preserves convergence/pass contracts for parity-tested migration. |
| `Fix::RepairLoop` | Compatibility constant for `Kernel::RepairAdapter` in `kernel/repair_adapter.rb` | legacy direct callers and Kernel pass factory | The implementation and policy now have one Kernel-owned class; prompt-free outcome summaries are recorded in Kernel's ledger. Preserve the old constant until callers migrate. |
| `Fix::Mission` | 668 lines | Durable objective and lease fencing | `lib/cli/command_registry.rb:585`, `lib/operator/services.rb:85-87` | Keep. Mission remains the durable objective/ownership boundary; Kernel does not replace its state machine. |
| `Fix::RunJournal` | Compatibility constant for `Kernel::LifecycleJournal` in `kernel/lifecycle_journal.rb` | Kernel's journal accessor and legacy callers | The durable journal implementation is nested under Kernel; schema and recovery semantics remain unchanged. Keep the old constant while parity tests exercise persisted runs. |
| `Fix::RunLedger` | 177 lines | "What one /fix run has learned about its own model phase … why proposals were rejected (and how often per file), which files ran out of wall-clock, which lanes keep failing." | `lib/cli/command_registry/review.rb` | Keep until FixLoop folds; then decide whether Kernel receipts subsume it. Its 2026-10-12 origin (runs that fixed nothing and only said "0 fixed") is the requirement it exists to keep. |
| `Fix::Transaction` | 559 lines + `transaction/` | Transaction path for staged writes | `tools/dead_css_sweep.rb` | Map against Kernel's own staging before any move; if `dead_css_sweep` uses the same class, it is a second entry point the merge must keep working. |

### Near-neighbours that are deliberately out of scope

`Supervisor`, `Governor`, `Homeostat`, `Watcher` and `WatchLoop` exist under
`lib/fix/` and also as unrelated classes elsewhere (`lib/voice/*` supervisors,
`lib/io/web_fetch.rb` and `lib/ground/policy/sandbox.rb` governors). The name
collisions are exactly why AGENTS.md asks for this map. They are not part of the
mandated set; none of them moves in this campaign, and no verdict here covers
them.

## Integration landed 2026-10-28 (source changes; runtime proof pending)

- Production boot creates `Fix::Kernel`; `Kernel::Lifecycle#build_fix_loop` loads
  the legacy source adapter as `Kernel::ConvergenceAdapter`, with `FixLoop` retained
  as a compatibility constant for existing call sites.
- `FixLoop#run` delegates the outer execution lock and coordinator start/terminal
  receipts to Kernel. Repair summaries correlate to the coordinator run id; a
  restart marks same-host coordinator starts with a demonstrably dead writer as
  `unknown_outcome`, while leaving possibly-live peer processes untouched.
- The durable run journal implementation is `Kernel::LifecycleJournal`; the old
  `RunJournal` constant points to the same class. Kernel and `Operator::FixStatus`
  use the shared accessor, preserving the existing on-disk format.
- The repair implementation is `Kernel::RepairAdapter`; `RepairLoop` is a
  compatibility constant to the same class. Pass stages and visual repairs use
  the Kernel factory and write bounded outcome summaries to the Kernel ledger.
- `test/test_fix_kernel.rb` and `test/test_fix_convergence.rb` exercise source
  ownership and receipts. `test/test_fix_interruption_restart.rb` starts a separate
  Ruby process, persists a partial transaction, kills the writer, then exercises
  FixLoop's real startup-recovery sweep in a second process, checks byte-exact
  rollback and durable-run resumption, and verifies the abandoned Kernel receipt
  becomes `unknown_outcome`. These tests are authored but unexecuted here.

The structural move is landed with compatibility aliases retained. The remaining
gates are runtime proof on pinned Ruby 4.0.5, Mission survival, journal-loss
reconstruction, pass/delivery adapter parity, and a real repository-wide `/fix`
trial. Do not delete the compatibility aliases until those gates pass.
## Merge order

Each phase is gated, and a gate that cannot run is a stop, not a formality.

**Phase 0 — runtime prerequisite.** A Ruby 4.0.5 host (the repo's single pin)
that can boot the check ladder and the RAILS stack contract suite. Every gate
below runs commands. Without the host, the merge is BLOCKED, not pending.

**Phase 1 — freeze the surface.** No new stage, lane or pass may be added to
`FixLoop` or `RepairLoop`. New behaviour lands in `Kernel` only. This costs
nothing and makes the fold finite.

**Phase 2 — recovery tests first, per responsibility.** The tests AGENTS.md
demands, written before anything moves. Minimum set, one test per
responsibility, each planting a defect, asserting red, asserting green, and
running once against a gutted implementation:

1. Staging and rollback: a write that must land as one `Transaction`, and the
   abort path that restores byte-identical state (Kernel ↔ Transaction).
2. Durable objective: kill the process mid-run; Mission must still report the
   remaining work after restart.
3. Journal: delete the journal mid-run; Git + Checkpoint reconstruct; the
   journal must never be the only copy of anything.
4. Budget/collapse: a run that exceeds its file budget trips `collapse_guard`
   instead of looping (RepairLoop → Kernel).
5. Ledger honesty: a run that fixes nothing reports why, per file, in one
   place (RunLedger's founding complaint).
6. Adapter parity: for every CLI path that reaches `FixLoop` or `RepairLoop`
   today (`boot_smoke`, `canary`, `pipeline/pass`, `snapshot_pack`, `ai_boot`,
   `command_registry/review`, `ground/laws`, `scan/law`,
   `scan/semantic_fingerprint`), the same input through the Kernel path must
   produce the same receipt bytes.

**Phase 3 — move one responsibility at a time.** Kernel gains the
responsibility behind its existing receipt contract; the old call site stays
working through the adapter. Both paths run in the same session for at least
one real convergence run before the old one is switched off. Commits are
path-scoped, one responsibility per batch.

**Phase 4 — delete the adapters.** Only after Phase 3 has covered every row of
the table above. `RunJournal` merges first (no external callers), then
`RepairLoop` (fewest external call sites), then `FixLoop`. `Mission` and
`RunLedger` are re-judged at the end, not assumed.

**Phase 5 — regenerate the generated surfaces.** `rake docs:agent_contracts`,
then `rake lint:agent_contracts`, because AGENTS.md's marked block describes
this landscape and must not drift from it.

## What this file does not claim

- It does not claim `RunJournal` has no dynamic dispatch callers; text search
  cannot see `send`, `const_get` or string-built requires.
- It does not claim the adapters are safe to delete now. Phase 2's tests do
  not exist yet, and the merge order is written so that a missing test stops
  the phase instead of skipping it.
- It does not rank `lib/fix/visual_*` (the 20+ flat visual instruments). They
  are FixLoop's dependency surface, so they move with Phase 3, not before it;
  consolidating them into one instrument with modes is proposed separately in
  `docs/restructure_assessment.md`.
