# MASTER web

Rails 8 + Falcon. Loopback `:53187`; relayd → `https://ai.brgen.no`.

## Routes

| Route | Purpose |
|-------|---------|
| `GET /` | Chat + face runtime |
| `GET /up` | Health |
| `GET /chat/message` | SSE assistant stream |
| `GET /chat/metrics` | Session metrics |
| `GET /events/stream` | SSE event bus |

## Face runtime

Scripts under `public/`:

- `face.js` — wireframe mesh (THREE.js)
- `cognition_ecology.js` — ecology particle layer (`z-index: 1` over face canvas)
- `particle_kernel.js` — typed cell pool
- `topology_registry.js` — topology dispatch

Topology config: `MASTER/data/topologies.yml` (not `data/topologies.yml` relative to web/).

Tap `#primer` to start audio/WebGL. Ecology particles should render over the face in a fresh private window when origin is healthy.

## Deploy

```zsh
doas rcctl restart master
curl -fsS http://127.0.0.1:53187/up
```

Auth: Bearer / `X-Token` / `master_session` cookie. Visitor tier: chat only.