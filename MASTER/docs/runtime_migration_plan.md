# Runtime Migration Plan

## Goal

Reduce MASTER from a large interconnected agent into a replayable cognitive runtime with explicit contracts.

## Immediate migration targets

### 1. Event sourcing

Current state:

- event bus exists
- telemetry exists
- audit log exists
- metrics exists

Problem:

- events are transient
- side effects happen outside durable runtime contracts
- replay is impossible

Migration:

- persist all event bus traffic to runtime/events/*.jsonl
- route audits and telemetry through runtime contracts
- add replay reconstruction

### 2. Provider routing

Current state:

- provider choice scattered across runtime
- direct model selection paths
- implicit escalation logic

Migration:

- centralize provider selection in orchestration/router
- score providers by latency, hallucination rate, failure rate, and cost
- quarantine degraded providers
- add quorum/voting strategies

### 3. Memory

Current state:

- mixed implicit memory
- command-specific state
- partial indexing

Migration:

- canonical memory
- episodic memory
- semantic memory
- compressed memory
- snapshot memory

### 4. Repair

Current state:

- rollback exists
- corruption checks exist
- scanner exists

Problem:

- repair logic is fragmented
- failures are not classified systematically

Migration:

- create repair classifiers
- digest failures continuously
- build reusable playbooks
- auto-quarantine unstable workflows

### 5. Contracts

Current state:

- tools execute directly
- retries vary by subsystem
- validation inconsistent

Migration:

- every tool gains declarative contract
- orchestration validates before execution
- side effects emit events
- retries standardized

## Simplification policy

Delete aggressively:

- duplicate orchestration layers
- duplicated registries
- mutable globals
- implicit fallback chains
- hidden retries
- provider-specific branches
- mixed runtime/UI state

## End state

MASTER becomes:

- resumable
- inspectable
- deterministic at orchestration layer
- probabilistic at cognition edge
- repair-oriented
- telemetry-native
- provider-agnostic
- replayable from event log
