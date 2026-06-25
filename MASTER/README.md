# MASTER

Constitutional AI runtime for any text artifact — code, prose, design, structure. Ruby. OpenBSD-first. Self-hosting.

Models propose. The constitution validates. Convergence loops digest violations. Memory learns what fixes stick. Pressure fields track epistemic health. Providers compete by capability, cost, and evidence.

The visual face (web UI particle system) is a live mirror of internal state (council, pipeline stages, pressure, topology). See `data/topologies.yml`, `data/visual_clusters.yml`, and `web/public/particle_kernel.js`.

## Quickstart

```sh
cd MASTER
bundle install
bundle exec ruby bin/cli
```

Pipe input for one-shot mode. The web face starts on port 53187 behind relayd at `https://ai.brgen.no`.

Deploy: `doas zsh DEPLOY/openbsd/openbsd.sh`

## Converge kernel

```ruby
require_relative "lib/converge"

engine = Converge::Engine.new("data/converge_rules.yml")
engine.subscribe { |event| warn(event.inspect) }
engine.run(code: "", reply_text: "plain reply")
```

The kernel canon lives at `data/converge_rules.yml`. The existing scanner corpus remains in `data/rules.yml`.

Core guarantees:

- rules run in dependency order
- convergence stops at a fixpoint or 16 cycles
- repeated state signatures are recorded as feedback loops
- every applied rule emits a runtime event
- runtime deltas are stored in `~/.master/state.db`

## Architecture

Four layers:

1. **Brain** — declarative constitution, standing orders, roles, memory policy, provider routing, governance.
2. **Runtime** — append-only events, telemetry, checkpoints, replay state, queues, locks, provider health, hot cache.
3. **Orchestration** — routing, voting, fallback, quorum, workflow execution, tool contracts, convergence loops.
4. **Interface** — CLI, web face, canvas, dashboard, traces, graph, timelines.

Eleven-stage turn pipeline: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Enhance rewrites user input for clarity and intent density with y/n approval in the web UI. Council and Lint run concurrently with a 30 s timeout.

### Convergence loop architectures

15 architectures across `loop/` — 14 implemented, 1 concept:

| # | Name | Status |
|---|------|--------|
| 1 | Priority queue over round-robin | implemented |
| 2 | Rule dependency graph (topological sort) | implemented |
| 3 | File-first convergence strategy | concept |
| 4 | Deterministic AST autofixes (Prism) | implemented |
| 5 | Unified diff output for large files | implemented |
| 6 | Council deliberation for severity:error | implemented |
| 7 | Reactive file watcher (kqueue/inotify) | implemented |
| 8 | Staged dataflow pipeline Detect→Apply | implemented |
| 9 | Genetic fix candidate selection | implemented |
| 10 | Reinforcement learning fix quality | implemented |
| 11 | Constitution as type system on AST IR | implemented |
| 12 | Datalog/Prolog rule engine | implemented |
| 13 | CRDT-based distributed convergence | implemented |
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
| Authenticated | `Authorization: Bearer`, `X-Token`, `master_session` cookie | Full — filesystem, git, all tools |
| Visitor | no credential | LLM chat only (`AskLlm`, `WebSearch`) |
| Public | `/up`, `/health` | Always |

First-hit `?token=…` is accepted only as a bootstrap handshake; the middleware sets an `HttpOnly; Secure; SameSite=Strict` cookie and 302s to the same path stripped of the token. After the handshake, the URL never carries the secret. No author name, vanity parameter, or other public query string grants authenticated access.

## Modules

`now` · `loop` · `judge` · `voice` · `ground` · `reach` · `trace` · `converge`

Constitution lives in `data/`. Runtime state in `.master/`. Knowledge store at `.master/knowledge.sqlite3`.

## Troubleshooting

**Bundler 403 on install**: proxy is blocking rubygems.org. Check `gem sources --list` and `env | grep -i proxy`. Install a single gem to isolate: `gem install zeitwerk -v 2.7.5`.

MIT.
