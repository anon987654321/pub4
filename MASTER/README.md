# MASTER

Constitutional AI runtime for text and code artifacts. Ruby. OpenBSD. Self-hosting.

MASTER is moving from smart CLI to cognitive runtime. Models propose. The orchestrator validates. Events record the truth. Repair loops digest failure. Memory compacts without forgetting. Providers compete by capability, cost, health, and evidence.

## Runtime shape

The system has four hard layers.

1. **Brain** — declarative constitution, standing orders, roles, memory policy, provider routing, and governance.
2. **Runtime** — append-only events, telemetry, checkpoints, replay state, queues, locks, provider health, and hot cache.
3. **Orchestration** — routing, voting, fallback, quorum, workflow execution, tool contracts, and repair loops.
4. **Interface** — CLI, web face, canvas, dashboard, traces, graph, and timelines.

The old ten-stage turn pipeline still exists: Intake, Infer, Route, Guard, Execute, Council and Lint in parallel, Prune, Memo, Render. The new runtime wraps it. Every stage emits structured events. Durable state changes pass through contracts. A failed contract enters repair, not narration.

## Operating law

- agents do not directly mutate durable state
- tools declare contracts before execution
- every action emits before/after events
- provider calls pass through routing policy
- telemetry is append-only JSONL
- memory has explicit lifecycle tiers
- rollback beats explanation
- replay beats trust

## Brain

`data/` remains the legacy constitution store. `brain/` becomes the live cognitive filesystem:

- `brain/providers/` — capability, routing, health, fallback, and cost policy
- `brain/memory/` — canonical, episodic, semantic, compressed, and snapshot tiers
- `brain/governance/` — mutation, approval, rollback, and escalation policy
- `brain/cognition/` — planner, critic, compressor, retriever, reviewer, patcher, synthesizer roles

The agent is still config. The config is now modular, hot-readable, and operational.

## Runtime

`runtime/` owns state:

- `runtime/events/` records activity, decisions, mutations, and replay checkpoints
- `runtime/telemetry/` records failures, corrections, hallucinations, retries, provider latency, token usage, context pressure, and tool calls
- `runtime/providers/` records live provider health, cooldowns, quarantines, and routing cache
- `runtime/checkpoints/` stores resumable workflow state
- `runtime/replay/` reconstructs a workflow from events

No critical behavior depends on a model remembering what happened. The event stream remembers.

## Orchestration

`orchestration/` turns cognition into controlled execution:

- route by task, capability, health, cost, and risk
- use cheap models for classification, compression, retrieval, critique, and voting
- reserve expensive models for high-risk synthesis and irreversible decisions
- validate structured outputs before side effects
- quarantine providers and tools that degrade
- retry through fallback chains with bounded cost

## Repair

Repair is a loop:

```text
observe -> classify -> propose -> sandbox -> validate -> merge
```

Failures become data. Data becomes playbooks. Playbooks become safer defaults.

## Scanner and sweep

The scanner still sweeps the tree in parallel, applies Prism-AST rules, regex rules, repo-graph mining, registry checks, semantic LLM review, visual shape checks, comment-drift checks, and co-change analysis. Sweep still prefers deterministic tools first, then surgical model edits, then guards and rollback.

The runtime adds memory, events, telemetry, provider scoring, and replay around that existing engine.

## Canvas

The live canvas remains the OpenClaw inheritance. It should render violations, fixes, council rounds, provider health, repair queue, event replay, memory compaction, context pressure, and workflow topology.

## Launch

From the project root:

```sh
bundle exec ruby exe/master
```

Pipe input through stdin for one-shot mode. The Rails 8 web face listens on 53187 behind relayd.

Deploy through `DEPLOY/openbsd/openbsd.sh`.

MIT.

## Debug note: Bundler and proxy 403s

If `bundle install` fails with `Gem::Net::HTTPClientException: 403 "Forbidden"` in containerized environments, verify proxy wiring before debugging MASTER itself. Rubygems requests routed through a blocking proxy fail before app boot.

Fast checks:

- `gem sources --list` should include `https://rubygems.org/`.
- `env | rg -i 'proxy|rubygems|bundle'` should reveal active proxy variables.
- `gem install zeitwerk -v 2.7.5` isolates network/proxy failure from MASTER code.

Treat this as infrastructure breakage unless gems install cleanly and MASTER still fails to boot.
