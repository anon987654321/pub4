# Replicate

MASTER generates media through the Replicate API while text reasoning stays on OpenRouter, xAI, and Anthropic. Authority flows from `data/rules.yml` to `data/providers.yml` to `data/models.yml` to this file. The token is `REPLICATE_API_TOKEN` in `/etc/master.env` or `~/.config/repligen/config.json`.

For images, quality work uses `black-forest-labs/flux-2-pro` and fast work uses `prunaai/flux-fast`. TTS uses `jaaari/kokoro-82m`. Image-to-video backends include `kwaivgi/kling-v2.1` and `minimax/video-01-live`.

VideoChain lives in `lib/reach/video_chain.rb`: Flux keyframe, then I2V, analog post, then stitch. Example invocation: `/video --backend kling --minutes 5 --critique --auto-retry "prompt"`, with full help at `bundle exec ruby bin/video help`. Backends are `kling`, `cogvideox`, `minimax`, and `animatediff` (ComfyUI). Motion Council is in `lib/judge/council/motion_critique.rb`. Relevant environment variables are `MOTION_CRITIQUE_VISION=1` and `COMFYUI_URL`. Motion datasets use `/motion-dataset` or `bin/video motion-dataset`, with presets in `data/comfyui/motion_lora_presets.yml`.

Shortcuts: `/photograph <seed>` runs Flux with kodak_portra postpro; `/repligen generate <model> <prompt>` starts a direct prediction; `/prompt photo|video <seed>` returns a Strunk-polished prompt only.

Poll predictions explicitly. Log prediction id, model, and cost. Run content guard before exposing output. Run `/scan` before merging new media workflows.