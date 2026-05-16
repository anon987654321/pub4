# MASTER

Constitutional AI runtime for any text artifact — code, prose, design, structure. Ruby. OpenBSD. Self-hosting.

Models propose. The constitution validates. Convergence loops digest violations. Memory learns what fixes stick. Pressure fields track epistemic health. Providers compete by capability, cost, and evidence.

## Quickstart

```sh
cd MASTER
bundle install
bundle exec ruby exe/master
```

Pipe input for one-shot mode. The web face starts on port 53187 behind relayd at `https://ai.brgen.no`.

Deploy: `doas zsh DEPLOY/openbsd/openbsd.sh`

## Architecture

Four layers:

1. **Brain** — declarative constitution, standing orders, roles, memory policy, provider routing, governance.
2. **Runtime** — append-only events, telemetry, checkpoints, replay state, queues, locks, provider health, hot cache.
3. **Orchestration** — routing, voting, fallback, quorum, workflow execution, tool contracts, convergence loops.
4. **Interface** — CLI, web face, canvas, dashboard, traces, graph, timelines.

Ten-stage turn pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run concurrently with a 30 s timeout.

### Convergence loop architectures

15 architectures across `loop/` — 11 implemented, 4 scaffolded:

| # | Name | Status |
|---|------|--------|
| 1 | Priority queue over round-robin | implemented |
| 2 | Rule dependency graph (topological sort) | implemented |
| 3 | File-first convergence strategy | implemented |
| 4 | Deterministic AST autofixes (Prism) | implemented |
| 5 | Unified diff output for large files | implemented |
| 6 | Council deliberation for severity:error | implemented |
| 7 | Reactive file watcher (kqueue/inotify) | scaffolded |
| 8 | Staged dataflow pipeline Detect→Apply | implemented |
| 9 | Genetic fix candidate selection | implemented |
| 10 | Reinforcement learning fix quality | implemented |
| 11 | Constitution as type system on AST IR | scaffolded |
| 12 | Datalog/Prolog rule engine | scaffolded |
| 13 | CRDT-based distributed convergence | scaffolded |
| 14 | Hierarchical Bayesian violation priors | implemented |
| 15 | Codebase as embodied particle topology | implemented |

## Operating law

- Agents do not directly mutate durable state.
- Tools declare contracts before execution.
- Every action emits before/after events.
- Provider calls pass through routing policy.
- Telemetry is append-only JSONL.
- Memory has explicit lifecycle tiers.
- Rollback beats explanation.
- Replay beats trust.

## Repair

```
observe → classify → propose → sandbox → validate → merge
```

Failures become data. Data becomes playbooks. Playbooks become safer defaults.

## Configuration

| Key | Default | Description |
|---|---|---|
| `model` | `openrouter/auto` | Default provider model |
| `budget_max` | `10.0` | Max spend per session (USD) |
| `req_max` | `1.0` | Max spend per request (USD) |
| `reasoning_mode` | `direct` | `direct` or `chain` |
| `auto` | `false` | Autoloop enabled |
| `trace` | `0` | Trace verbosity (0–3) |
| `cache_ttl` | `3600` | Cache TTL in seconds |

Config lives at `.master/config.yml`. Override any key at runtime with `/config key value`.

## Web auth

| Tier | Trigger | Access |
|---|---|---|
| Authenticated | `?token=…` | Full — filesystem, git, all tools |
| Visitor | no token | LLM chat only (`AskLlm`, `WebSearch`) |
| Public | `/up`, `/health` | Always |

## Modules

`now` · `loop` · `judge` · `voice` · `ground` · `reach` · `trace`

Constitution lives in `data/`. Runtime state in `.master/`. Knowledge store at `.master/knowledge.sqlite3`.

## Troubleshooting

**Bundler 403 on install**: proxy is blocking rubygems.org. Check `gem sources --list` and `env | grep -i proxy`. Install a single gem to isolate: `gem install zeitwerk -v 2.7.5`.

MIT.
