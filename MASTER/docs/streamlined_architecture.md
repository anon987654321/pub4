# Streamlined MASTER Architecture

## Problem

MASTER accumulated overlapping abstractions:

- pipeline logic
- orchestration logic
- council logic
- scanner logic
- provider logic
- telemetry logic
- command registry logic
- memory logic
- canvas logic

The result trends toward conceptual duplication and cognitive drag.

## Principle

MASTER needs fewer concepts with stronger boundaries.

Everything reduces to:

1. event
2. workflow
3. contract
4. memory
5. provider
6. repair

## Canonical topology

```text
brain/
runtime/
orchestration/
repair/
tools/
interface/
```

Everything else becomes subordinate.

## brain/

Pure declarative cognition.

Contains:

- constitution
- governance
- provider policy
- role definitions
- memory policy
- workflow templates
- heuristics
- repair playbooks

No side effects.

## runtime/

Pure state.

Contains:

- events
- telemetry
- queues
- replay
- checkpoints
- provider health
- caches
- leases
- snapshots

No orchestration decisions.

## orchestration/

Pure execution control.

Contains:

- routing
- workflow execution
- quorum
- retries
- voting
- fallback
- validation
- scheduling
- coordination

No direct persistence outside runtime contracts.

## repair/

Self-healing subsystem.

Contains:

- classifiers
- quarantine
- drift analysis
- corruption checks
- repair plans
- rollback heuristics
- failure digesters

Repair owns resilience.

## tools/

Every tool becomes contract-driven.

Every tool declares:

- inputs
- outputs
- permissions
- timeout
- retries
- sandbox requirements
- validation
- side effects

Tool execution emits runtime events.

## interface/

Everything user-facing:

- CLI
- web
- canvas
- traces
- dashboards
- graph
- replay visualizer

Interface never mutates core runtime directly.

## Deletion targets

The current system should aggressively collapse:

- duplicate registries
- overlapping scanners
- hidden side effects
- model-specific orchestration branches
- implicit mutable globals
- magic fallback behavior
- silent retries
- mixed telemetry formats
- coupled UI/runtime state

## Desired outcome

MASTER becomes:

- replayable
- inspectable
- resumable
- provider-agnostic
- repair-oriented
- deterministic at orchestration level
- probabilistic only at cognition edges
