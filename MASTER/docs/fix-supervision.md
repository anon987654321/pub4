# Durable /fix supervision

MASTER treats a long-running `/fix` objective as durable work, not as an immortal
Ruby call stack.

The rule is simple: **the mission is durable; the attempt is bounded.**

A `/fix <target>` mission is persisted under `.master/mission.json`. A single
`FixLoop#run` remains bounded by its pass and wall-clock budgets. When the attempt
finishes without proving completion, the mission remains resumable and receives a
next wake time. When the process dies, the next MASTER process reclaims an expired
lease and continues the same objective.

## Lifecycle

`/fix <target>`
→ create or resume mission
→ acquire lease
→ run one bounded FixLoop attempt
→ persist the result
→ complete, block, or defer
→ wake again when due

`FixLoop` remains the repair engine. `Supervisor` owns lifetime.

`WatchLoop` does not start a second fix execution when the supervisor is active.
A file event becomes a mission wake request. Heartbeat is a reconciliation/wakeup
mechanism, not a second autonomous repair engine.

## Durable mission state

The mission record contains the objective and the information required to resume:

- goal and scope
- model and effort
- current stage and plan
- attempt and retry counts
- checkpoint and artifacts
- next wake time and wake reason
- lease owner and lease expiry
- last-seen and completion/error state

A wake received during an active attempt is latched as `wake_requested`. It is
converted into a fresh waiting state after that attempt finishes instead of
interrupting a transaction halfway through.

## Recovery

A worker owns a short lease. A live lease prevents another worker from claiming
the mission. An expired lease is reclaimable.

Transient failure is deferred with exponential backoff up to one hour. A blocked
mission remains blocked until a human or an explicit `/fix` request changes it.
A successful convergence is the only path that records the mission as completed.

This makes process restart cheap:

1. OpenBSD or another supervisor starts MASTER.
2. MASTER reads the mission record.
3. An expired running lease is reclaimed.
4. The next bounded attempt resumes the objective.
5. No source content has to be reconstructed from the mission record; Git,
   transaction manifests and checkpoints remain the content sources of truth.

## Event sources

The supervisor can sleep until the next durable wake time and can be woken early
by an event.

Relevant events include source changes, provider recovery, resource recovery,
manual requests and other runtime signals that mean “reconsider this mission”.

The event source never becomes a second scheduler. It only wakes the single
authoritative supervisor.

## Configuration

`MASTER/data/limits.yml#autoloop.poll_interval` controls the supervisor's maximum
poll interval. There is no `max_cycles` lifetime bound for autonomous missions.

Pass limits and run budgets remain deliberate circuit breakers. They bound one
attempt; they do not claim that the mission is finished.

## Operational meaning

`DONE` means the existing FixLoop verification and ground-truth gates proved the
objective.

`WAITING` means the objective still exists and has a future wake.

`BLOCKED` means MASTER has deliberately stopped autonomous progress.

`FAILED` means the attempt or mission recorded an unrecoverable error.

None of these states is inferred from a dead process. Process death is an
execution failure to recover from, not a declaration that the objective vanished.
