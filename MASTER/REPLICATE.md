# REPLICATE.md

Replicate is MASTER's governed media provider — image, video, TTS — not a reasoning LLM.

Authority: `data/soul.yml` > `data/rules.yml` > this file > `CLAUDE.md`.

## Stances

1. Media only. Text reasoning stays on OpenRouter / dedicated LLM providers.
2. Evidence required. Log prediction id, model slug, input hash, estimated cost before downstream use.
3. Reversible. Generated artifacts are staging inputs; never auto-commit seeds or deploy assets.
4. Token via env. `REPLICATE_API_TOKEN` or `REPLICATE_API_KEY` in `/etc/master.env` on VPS; `~/.config/repligen/config.json` for repligen CLI.
5. Scan gate. Files touched by Replicate output must pass `/scan` before merge.

## Entry points

| Path | Role |
|------|------|
| `tools/repligen.rb` | Interactive + batch image/video via `DEPLOY/repligen.rb` |
| `Reach::Repligen` | LLM tool + `/repligen` slash command |
| `Reach::ReplicateClient` | Net::HTTP predictions API (VideoChain, TTS) |
| `Reach::VideoChain` | Flux keyframe → I2V backends (Replicate + ComfyUI) |
| `Voice::Engines` `replicate_kokoro` | Cloud TTS when local MLX unavailable |

Config: `data/providers.yml`, `data/tts.yml`, `data/comfyui/`.

## Recommended models (2026-06)

| Task | Slug | Notes |
|------|------|-------|
| Image | `black-forest-labs/flux-1.1-pro` | Keyframes, photography; pair with postpro |
| Image (new) | `black-forest-labs/flux-2-pro` | Typography, multi-reference when available |
| TTS | `jaaari/kokoro-82m` | VPS-primary; `af_bella`, speed ~1.18 |
| Video | `kwaivgi/kling-v2.1`, `minimax/video-01-live` | Replicate I2V via VideoChain |
| Video (premium) | `google/veo-3.1`, `openai/sora-2` | When budget allows; longer poll timeouts |

## Protocol

Image: `/repligen generate <model> <prompt>` or `Reach::VideoChain` for chunked film.

TTS: `Voice::Transcendent` engine chain tries `replicate_kokoro` when token present.

Video: `/video --backend kling|happyhorse|animatediff` — see `data/comfyui/motion_lora_presets.yml`.

## Ruby rules

- Net::HTTP or `Reach::ReplicateClient`; no `replicate` gem.
- `rescue StandardError => e` only.
- Publish events: `replicate:predict_start`, `replicate:predict_done`, `replicate:predict_error`.
- No bare `system("curl …")`.

## OpenBSD / VPS

```zsh
# /etc/master.env
REPLICATE_API_TOKEN=...
doas zsh DEPLOY/openbsd/openbsd.sh --sync-configs
cd MASTER && bundle exec ruby bin/cli
# /repligen stats
```

## Refusals

- No secret tokens in repo, logs, or chat output.
- No unbounded parallel predictions (VideoChain caps threads).
- No generated binary in git without explicit operator intent.
- No claiming generation succeeded without prediction output URL or file path.

## Never

- Route council or fix-loop reasoning through Replicate.
- Skip postpro on photography intended for production seeds.
- Replace edge-tts worker with Kokoro for sub-20-char UI blips without measurement.