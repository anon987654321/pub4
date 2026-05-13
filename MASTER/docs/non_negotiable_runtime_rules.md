# Non-Negotiable Runtime Rules

## Core invariants

1. No agent directly mutates durable state.
2. Every side effect emits runtime events.
3. Replay reconstructs workflows without model memory.
4. Tool execution requires contract validation.
5. Telemetry is append-only unless compacted through policy.
6. Repair consumes failures as first-class runtime input.
7. Providers are runtime resources, not personalities.
8. Expensive cognition is reserved for high-risk decisions.
9. Rollback beats narration.
10. Deterministic orchestration beats hidden heuristics.

## Anti-patterns

Forbidden:

- hidden retries
- mutable globals
- provider-specific orchestration branches
- implicit state mutation
- silent fallbacks
- direct shell execution without contract
- model-selected providers
- unverifiable side effects
- memory as source of truth
- UI coupled to orchestration state

## Runtime philosophy

Models are probabilistic cognition edges.

The runtime is the operating system.

The orchestrator owns truth.
