# Lifecycle ownership

Who builds each part of MASTER's execution path, what state it keeps, who
authorises its effects, and what reads that state after a crash. Mapped from
production call sites on 2026-10-26; a claim here names the file that makes it
true, so a change to that file is a change to this page.

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

### Fix::Kernel, FixLoop, RunJournal and RunLedger

Production boot in `lib/builder/ai_boot.rb` creates one `Fix::Kernel`.
The canonical class `Kernel::ConvergenceAdapter` is exposed to legacy callers as
`FixLoop`; its `run` delegates the outer execution lock and coordinator
lifecycle to Kernel. Kernel emits hash-chained start/terminal receipts with repair
outcomes correlated by run id. If a process dies before terminalization, the
next same-host run records `unknown_outcome` only after confirming the writer
is gone; a possibly-live peer is not declared finished. This is now a production
writer, not merely a replay reader.

The durable journal implementation is `Kernel::LifecycleJournal`, with the old
`RunJournal` constant retained as an alias. Kernel owns the single
`lifecycle_journal` accessor, and FixLoop plus the read-only
`Operator::FixStatus` use it. Its persisted schema and transaction/restart
semantics remain unchanged under `MASTER/.master/fix_runs.json`. Likewise,
`Kernel::RepairAdapter` is exposed as `RepairLoop` for compatibility. FixLoop
pass stages build repairs through Kernel and record bounded status/count outcomes;
the budget, collapse guard, and write-policy implementation remains grouped in
that nested adapter rather than copied into the Kernel's core methods.

FixLoop keeps `@transaction_root`, the root it was given, for transaction
recovery (2de776cde). RunLedger remains process memory reset at each run start.
Delivery is still the Committer: a commit per kept fix and a push, or one push at
the end.

### The inner repair loop

FixLoop's opportunity, visual, wishlist, improvement and per-Law stages now
build `RepairLoop` via `Kernel#build_repair_loop`. The adapter reports bounded
per-Law/status/count summaries to the same hash-chained Kernel ledger; it does
not write prompts or source text into that ledger. The actual write policy,
file budget, collapse guard, verifier, consensus panel, and transaction-bound
write implementation remain in RepairLoop and its collaborators for now.
WatchLoop builds none: a changed file wakes the background runner or starts an
incremental FixLoop run, so its repairs get a transaction and run ledger like
any other.

### Fix::Mission

Lifecycle, the background runner, the Supervisor, the TaskSteward and CoreBridge
build it. State is .master/mission.json under a lock and a lease. A handle that
claimed a mission may write only that mission while it holds the lease; any
other write raises Mission::Fenced (c296719e1). The Supervisor, Heartbeat and
TaskSteward read it and wake work whose lease expired. Two missions coexist: the
Fold's under MASTER's root and /fix's under the repository root
(FixLoop#mission_root); Kernel's execution lock and the transaction lock serialise /fix
writes. Heartbeat wakes /fix's, the TaskSteward tends the
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

1. Kernel owns the production coordinator, lock, receipts and factories. The
   implementation classes for loop convergence, journal lifecycle and repair
   policy are now nested as `Kernel::ConvergenceAdapter`,
   `Kernel::LifecycleJournal`, and `Kernel::RepairAdapter`; compatibility
   constants preserve existing callers. The subprocess regression
   `test/test_fix_interruption_restart.rb` is authored, but has not run on pinned
   Ruby 4.0.5 in this environment. Mission survival, journal-loss reconstruction,
   full adapter parity and the repository-wide `/fix` run remain evidence gates;
   see `docs/fix_coordinator_map.md`.
