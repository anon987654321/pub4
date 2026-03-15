# MASTER2 10/10 Masterpiece Roadmap

This document proposes high-impact changes to make MASTER2 an architectural and software-engineering reference system.

## North-star definition

A 10/10 MASTER2 should be:

1. **Predictable**: same input class, same safety and quality envelope.
2. **Auditable**: every decision has evidence, cost, and risk trace.
3. **Self-healing**: failures degrade gracefully and trigger corrective loops.
4. **Composable**: modules are independently evolvable and testable.
5. **Operator-grade**: SLO-driven with explicit runbooks and rollback paths.

## Priority 0 — confidence and correctness rails

### 1) Add a deterministic planning layer before execution
- Introduce `plan` as a first-class stage between `route` and `execute`.
- Require execution to reference a signed plan object (`plan_id`, constraints, expected artifacts).
- Reject action if plan and execution diverge outside tolerance.

**Why**
- Prevents silent strategy drift.
- Makes behavior reproducible under stress.

### 2) Build a formal safety policy engine
- Move safety checks from distributed ad hoc conditions into one policy interpreter.
- Policies compile from YAML into executable predicates with versioning.
- Log allow/deny with reason codes.

**Why**
- One source of truth for safety and governance.
- Enables audits and safe policy rollouts.

### 3) Establish quality gates as code
- Add mandatory gates: syntax, tests, static analysis, security lint, architectural rules.
- Gate verdicts become machine-readable (`pass`, `warn`, `fail`, override token).

**Why**
- Ensures quality is enforced uniformly instead of socially.

## Priority 1 — architecture hardening

### 4) Convert pipeline to an explicit state machine
Define stable states and transitions:
`intake -> guard -> route -> plan -> execute -> verify -> lint -> render -> persist`

Rules:
- Every transition writes an event.
- Illegal transitions are impossible by construction.
- Crash recovery resumes from last valid state.

### 5) Introduce domain boundaries and ports/adapters
Refactor into bounded contexts:
- `Core::Policy`
- `Core::Pipeline`
- `Core::ModelRouting`
- `Core::Session`
- `Core::Review`

Adapters:
- providers (Replicate/OpenRouter)
- storage (files/jsonl/sqlite)
- transport (CLI/SSE/web)

### 6) Create a canonical event log
- Append-only event stream with typed schemas.
- Each turn emits decision events, tool events, guard events, cost events.
- Derived views power UI, replay, and analytics.

## Priority 2 — reliability and operations

### 7) Define SLOs and error budgets
Recommended initial SLOs:
- command success rate >= 99.0%
- median response latency <= 2.5s (routing-only), <= 12s (tool path)
- safety-policy false negative rate <= 0.1%

### 8) Add resilience patterns
- Per-provider circuit breaker with half-open probes.
- Bulkhead isolation by subsystem (LLM, filesystem, web UI).
- Adaptive retry with jitter and idempotency keys.

### 9) Ship production runbooks
Runbooks for:
- provider outage
- malformed policy deployment
- latency regression
- corrupted session replay

## Priority 3 — developer experience and speed

### 10) Standardize architecture decision records (ADRs)
- Add `/docs/adr` with lightweight template.
- All cross-cutting changes require an ADR.

### 11) Introduce contract tests for every boundary
- Provider adapter contracts.
- Pipeline state-transition contracts.
- Policy-engine fixture matrix.

### 12) Add a system scorecard command
`master scorecard` should report:
- SLO status
- quality gate pass rate
- policy override counts
- model routing efficiency
- open architectural debt items

## Proposed phased execution

### Phase 1 (Weeks 1-2): safety + planning
- Add `plan` stage and policy engine skeleton.
- Introduce event schema and transition IDs.
- Add baseline contract tests.

### Phase 2 (Weeks 3-4): state machine + reliability
- Transition pipeline to strict state machine.
- Integrate circuit breakers and bulkheads.
- Begin SLO telemetry.

### Phase 3 (Weeks 5-6): governance + scorecard
- ADR workflow enforced.
- Runbooks complete.
- Launch `master scorecard`.

## Objective acceptance criteria for “10/10 trajectory”

1. 100% of turns have replayable event traces.
2. 0 critical safety checks outside the policy engine.
3. >= 95% of boundary modules protected by contract tests.
4. All production incidents map to a runbook within 5 minutes.
5. Architectural decisions for major changes recorded as ADRs.

## Suggested initial implementation map

- `lib/pipeline/` -> state machine + plan stage
- `lib/policy/` -> policy compiler + evaluator + reasons
- `lib/events/` -> event envelope + schema validation + append log
- `test/contracts/` -> adapter and transition contracts
- `docs/adr/` -> ADR templates and decisions
- `bin/master` -> `scorecard` command integration

This roadmap prioritizes safety, determinism, and operational excellence first, then scales velocity with governance and contracts.
