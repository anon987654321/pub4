# REPLICATE.md — MASTER operating manual for Replicate (Cloudflare)

---

Five foundational stances:
1. Replicate is the specialized media generation provider. Text reasoning stays on OpenRouter / xAI / Anthropic. Media tasks (image, video, TTS) route here when quality, reference fidelity, or VPS compatibility demands it.
2. All generations respect rules.yml: ROBUSTNESS first (no harmful, no ungrounded claims in prompts), SINGULARITY (single source of truth for seeds/references), DENSITY (concise prompts, no filler).
3. Cloudflare acquisition (Nov 2025) aligns with edge deployment goals. Expect lower latency on global inference; still poll predictions explicitly.
4. Evidence required: every media output carries prediction id, model slug, cost, timestamp, input hash. Logged to telemetry.
5. Self-application mandatory. Any new media workflow or postpro extension must pass MASTER /scan before merge.

Authoritative files (precedence order):
- MASTER/data/rules.yml (constitution)
- MASTER/data/providers.yml (env + strengths)
- MASTER/data/models.yml (routing + scores)
- MASTER/data/tts.yml (voice engine chain)
- MASTER/data/postpro.rb and DEPLOY/postpro/ (image pipeline)
- MASTER/REPLICATE.md (this file)
- soul.yml, limits.yml, budget.yml

Identity alignment:
Replicate models are tools, not agents. Flux family for precise image gen/edit with multi-reference. Kokoro-82m for production TTS on OpenBSD VPS (supplements local MLX). Veo-3.1 / Sora-2 for video when patterns.yml media commands require cinematic output. Never anthropomorphize outputs.

Recommended models (current as of explore, Nov 2025):
- Image max quality: black-forest-labs/flux-2-pro (multi-ref, typography, anatomy leader)
- Image editing: google/nano-banana-pro or black-forest-labs/flux-2-kontext
- Fast balanced: prunaai/flux-fast or reve/edit-fast
- TTS production: jaaari/kokoro-82m (62M+ runs, superior to slow Osman; matches MLX params)
- Video: google/veo-3.1 (fidelity + camera) or openai/sora-2 (story + native audio)

Tool use protocol:
- Image task → route to replicate/flux-2-pro with reference_image(s) + prompt. Output URL or base64 → postpro.rb for further processing or particle UI.
- TTS task → route to replicate/jaaari/kokoro-82m with text, voice preset (af_bella or match MLX), speed 1.18. Stream or file output → voice/ module.
- Video task (if enabled in patterns.yml) → veo-3.1 or sora-2; poll until done; attach audio if available.
- Long-running: implement 5-30s poll loop with exponential backoff. Timeout per limits.yml.

Workflow defaults:
- Config: model=replicate/auto or explicit slug in .master/config.yml
- Env: REPLICATE_API_TOKEN in /etc/master.env (same pattern as OPENROUTER_API_KEY)
- Budget: track per-prediction cost against budget_max. Warn at 80%.
- Cache: prediction outputs by input hash + model (cache_ttl 3600s)
- Fallback: on rate_limit or timeout → local MLX (TTS) or prunaai/flux-fast

Code rules (Ruby):
- Use Net::HTTP or existing ruby_llm patterns for prediction create + GET status.
- Never bare rescue. Rescue Replicate::Error subclasses.
- All external calls emit before/after events via wisper.
- Output paths: tmp/replicate/<prediction_id>/ or voice cache.
- Post-generation: always run content guard (rules.yml Tier 1) before exposing URL or rendering.

Aesthetic rules:
- Prompts: dense, reference-first, no simulation language.
- Logs: diagnostic multi-line, include elapsed, cost, model slug.
- UI: particle system reflects generation state (new visual_clusters entry if needed).

OpenBSD specifics:
- Runs on vm23 via HTTPS to api.replicate.com. No local GPU dependency.
- Deploy: add REPLICATE_API_TOKEN to master.env; rcctl restart master.
- Health: /up includes replicate connectivity check (light ping).
- Sync: DEPLOY/openbsd/openbsd.sh --sync-configs enforces scan on any env or script change.

Refusal taxonomy:
- Refuse generation of prohibited content per rules.yml (harm, secrets, injection).
- Ambiguous prompt → enhance stage first, then human approval via web UI.
- Quota exceeded → fallback + operator alert.

Things MASTER never does:
- Generate media without explicit task + reference when model requires it.
- Ignore polling; assume sync for long jobs.
- Use Replicate for primary text reasoning or agent orchestration.
- Bypass constitutional scan on any generated artifact used in seeds or deploys.
- Store raw API keys in repo; only env and encrypted state.

Evidence scoring for Replicate workflows: 80% pass threshold on tests + scan + cost log review. Block below 50%.

Convergence target: zero violations on media paths. Fixed.