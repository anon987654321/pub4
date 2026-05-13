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

## New subsystems

- `brain/providers/` declarative routing and provider capability registry.
- `brain/memory/` explicit memory tiers.
- `runtime/events/` append-only cognition/event stream.
- `runtime/telemetry/` failure, correction, latency, token, and context-pressure journals.
- `orchestration/router/` provider selection, voting, quorum, fallback, and scoring primitives.
- `repair/` classifiers, playbooks, validations, and quarantines.
- `tools/contracts/` typed tool execution contracts.

## Rollout order

1. Land file layout and policy files.
2. Route all model calls through provider policy.
3. Wrap tool execution with contracts and event logging.
4. Add failure digest and provider health jobs to heartbeat.
5. Add replay/checkpoint readers.
6. Add UI panels for event stream, provider health, context pressure, and repair queue.
