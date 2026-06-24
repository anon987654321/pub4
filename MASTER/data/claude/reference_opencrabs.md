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
| 13 | Soft/hard auto-compaction (65%/90%) | `ContextWindow` soft thread + hard sync — wired 2026-06-24 |
| 14 | Per-model daily quota (free tier) | `Ground::ModelQuota` + router skip — wired 2026-06-24 |
| 15 | Prompt-cache efficiency card | `Trace::CacheEfficiency` + `/chat/metrics` + dashboard — wired 2026-06-24 |
| 16 | Multi-key OpenRouter rotation | `Ground::KeyRotator` on rate-limit/quota — wired |
| 17 | Unified health audit | `bin/doctor` + `/doctor` — wired 2026-06-24 |

**OpenCrabs gaps — not yet in MASTER:**

| Priority | Pattern | Notes |
|----------|---------|-------|
| high | Auth profile rotation (OAuth before API keys) | OpenClaw parity; LRU + cooldown; session-pinned |
| high | `self_improve` approved brain writes | RSI ledger exists; no auto-write path |
| high | NL config edits (`config_manager`) | infer promotes commands; no NL write tool |
| medium | Native offline STT/TTS (whisper.cpp, Piper) | Edge TTS + browser fallback only |
| medium | Multi-channel inbox (Telegram, WhatsApp) | web+CLI only |
| medium | Cron + heartbeats DSL | standing orders exist; no cron.toml |
| medium | Dynamic tools (`tools.toml` hot-reload) | `data/tools.yml` static |
| medium | Video/PDF multimodal (`analyze_video`, poppler) | image path only |
| medium | Usage dashboard activity categorization | partial `/dashboard`; no session labels |
| low | A2A protocol (inter-agent RPC) | no cross-MASTER spawn |
| low | `zeroize` API key hygiene | env/files only |
| low | Upstream brain template sync | manual `data/*.yml` edits |

---

## OpenClaw ([openclaw/openclaw](https://github.com/openclaw/openclaw))

Gateway-centric personal agent (355k+ stars). Docs: [docs.openclaw.ai](https://docs.openclaw.ai).

**Patterns MASTER should steal:**

| Pattern | OpenClaw source | MASTER gap |
|---------|-----------------|------------|
| Model failover (auth rotate → model chain) | [model-failover](https://docs.openclaw.ai/concepts/model-failover) | partial — `KeyRotator` + `ModelRouter`; missing OAuth profiles, cooldown backoff tiers |
| `openclaw doctor` security audit | [gateway/doctor](https://docs.openclaw.ai/gateway/doctor) | `/doctor` covers deps/keys/quota/cache; missing DM policy, sandbox audit |
| Session tools (`sessions_spawn`, `sessions_send`) | gateway session API | session/history only; `/btw` subagents partial |
| DM pairing / allowlists (`dmPolicy=pairing`) | [gateway/security](https://docs.openclaw.ai/gateway/security) | web token auth only |
| Sandbox modes (Docker/non-main isolation) | gateway config | governor only; no container sandbox |
| ClawHub skills registry | external hub | `data/skills/` local only |
| Live Canvas / A2UI workspace | companion protocol | particle face; no agent canvas protocol |
| Voice Wake + Talk Mode | mobile nodes | PTT/STT stub |
| Chat commands (`/compact`, `/think`, `/usage`) | channel commands | subset via infer + registry |
| Webhook/cron automation ingress | gateway cron | standing orders; no webhook ingress |
| Fallback skip TTL cache | `OPENCLAW_FALLBACK_SKIP_TTL_MS` | not implemented |

---

## Similar repos to mine

| Repo | Steal-worthy | MASTER status |
|------|--------------|---------------|
| [OpenHands](https://github.com/All-Hands-AI/OpenHands) | sandboxed dev env, GUI | governor only |
| [Aider](https://github.com/Aider-AI/aider) | git-centric repo map | `GitContext`, `CodeIndex` partial |
| [SWE-agent](https://github.com/SWE-agent/SWE-agent) | issue→patch harness | `/fix` loop partial |
| [crewAI](https://github.com/crewAIInc/crewAI) | role-based workflows | council + swarm partial |
| [nekro-agent](https://github.com/KroMiose/nekro-agent) | chat-platform sandbox | not wired |
| [OpenClaw-RL](https://github.com/Gen-Verse/OpenClaw-RL) | online RL from tool/GUI signals | `FeedbackLedger` only |

Clusters in `data/patterns.yml`: `openclaw_like_personal_agents`, `bleeding_edge_experimental_repos`, `agi_agent_ecosystem`.

**Risks (don't blindly copy):** unapproved RSI brain writes; hallucinated tool calls in corrupted sessions; bus factor 1; headless web-chat ToS (see `ROUTING_REARCHITECTURE.md` §6).

**Don't conflate:** `mo-vic/OpenCrab` (distillation) and empty `opencrab` org are unrelated.