# MASTER Deletion and Addition Plan

This plan turns the cognitive-runtime refactor into concrete removals and additions.

## Delete or collapse

### Duplicate runtime truth

Remove any subsystem that stores workflow truth outside `runtime/events/`, `runtime/checkpoints/`, or explicit runtime state objects.

Target symptoms:

- hidden mutable globals
- ad hoc instance variables treated as durable memory
- UI-owned runtime state
- telemetry-only state with no event source

### Duplicate orchestration registries

Collapse command, tool, model, provider, and workflow registration toward one orchestration registry.

Keep local adapter registries only when they are pure lookup tables.

### Silent retries

Delete retry paths that do not emit:

- retry event
- failure event
- provider/tool involved
- final result

Retries without events make replay false.

### Provider-specific branching

Delete hard-coded provider preference branches from execution paths.

Provider choice belongs in:

```text
brain/providers/routing.yml
runtime/providers/*
orchestration/router/*
```

### Mixed telemetry sinks

Collapse telemetry into canonical NDJSON streams and derive dashboards from those streams.

Keep OpenTelemetry spans as optional external export, not canonical state.

### Legacy namespace drift

Reject stale constants through `Runtime::StaleNamespaceAudit` before boot/restart.

## Add or recover

### Runtime context pressure

`Runtime::ContextPressure` recovers the deleted cognitive monitor concept as infrastructure.

Use it for:

- context compaction triggers
- escalation signals
- UI entropy/confidence
- topology choice
- overload warnings

### Runtime experience scoring

`Runtime::Experience` recovers lost strategy scoring.

Use it for:

- tool plans
- repair playbooks
- provider routes
- workflow templates

### Stale namespace audit

`Runtime::StaleNamespaceAudit` prevents refactor regressions by scanning for old constants.

### Event contracts

Every side-effecting tool should declare:

- input schema
- output schema
- permissions
- timeout
- retry policy
- event emission
- validation

### Smoke gates

`exe/master-smoke` should become the mandatory gate after:

- refactors
- deploy script changes
- provider routing changes
- boot/container changes
- namespace moves

## First cleanup sequence

1. Run stale namespace audit.
2. Run smoke gate.
3. Replace provider-specific branches with routing policy reads.
4. Wrap tool side effects in runtime event contracts.
5. Move UI-only runtime state into runtime events.
6. Replace duplicate telemetry writes with canonical streams.
7. Add replay reader for workflow reconstruction.

## Success condition

A MASTER workflow can be reconstructed from events, smoke-tested after refactor, scored by experience, watched through context pressure, and repaired through explicit playbooks.
