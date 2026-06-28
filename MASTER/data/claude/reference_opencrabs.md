---
name: OpenCrabs (Rust MASTER cousin)
description: github.com/adolfousier/opencrabs — Rust/Ratatui TUI agent, philosophical cousin of MASTER. ~803 stars, MIT. Worth-stealing patterns listed with MASTER wiring status.
type: reference
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---

OpenCrabs is the Rust cousin of MASTER—[opencrabs](https://github.com/adolfousier/opencrabs) with [docs](https://docs.opencrabs.com), v0.3.47 as of June 2026, four thousand plus tests, MIT license, roughly eight hundred stars. It targets Linux, macOS, and Windows; it does not support OpenBSD or `pledge`. Architecture is TUI/CLI → Brain → Services → SQLx/SQLite → LLM providers, built with Rust, Tokio, and Ratatui.

As of 2026-06-24, MASTER wired brain-files re-read (`data/*.yml`, `Ground::BrainOverlay`); FTS5 BM25 memory; inline compaction via `ContextWindow`, web SSE, and daily log; `/rebuild` hot-restart; sub-agent tool exclusion (`SubagentPolicy`, `AgentPool`, swarm); typed sub-agents (`agent_taxonomy.yml`, `/btw`); hashline edits (`Reach::Hashline`); RTK output filter (`/rtk`); plan pinning (`Ground::ActivePlan`); mission dashboard (`/dashboard`); phantom recovery; skills slash triggers (`Now::Skills#trigger_for`); soft and hard compaction at 65% and 90%; per-model quota (`Ground::ModelQuota`); prompt-cache card (`Trace::CacheEfficiency`, `/chat/metrics`); OpenRouter key rotation (`Ground::KeyRotator`); and unified health (`bin/doctor`, `/doctor`).

OpenCrabs gaps remain: high priority for OAuth-before-key auth rotation, `self_improve` brain writes, and NL `config_manager`; medium for offline STT/TTS, multi-channel inbox, cron DSL, dynamic `tools.toml`, video and PDF multimodal, and usage categorization; low for A2A RPC, `zeroize` key hygiene, and upstream brain sync.

OpenClaw ([openclaw/openclaw](https://github.com/openclaw/openclaw), 355k+ stars, [docs](https://docs.openclaw.ai)) overlaps partially: MASTER has model failover via `KeyRotator` and `ModelRouter` but lacks OAuth and cooldown tiers; `/doctor` exists but lacks DM and sandbox audit; session tools via `/btw` are partial; DM pairing, Docker sandbox, ClawHub registry, Live Canvas/A2UI, Voice Wake, chat commands subset, and webhook/cron ingress are incomplete; fallback skip TTL cache is missing.

Similar repos include [OpenHands](https://github.com/All-Hands-AI/OpenHands) for sandbox GUI; [Aider](https://github.com/Aider-AI/aider) for repo map (`GitContext`, `CodeIndex` partial); [SWE-agent](https://github.com/SWE-agent/SWE-agent) for issue-to-patch (`/fix` partial); [crewAI](https://github.com/crewAIInc/crewAI) for roles (council and swarm partial); [nekro-agent](https://github.com/KroMiose/nekro-agent) for chat sandbox; and [OpenClaw-RL](https://github.com/Gen-Verse/OpenClaw-RL) for online RL (`FeedbackLedger` only). Clusters live in `patterns.yml` as `openclaw_like_personal_agents`, `bleeding_edge_experimental_repos`, and `agi_agent_ecosystem`.

Risks include unapproved RSI brain writes, hallucinated tools in corrupted sessions, bus factor one, and headless web-chat ToS per `ROUTING_REARCHITECTURE.md` §6. Do not conflate `mo-vic/OpenCrab` (distillation) or the empty `opencrab` org with this project.