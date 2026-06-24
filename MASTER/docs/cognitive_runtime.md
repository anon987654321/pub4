# MASTER Cognitive Runtime

MASTER now has a concrete adoption path for the OpenCrabs/OpenClaw concepts captured in `Master Concept Adoption.pdf`.

The target shape is not another prompt layer. The target shape is an event-sourced cognitive runtime:

- models propose intents
- the orchestrator validates intents
- every decision and mutation is appended to disk
- providers are scored and quarantined
- memory is tiered and compacted
- failures become repair input
- workflows can be replayed from checkpoints

## First-class invariants

1. Agents do not directly mutate durable state.
2. Every external action emits an event before and after execution.
3. Provider calls are routed through capability, health, cost, and fallback policy.
4. Telemetry is append-only JSONL unless explicitly compacted.
5. Memory moves through canonical, episodic, semantic, compressed, and snapshot tiers.
6. Repair follows observe -> classify -> propose -> sandbox -> validate -> merge.
7. Tool contracts define inputs, outputs, permissions, retries, timeout, and validation.
8. Git history is mined as repair memory, not treated as dead text.
9. Context pressure is measured before escalation, compaction, or topology changes.

## Landed subsystems

- `brain/providers/routing.yml` declarative provider routing and fallback policy.
- `runtime/events/` append-only cognition/event stream documentation.
- `runtime/telemetry/` failure, correction, latency, token, and context-pressure journals.
- `runtime/context_pressure.rb` recovered cognitive-pressure tracking.
- `runtime/experience.rb` recovered plan/provider/tool-route scoring.
- `runtime/event_record.rb` canonical event record primitive.
- `runtime/replay_reader.rb` replay reader for JSONL event streams.
- `runtime/stale_namespace_audit.rb` permanent post-refactor namespace drift scanner.
- `repair/git_history_miner.rb` commit-history mining for lost repair logic.
- `tools/contracts/runtime_event.yml` contract for append-only event emission.
- `data/stale_namespaces.yml` migration registry for stale constants.

## Runtime spine

```text
workflow
  -> event record
  -> append-only stream
  -> replay reader
  -> telemetry derivation
  -> repair learning
  -> provider scoring
  -> orchestration refinement
```

## Rollout order

1. Land runtime primitives and policy files.
2. Make smoke and stale-namespace audit hard refactor gates.
3. Route all model calls through provider policy.
4. Wrap tool execution with contracts and event logging.
5. Add failure digest and provider health jobs to heartbeat.
6. Add checkpoint/replay reconstruction for full workflows.
7. Feed visual bridge from canonical runtime events.
8. UI panels for event stream, provider health, context pressure, and repair queue — wired in `/dashboard` (2026-06-24) via `Trace::ContextPressure` + `dashboard/live` JSON.

## Deletion pressure

Delete or collapse anything that creates competing runtime truth:

- silent retries
- hidden mutable globals
- provider-specific execution branches
- duplicate registries
- telemetry-only state
- UI-owned runtime state
- stale namespace compatibility shims
