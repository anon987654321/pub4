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
- Video (short clips): kwaivgi/kling-v2.1, thudm/cogvideox-5b-i2v, minimax/video-01-live via VideoChain
- Video (long-form): VideoChain stitches parallel chunks; optional ComfyUI AnimateDiff + Motion LoRAs locally

## VideoChain (cinematic pipeline)

Implementation: `MASTER/lib/reach/video_chain.rb` (not `lib/services/`). HTTP via `Reach::ReplicateClient`; ffmpeg via `Reach::VideoPost` (Open3 only).

Flow per chunk: **Flux keyframe** → **I2V backend** → **analog grain/vignette** → **concat**. Optional **Motion Council** critique and **auto-retry** of weak scenes.

| Backend | Provider | Notes |
|---------|----------|-------|
| `kling` | Replicate | Default I2V |
| `happyhorse` | Replicate | Alias to minimax/video-01-live in tree |
| `cogvideox` | Replicate | Open-weights style I2V |
| `minimax` | Replicate | Character consistency |
| `animatediff` / `animatediff_camera` | ComfyUI | Motion LoRA stacking; see `data/comfyui/` |

CLI (interactive or standalone):

```sh
# Inside MASTER CLI
/video --backend kling --minutes 5 --critique --auto-retry neon alley chase

# Standalone (no interactive CLI)
bundle exec ruby bin/video --backend animatediff_camera \
  --motion-stack slow_dolly_push_in,elegant_orbit_tracking \
  --minutes 10 --critique --vision-critique --per-chunk-critique --auto-retry \
  "epic cyberpunk chase"

# Motion LoRA training clip bootstrap
/motion-dataset --preset slow_dolly_push_in --subject "character in neon rain" --clips 12
bundle exec ruby bin/video motion-dataset --preset slow_dolly_push_in --subject "ZIKI girl" --clips 12
```

Motion Council (`lib/judge/council/motion_critique.rb`):
- **Whole-video** — keyframes from stitched output; 6 vision personas or text Deliberation with agent.
- **Per-chunk** — each clip reviewed before stitch (enabled by `--auto-retry` or `--per-chunk-critique`). Precise scene flags for retry.
- **Vision** — `MOTION_CRITIQUE_VISION=1` or `--vision-critique`; uses `google/gemini-2.5-flash` on Replicate (config: `data/council/motion_personas.yml`).

Auto-retry: `--auto-retry` re-renders flagged scenes with boosted `motion_intensity`, re-stitches as `cinematic_*_retryN_*.mp4`, up to `--max-retries` (default 2).

ComfyUI (self-hosted AnimateDiff):
- Direct: `COMFYUI_URL=http://127.0.0.1:8188` — client patches `data/comfyui/animatediff_i2v.workflow.json`.
- Wrapper (optional): `python3 tools/comfyui/animatediff_api.py --port 8189` then `COMFYUI_WRAPPER_URL=http://127.0.0.1:8189`. See `tools/comfyui/README.md`.

Motion LoRA presets: `data/comfyui/motion_lora_presets.yml` (`slow_dolly_push_in`, `elegant_orbit_tracking`, …).

Tool use protocol:
- Image task → route to replicate/flux-2-pro with reference_image(s) + prompt. Output URL or base64 → postpro.rb for further processing or particle UI.
- Photo shortcut → `/photograph <seed>` (Flux generate + kodak_portra postpro).
- TTS task → route to replicate/jaaari/kokoro-82m with text, voice preset (af_bella or match MLX), speed 1.18. Stream or file output → voice/ module.
- Long-form video → `/video` or `bin/video` via VideoChain; poll Replicate per chunk; ComfyUI polls `/history`.
- Long-running: 3s poll loop in ReplicateClient; ComfyUI timeout 900s default.

Workflow defaults:
- Config: model=replicate/auto or explicit slug in .master/config.yml
- Env (see `DEPLOY/openbsd/etc/master.env.sample`):
  - `REPLICATE_API_TOKEN` — predictions (also reads `REPLICATE_API_KEY` or `~/.config/repligen/config.json`)
  - `COMFYUI_URL` — ComfyUI host for `animatediff_camera` (default `http://127.0.0.1:8188`)
  - `COMFYUI_WRAPPER_URL` — optional Python wrapper (`tools/comfyui/animatediff_api.py`)
  - `COMFYUI_MOTION_LORA` / `COMFYUI_MOTION_LORA_WEIGHT` — default Motion LoRA file + strength
  - `MOTION_CRITIQUE_VISION=1` — vision council on `--critique`
  - `MOTION_CRITIQUE_PER_CHUNK=1` — per-chunk review (also default when `--auto-retry`)
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