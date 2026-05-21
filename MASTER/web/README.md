# MASTER Web UI

Rails 8 + Falcon server. Internal port 53187; relayd proxies to ai.brgen.no:4430.

## Routes

| Route | Description |
|---|---|
| `GET /` | Chat interface |
| `GET /chat/message` | SSE streaming response |
| `POST /chat/tts` | TTS synthesis |
| `POST /chat/speak` | Speak text |
| `GET /chat/metrics` | Session metrics |
| `GET /chat/dmesg` | Event log |
| `GET /events/stream` | SSE event stream |

## Pixel Field

Semantic bitmap renderer. Cells carry kind, zone, confidence, pressure, valence, arousal, attention, age — not decorative particles.

- `particle_kernel.js` — typed-array cell pool, fixed-timestep update, bitmap primitives (integer scaling, hard edges, Bayer dithering)
- `topology_registry.js` — canonical topologies (face / codebase / ecology / face3d) and master:* event bus
- `data/topologies.yml` — source of truth: zones, transitions, palettes, cell rules

Runtime modes: operator (black/white/one accent, max density) · review (calmer, slower) · visitor (restricted).

Internal resolutions: 320×180 / 480×270 / 640×360, integer upscaled. `ctx.imageSmoothingEnabled = false`.

## Audio

- Ambient pad engine
- Drum sequencer
- 17 voice FX chains

## rc.d service

```zsh
doas rcctl enable master
doas rcctl start master
```

Daemon binds to 127.0.0.1:53187. relayd handles TLS termination.
