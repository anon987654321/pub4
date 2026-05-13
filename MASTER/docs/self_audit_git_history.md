# MASTER Self-Audit and Git-History Mining

This file captures a MASTER-on-MASTER pass using the repository's own architectural rules: reduce duplication, restore valuable deleted logic, harden boot gates, and convert hidden state into replayable runtime events.

## Immediate audit result

MASTER already contains the runtime nucleus:

- `Master::Trace::EventBus` handles publish/subscribe and event pattern matching.
- `Master::Trace::Telemetry` wraps spans and trace emission.
- `Master.bootstrap_container` initializes telemetry, builds the container, snapshots boot state, and starts heartbeat.
- `exe/master-smoke` exists in history as a boot/wire/web/log gate.
- The seven-module refactor clarified domains but left some old logic behind.

The next move is consolidation.

## Lost or underused logic worth recovering

### 1. `exe/master-smoke`

History introduced a compact smoke gate that requires MASTER, bootstraps the container, checks builder output, verifies core wiring, optionally pings `/up`, and scans daemon logs for stale constant and method errors.

Action:

- keep `exe/master-smoke`
- add it to docs and deployment gates
- extend it to emit runtime events and telemetry
- make it the default post-refactor confidence check

### 2. `State::Experience`

A deleted test reveals useful lost logic: score tool-plan sequences by strategy signature, not exact arguments.

Recover as `Master::Runtime::Experience` and use it for tool-chain, provider-route, repair-playbook, and workflow-template scoring.

Preserve:

- argument-insensitive plan signatures
- decayed counts
- near-zero score for unseen plans

### 3. `CognitiveMonitor`

Deleted web tests show a lost cognitive-pressure model: load, flow_state, overload detection, reset with recent retention, context-switch tracking, and overload-risk state.

Recover as `Master::Runtime::ContextPressure`, not UI-only state.

Use it for context pressure telemetry, model-routing escalation, memory compaction triggers, visual entropy/confidence state, and topology selection.

### 4. Namespace audit

History repeatedly fixed stale namespace references after the seven-module refactor.

Permanent audit rules should catch old constants before runtime:

- `Master::CLI` -> `Master::Now::CLI`
- `Master::Pipeline` -> `Master::Now::Pipeline`
- `Master::Stages` -> `Master::Now::Stages`
- `Master::Speech` -> `Master::Voice::Speech`
- `Master::Personality` -> `Master::Voice::Personality`
- `Master::Swarm` -> `Master::Judge::Swarm`
- `Master::Scan` -> `Master::Judge::Scan`
- `Master::Council` -> `Master::Judge::Council`
- `Master::Session` -> `Master::Trace::Session`
- `Master::Axioms` -> `Master::Ground::Rules`

### 5. Visual runtime bridge

Recent history added a browser-side visual bridge that maps runtime events to entropy, confidence, topology, provider, and mode.

Keep DOM observers as fallback. Make `/events/stream` the primary data source.

## Critical streamlining recommendations

1. Collapse all runtime event concepts onto one event record shape.
2. Treat telemetry as derived from events where possible.
3. Use smoke plus namespace audit as hard gates after refactors.
4. Restore plan-experience scoring as provider/tool/workflow learning.
5. Restore cognitive monitor as context-pressure infrastructure.
6. Route visual entropy/confidence from runtime events, not UI guesses.
7. Add git-history mining as a recurring repair daemon task.

## Proposed recovery files

```text
MASTER/lib/master/runtime/context_pressure.rb
MASTER/lib/master/runtime/experience.rb
MASTER/lib/master/runtime/stale_namespace_audit.rb
MASTER/lib/master/runtime/event_record.rb
MASTER/lib/master/runtime/event_log.rb
MASTER/lib/master/repair/git_history_miner.rb
MASTER/data/stale_namespaces.yml
```

## Final diagnosis

MASTER's best lost logic is practical:

- smoke gates
- namespace audits
- plan experience scoring
- cognitive pressure tracking
- runtime visual bridge

Recover those into the new runtime spine before adding new model intelligence.
