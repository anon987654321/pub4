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

### FixLoop, RunJournal and RunLedger

ai_boot builds the FixLoop (in the background when MASTER_AUTOFIX=1) and the
/fix command builds one per run. FixLoop works on the repository root but keeps
@transaction_root, the root it was given, for transactions (2de776cde).
RunJournal persists runs in MASTER/.master/fix_runs.json with plan
generations and assessment receipts. RunLedger is process memory reset at each
run start. Delivery is the Committer: a commit per kept fix and a push, or one
push at the end.

### The inner repair loop

Pass stages build RepairLoop; it writes source with write_atomic inside the
pass transaction and relies on the reflexion verifier, the consensus panel, the
collapse guard and the Committer's path validation. WatchLoop builds none: a
changed file wakes the background runner or starts an incremental FixLoop run,
so its repairs get a transaction and a run ledger like any other.

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

1. Fix::Kernel is only the replay reader for .master/log.jsonl, and nothing
   in the runtime appends to that log, so `master replay` has no production
   history to read. FixLoop is the coordinator every /fix path enters;
   docs/fix_coordinator_map.md names the owner of each responsibility.
