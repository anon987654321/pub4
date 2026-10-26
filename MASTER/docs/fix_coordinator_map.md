# /fix coordinator responsibility map

The map AGENTS.md requires to exist before any of `FixLoop`, `RepairLoop`,
`Kernel`, `Mission`, `RunJournal`, `RunLedger` or `Transaction` is merged or
removed: every responsibility, its real call sites, and the recovery proof each
deletion has to pass. Written from static call-site analysis only — the analysis
environment had no Ruby runtime — so every "no callers found" below is a text-
search result, not a runtime proof, and each phase gate says so.

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
| `Fix::Kernel` | 686 lines + `transaction/` | "The small, auditable repair core." | `bin/master.rb:21` (`Kernel.replay_cli`) | Canonical survivor. Receives responsibilities; deletes nothing itself. |
| `Fix::FixLoop` | 976 lines + `fix_loop/` (13 files) | LLM repair loop: pass runners, council rounds, llm_router, background runner | `tools/boot_smoke.rb`, `lib/cli/command_registry/review.rb`, `lib/operator/canary.rb`, `lib/cli/pipeline/pass.rb`, `lib/operator/snapshot_pack.rb`, `lib/builder/ai_boot.rb` | Adapter. Folds into Kernel responsibility-by-responsibility behind parity receipts. |
| `Fix::RepairLoop` | 569 lines + `repair_loop/` (6 files) | Autofix policy, collapse guard, file budget, outcome tracking | `lib/ground/laws.rb`, `lib/review/scan/semantic_fingerprint.rb`, `lib/review/scan/law.rb` | Adapter. Same folding discipline as FixLoop; its `collapse_guard` and `file_budget` are recovery machinery that must move with tests, not be rewritten. |
| `Fix::Mission` | 668 lines | "The durable objective. A FixLoop execution is only one attempt to advance it; process death must never erase the work that remains." | `lib/cli/command_registry.rb:585`, `lib/operator/services.rb:85-87` | Keep. Kernel has no durability story; Mission is the only owner of survive-process-death semantics. |
| `Fix::RunJournal` | 298 lines | "Durable lifecycle journal for /fix runs … deliberately metadata-only. It never tries to reconstruct files from JSON; Git, Checkpoint and the write journal remain the sources." | none found outside `lib/fix` (required by `fix_loop.rb`) | Merge candidate. Its content guarantee (metadata-only, git as source) must become Kernel's guarantee before the file disappears. |
| `Fix::RunLedger` | 177 lines | "What one /fix run has learned about its own model phase … why proposals were rejected (and how often per file), which files ran out of wall-clock, which lanes keep failing." | `lib/cli/command_registry/review.rb` | Keep until FixLoop folds; then decide whether Kernel receipts subsume it. Its 2026-10-12 origin (runs that fixed nothing and only said "0 fixed") is the requirement it exists to keep. |
| `Fix::Transaction` | 559 lines + `transaction/` | Transaction path for staged writes | `tools/dead_css_sweep.rb` | Map against Kernel's own staging before any move; if `dead_css_sweep` uses the same class, it is a second entry point the merge must keep working. |

### Near-neighbours that are deliberately out of scope

`Supervisor`, `Governor`, `Homeostat`, `Watcher` and `WatchLoop` exist under
`lib/fix/` and also as unrelated classes elsewhere (`lib/voice/*` supervisors,
`lib/io/web_fetch.rb` and `lib/ground/policy/sandbox.rb` governors). The name
collisions are exactly why AGENTS.md asks for this map. They are not part of the
mandated set; none of them moves in this campaign, and no verdict here covers
them.

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
