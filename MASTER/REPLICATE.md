# Replicate

Media generation via Replicate API. Text reasoning stays on OpenRouter/xAI/Anthropic.

Authority: `data/rules.yml` → `data/providers.yml` → `data/models.yml` → this file.

Token: `REPLICATE_API_TOKEN` in `/etc/master.env` or `~/.config/repligen/config.json`.

## Models

| Task | Model |
|------|-------|
| Image (quality) | `black-forest-labs/flux-2-pro` |
| Image (fast) | `prunaai/flux-fast` |
| TTS | `jaaari/kokoro-82m` |
| I2V | `kwaivgi/kling-v2.1`, `minimax/video-01-live` |

## VideoChain

`lib/reach/video_chain.rb`: Flux keyframe → I2V → analog post → stitch.

```sh
/video --backend kling --minutes 5 --critique --auto-retry "prompt"
bundle exec ruby bin/video help
```

Backends: `kling`, `cogvideox`, `minimax`, `animatediff` (ComfyUI). Motion Council: `lib/judge/council/motion_critique.rb`. Env: `MOTION_CRITIQUE_VISION=1`, `COMFYUI_URL`.

Motion datasets: `/motion-dataset` or `bin/video motion-dataset`. Presets: `data/comfyui/motion_lora_presets.yml`.

## Shortcuts

| Command | Action |
|---------|--------|
| `/photograph <seed>` | Flux + kodak_portra postpro |
| `/repligen generate <model> <prompt>` | Direct prediction |
| `/prompt photo\|video <seed>` | Strunk-polished prompt only |

Poll predictions explicitly. Log prediction id, model, cost. Run content guard before exposing output. `/scan` before merging new media workflows.