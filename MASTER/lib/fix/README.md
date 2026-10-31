# lib/fix — boundary map

`lib/fix` is the largest subsystem in the tree (206 files, ~41k lines). Its size is
consolidation debt: five loop mechanisms grew side by side, each with its own budget,
and two of them still exist as compatibility constants for callers that predate the
Kernel move. This file is the map that consolidation works behind — what owns what,
what may call what, and which seams are still open. It is a description of the code
as it stands, not a claim that the consolidation is finished.

## The one rule

Mutations go through the FixLoop identity. Anything that wants to change the tree on
the fix path — a watcher reacting to a file, an elevation pass, a restructure — starts
a FixLoop run, so the repair gets the pass transaction, the journal entry and the run
ledger, and `FixLoop#run`'s mutex keeps it from overlapping an operator's `/fix`. A
loop that applied repairs by any other road would be unjournaled work, which is the
one thing the receipts chain cannot survive.

## The five loop mechanisms

| Mechanism | File | What it is today |
| --- | --- | --- |
| FixLoop | `fix_loop.rb` | Compatibility entry point. The canonical implementation and identity live under `Fix::Kernel`; the adapter installs the legacy constant before its child modules load so every pass module reopens the same class object. |
| RepairLoop | `repair_loop.rb` | Compatibility constant for legacy callers. The implementation lives under Kernel so the production repair policy has one canonical namespace. |
| Restructure | `restructure.rb` | Applies one multi-file restructure (a split, a merge, a flattened directory) and keeps it only when a hostile review approves the diff and the proof holds. |
| Improve | `improve.rb` | The Elevation Engine — the half of /fix that does not repair. It measures distance from the ideal, closes it one anchored, evidence-backed step per pass, and never blocks a run: severity rides the improvement lane. |
| WatchLoop | `watch_loop.rb` | File-watcher reactive trigger (inotify on Linux, kqueue on OpenBSD). A changed file wakes the background runner or starts an incremental FixLoop run on that file. |

The two compatibility rows are the identity dance: `FixLoop` is both the legacy name
and, through `Kernel::ConvergenceAdapter`, the same object the Kernel drives. New code
should name `Fix::Kernel` and the pass modules, not the constants.

## Kernel

`kernel.rb` and `kernel/` own the hash-chained /fix coordinator lifecycle and keep the
replay reader public for `bin/master replay <seq>`. The Kernel does **not** apply
repairs — `FixLoop`, the repair adapter and the transaction system retain the mutation
responsibilities, and a broken receipts chain is refused rather than returned as
partial history.

## What may call what

- `watch_loop.rb` → FixLoop only. A watcher never edits a file itself.
- `improve.rb` and `restructure.rb` → through the FixLoop pass machinery, so every
  step is anchored, evidenced and journaled like a repair.
- Everything → the Governor for tiered tool approval (`governor.rb`). The @auto
  dangerous-tier gates (persistent allowlist, per-run budget) are enforced here and
  nowhere else; a loop must not carry its own approval path.
- Everything → `Ground::Redactor` by way of the LLM dispatcher. No loop assembles a
  provider request by hand.

## Open seams

Named honestly, because a map that hides the debt is a brochure:

- Five mechanisms with separate pass budgets are still five mechanisms. The budgets
  have not converged; a run under WatchLoop and a run under Improve charge different
  clocks.
- The compatibility constants are load-bearing until every caller has moved; the
  adapter's `remove_const` dance exists because they are constants and not assignments.
- The error regimes (Result, exceptions, Observation-swallowing) meet inside this
  directory and are reconciled by translation at the boundary. Unifying them behind
  Result is the next consolidation step after this map.
