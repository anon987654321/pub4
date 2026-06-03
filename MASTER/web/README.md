# MASTER Web UI

Rails 8 + Falcon server. Internal port 53187; relayd proxies to https://ai.brgen.no (443).

## Routes

| Route | Description |
|---|---|
| `GET /` | Chat interface |
| `GET /chat/message` | SSE streaming response |
| `GET /chat/metrics` | Session metrics |
| `GET /chat/dmesg` | Event log |
| `GET /events/stream` | SSE event stream |

## Face — Wireframe Mesh

`public/face.js` renders a 3D face as a sparse polygon mesh — vertices and edges, not a particle cloud.

Topology: hex-grid projected onto the face depth map (~1400 nodes desktop, ~480 mobile). Only cells where luminance > 0.08 become vertices; the rest is void. Hex adjacency produces three edge types per cell (right, below, diagonal), yielding the triangulated wireframe.

Rendering: `THREE.Points` for vertex nodes, `THREE.LineSegments` for mesh edges at 6% opacity — the substrate. Vertex nodes are larger and brighter (depth-shaded). Together they read as a Blender/Lightwave wireframe with biological character: the face topology is legible as geometry, not fog.

Motion: curl noise drives vertex drift at low amplitude (0.06 base) — languid, hyphal. During thinking mode the amplitude rises to 0.34 (`uCurl` → 1.0), vertices swarm. During speech, jaw vertices drop and bass pulses the radial wave. Edge opacity scales with bass for a brief mesh-glow on consonants.

Depth map (`generateFaceDepthMap`): OffscreenCanvas grayscale encoding — luminance = Z. Features: forehead plane, brow ridges, glabella depression, elongated eye sockets, corneal speculars, nose bridge/tip, cheekbones, nasolabial folds, elongated lips, philtrum, chin taper.

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
