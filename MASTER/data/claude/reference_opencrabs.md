---
name: OpenCrabs (Rust MASTER cousin)
description: github.com/adolfousier/opencrabs — Rust/Ratatui TUI agent, philosophical cousin of MASTER. ~803 stars, MIT. Worth-stealing patterns listed with MASTER wiring status.
type: reference
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
**Repo:** [opencrabs](https://github.com/adolfousier/opencrabs) · [docs](https://docs.opencrabs.com) · v0.3.47 (Jun 2026) · 4k+ tests · Linux/macOS/Windows; no OpenBSD/`pledge`.
**Architecture:** TUI/CLI → Brain → Services → SQLx/SQLite → LLM providers (Rust + Tokio + Ratatui).

**Wired in MASTER (2026-06-24):** brain-files re-read (`data/*.yml`, `Ground::BrainOverlay`); FTS5 BM25 memory; inline compaction (`ContextWindow`, web SSE, daily log); `/rebuild` hot-restart; sub-agent tool exclusion (`SubagentPolicy`, `AgentPool`, swarm); typed sub-agents (`agent_taxonomy.yml`, `/btw`); hashline edits (`Reach::Hashline`); RTK output filter (`/rtk`); plan pinning (`Ground::ActivePlan`); mission dashboard (`/dashboard`); phantom recovery; skills slash triggers (`Now::Skills#trigger_for`); soft/hard compaction 65%/90%; per-model quota (`Ground::ModelQuota`); prompt-cache card (`Trace::CacheEfficiency`, `/chat/metrics`); OpenRouter key rotation (`Ground::KeyRotator`); unified health (`bin/doctor`, `/doctor`).

**OpenCrabs gaps:** high — OAuth-before-key auth rotation, `self_improve` brain writes, NL `config_manager`; medium — offline STT/TTS, multi-channel inbox, cron DSL, dynamic `tools.toml`, video/PDF multimodal, usage categorization; low — A2A RPC, `zeroize` key hygiene, upstream brain sync.

**OpenClaw** ([openclaw/openclaw](https://github.com/openclaw/openclaw), 355k+ stars, [docs](https://docs.openclaw.ai)): MASTER partial on model failover (`KeyRotator`, `ModelRouter` — missing OAuth/cooldown tiers), `/doctor` (missing DM/sandbox audit), session tools (`/btw` partial), DM pairing, Docker sandbox, ClawHub registry, Live Canvas/A2UI, Voice Wake, chat commands subset, webhook/cron ingress, fallback skip TTL cache.

**Similar repos:** [OpenHands](https://github.com/All-Hands-AI/OpenHands) sandbox GUI; [Aider](https://github.com/Aider-AI/aider) repo map (`GitContext`, `CodeIndex` partial); [SWE-agent](https://github.com/SWE-agent/SWE-agent) issue→patch (`/fix` partial); [crewAI](https://github.com/crewAIInc/crewAI) roles (council+swarm partial); [nekro-agent](https://github.com/KroMiose/nekro-agent) chat sandbox; [OpenClaw-RL](https://github.com/Gen-Verse/OpenClaw-RL) online RL (`FeedbackLedger` only). Clusters: `patterns.yml` — `openclaw_like_personal_agents`, `bleeding_edge_experimental_repos`, `agi_agent_ecosystem`.

**Risks:** unapproved RSI brain writes; hallucinated tools in corrupted sessions; bus factor 1; headless web-chat ToS (`ROUTING_REARCHITECTURE.md` §6). Don't conflate `mo-vic/OpenCrab` (distillation) or empty `opencrab` org.