---
name: OpenCrabs (Rust MASTER cousin)
description: github.com/adolfousier/opencrabs — Rust/Ratatui TUI agent, philosophical cousin of MASTER. ~803 stars, MIT. Worth-stealing patterns listed with MASTER wiring status.
type: reference
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
**Repo:** [github.com/adolfousier/opencrabs](https://github.com/adolfousier/opencrabs) · [docs.opencrabs.com](https://docs.opencrabs.com) · v0.3.47 (Jun 2026) · 4k+ tests · Linux/macOS/Windows; no OpenBSD/`pledge`.

**Architecture:** TUI/CLI → Brain → Services → SQLx/SQLite → LLM providers. Layered Rust + Tokio + Ratatui.

**Patterns worth stealing — MASTER wiring (2026-06-24):**

| # | Pattern | MASTER status |
|---|---------|---------------|
| 1 | Brain-files re-read every turn | `data/*.yml` + `Ground::BrainOverlay` — wired |
| 2 | FTS5 BM25 memory | `ground/memory.rb`, `memory_search.rb` — wired |
| 3 | Inline compaction summary | `ContextWindow` + web SSE `compaction:` + daily log — wired |
| 4 | `/rebuild` hot-restart | CLI `run_rebuild`; web `/rebuild` → `tmp/restart.txt` — wired |
| 5 | Sub-agent tool exclusion | `SubagentPolicy` + `SubagentContext` + `AgentPool` + swarm — wired |
| 6 | Typed sub-agents (`explore/plan/code/research`) | `data/agent_taxonomy.yml` + `/btw` — wired |
| 7 | Hashline-anchored edits | `Reach::Hashline` + `read_file(hashline:)` — wired |
| 8 | RTK token savings on shell output | `Reach::OutputFilter` + `/rtk` — wired |
| 9 | Plan pinning each turn | `Ground::ActivePlan` + `propose_tree:done` — wired |
| 10 | Mission control dashboard | `/dashboard` RSI/RTK/plan/bus — wired |
| 11 | Phantom/gaslighting recovery | `PhantomRecovery` + web glitch badge — wired |
| 12 | Skills as slash triggers | `Now::Skills#trigger_for` in Enhance stage — wired |

**Risks (don't blindly copy):** unapproved RSI brain writes; hallucinated tool calls in corrupted sessions; bus factor 1.

**Don't conflate:** `mo-vic/OpenCrab` (distillation) and empty `opencrab` org are unrelated.