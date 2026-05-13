# Runtime Event Streams

MASTER runtime events are append-only JSONL streams.

Streams:

- activity.jsonl
- decisions.jsonl
- mutations.jsonl
- workflows.jsonl
- providers.jsonl
- repair.jsonl

## Principles

- events are immutable
- replay reconstructs workflow state
- orchestration trusts events over memory
- repair consumes failures as input
- telemetry and audit derive from runtime events

## Record shape

```json
{
  "id": "uuid",
  "timestamp": "2026-01-01T00:00:00.000000Z",
  "event": "tool:after",
  "payload": {}
}
```

## Usage

Every subsystem emits:

- before events
- after events
- failure events
- retry events
- quarantine events
- rollback events

## Long-term direction

Runtime events become the canonical substrate for:

- replay
- debugging
- observability
- memory reconstruction
- workflow analytics
- repair learning
- provider scoring
- autonomous planning
