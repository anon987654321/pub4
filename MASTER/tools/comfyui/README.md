# ComfyUI AnimateDiff wrapper

Optional HTTP shim between MASTER VideoChain and a local ComfyUI instance.

## When to use

- **Direct** (`COMFYUI_URL` only): `Reach::ComfyuiClient` patches `data/comfyui/animatediff_i2v.workflow.json` and calls ComfyUI `/prompt`.
- **Wrapper** (`COMFYUI_WRAPPER_URL`): same payload shape as Grok’s `/api/animatediff/generate` — useful if you prefer a single JSON endpoint or run ComfyUI on another host.

## Start wrapper

```sh
cd MASTER
COMFYUI_URL=http://127.0.0.1:8188 \
  WORKFLOW_JSON=data/comfyui/animatediff_i2v.workflow.json \
  python3 tools/comfyui/animatediff_api.py --port 8189
```

```sh
export COMFYUI_WRAPPER_URL=http://127.0.0.1:8189
bundle exec ruby bin/video --backend animatediff_camera \
  --motion-stack slow_dolly_push_in,elegant_orbit_tracking \
  "cinematic dolly shot"
```

## Requirements

- ComfyUI with **AnimateDiff-Evolved** + **ADMotionDirector** nodes installed.
- Motion LoRA files under `ComfyUI/models/animatediff_motion_lora/` (see `data/comfyui/motion_lora_presets.yml`).
- After exporting your workflow from ComfyUI (API format), update node IDs in `data/comfyui/animatediff_i2v.inputs.yml`.

## POST body

```json
{
  "prompt": "scene description",
  "image": "https://… or /local/keyframe.png",
  "frame_count": 80,
  "motion_loras": ["ZIKI_cinematic_slow_dolly_push_in_v1.safetensors"],
  "motion_lora_strength": 0.75
}
```

Response: `{ "view_url": "http://127.0.0.1:8188/view?…" }`