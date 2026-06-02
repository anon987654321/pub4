# Face3D particle system migration

This document describes the incremental path from the current retro canvas face to a more coherent semantic 3D face-as-particles engine.

## Goals

- Keep (and refine) the existing retro Atkinson/Bayer/ZX/phosphor look as pure white dithered pixels — 8-bit monochrome CRT / terminal aesthetic.
- Move face geometry into normalized 3D coordinates.
- Move expression logic into blendshape state.
- Keep particles semantically assigned to anatomical zones.
- Use typed arrays in hot loops.
- Make speech, mood, confidence, tool events, and verdicts drive one coherent face state.
- Mine existing visual clusters and route them into one shared emotion/topology system.

## New modules

`web/public/face3d_engine.js` adds a standalone engine namespace at `window.MasterFace3D` and exports the same API as an ES module.

`web/public/face3d_renderer.js` adds a `Face3DCanvasRenderer` adapter that can render the engine snapshot back through a retro low-resolution phosphor/dither canvas path.

`web/public/face3d_preview.js` is an optional boot module. It only runs when the page URL includes `?face3d=1`, so it can be used as a safe preview path before replacing the live `face.js` renderer.

`web/public/cluster_miner.js` listens to `master:visual`, `master:codebase`, and `master:rule_event`, groups them into semantic clusters, emits `master:clusters`, and can feed `Face3DPreview.engine.setEmotion(...)` when the preview is active.

`data/visual_clusters.yml` is the canonical registry for current and proposed visual/cognition clusters.

The modules are intentionally additive. They do not replace `face.js` yet.

## Mined clusters

### Face Particle Body

Files:

- `web/public/face.js`
- `web/public/face3d_engine.js`
- `web/public/face3d_renderer.js`
- `web/public/face3d_preview.js`

Purpose: embody the assistant as a semantic particle face. The current renderer supplies the retro soul; Face3D supplies normalized topology, blendshapes, typed arrays, and preview rendering.

### Cognition Ecology

Files:

- `web/public/cognition_ecology.js`

Purpose: render runtime cognition as terrain, weather, trails, memories, and agent spirits.

### Codebase Topology

Files:

- `web/public/codebase.js`
- `data/architectures.yml`

Purpose: render modules as particle clusters. Violations agitate clusters; fixes settle them. This corresponds to Architecture #15.

### Runtime Visual Bridge

Files:

- `web/public/visual_bridge.js`

Purpose: normalize runtime events into `master:visual` state: mode, topology, entropy, confidence, provider.

### Speech and Audio Body

Files:

- `lib/voice/speech.rb`
- `bin/tts-worker`
- `web/public/face.js`

Purpose: convert streamed response text into speech, analyse decoded audio, and reshape the mouth during playback.

### Repo Ecology

Files:

- `docs/repo_ecology.md`
- `data/visual_clusters.yml`

Purpose: promote the repository from a bag of files into semantic topology, dependency ecology, cognitive geography, architectural history, and organizational memory.

## New proposed clusters

### Cluster Miner

Runtime/browser cluster miner that groups live visual events into reusable cluster states with heat, confidence, and evidence.

### Evidence Graph

Tracks why a file or event belongs to a cluster: imports, runtime event coupling, shared vocabulary, shared data files, changed-together history, or explicit docs.

### Emotion Bus

Converts visual entropy/confidence/mode/provider and cluster heat into a single shared emotion vector:

```js
{
  arousal,
  valence,
  focus,
  confidence,
  fatigue
}
```

### Topology Registry

Canonical registry for `papua-mask`, `serpent`, `neural`, `torus`, `sphere`, `codebase`, and future terrain/body forms.

### Migration Radar

Ranks safe migration steps by touched files, blast radius, rollback plan, and confidence.

## Core concepts

### Normalized topology

Masks should produce anchors in normalized face space:

- `x`: left to right, roughly `-1..1`
- `y`: forehead to chin, roughly `-1..1`
- `z`: back to forward, roughly `-1..1`
- `zone`: semantic anatomical region
- `u`: stable local coordinate within the zone

This lets the same topology scale to any viewport and makes real 3D pose projection simpler.

### Semantic particles

Particles keep a stable zone and local `u` coordinate. During mask changes, each particle finds the corresponding anchor in the new mask rather than being randomly reassigned.

This preserves feature identity: pupil particles stay pupils, mouth particles stay mouth, and brow particles stay brows.

### Blendshape rig

Mood, speech, confidence, and state events should write to blendshape values:

- `blink`
- `squint`
- `browInnerUp`
- `browDown`
- `smile`
- `frown`
- `jawOpen`
- `mouthWide`
- `mouthRound`
- `pupilDilate`
- `nostrilFlare`
- `cheekRaise`
- `shock`
- `chibi`

Particle targets are produced by applying the blendshape rig to topology anchors.

### Emotion vector

High-level events should update one emotion vector:

- `arousal`
- `valence`
- `focus`
- `confidence`
- `fatigue`

Blendshapes are derived from this vector, so the face feels continuous rather than event-random.

### Renderer adapter

The renderer consumes the engine snapshot:

```js
{
  count,
  x,
  y,
  depth,
  brightness,
  zone
}
```

It accumulates particles into a low-resolution float buffer, applies phosphor decay, runs Atkinson or Bayer dithering to produce pure white pixels, and blits the result to the face canvas (8-bit monochrome CRT / terminal aesthetic with dither for shading).

### Quality controller

Performance policy should live in one controller. It can lower frame rate, disable bloom, disable oscilloscope, or skip spatial repulsion when frame time or battery status requires it.

## Suggested migration order

1. Load `face3d_engine.js`, `face3d_renderer.js`, `face3d_preview.js`, and `cluster_miner.js` next to `face.js`.
2. Verify the preview with `?face3d=1`.
3. Use `MASTERClusterMiner.snapshot()` to inspect mined runtime clusters.
4. Route `master:clusters` into Face3D emotion state.
5. Use `MasterFace3D.VisemeDriver` for duration-based lipsync while keeping the existing renderer.
6. Replace direct mouth zone mutation with blendshape-driven mouth targets.
7. Convert existing mask builders to normalized anchors one mask at a time.
8. Move particle storage from objects to typed arrays.
9. Add spatial hash repulsion for high-density zones.
10. Add an optional WebGL renderer while preserving the retro canvas renderer as default.

## Preview integration

Add these after the existing `face.js` script:

```html
<script type="module" src="/face3d_engine.js"></script>
<script type="module" src="/face3d_renderer.js"></script>
<script type="module" src="/face3d_preview.js"></script>
<script src="/cluster_miner.js" defer></script>
```

Then open the chat UI with:

```text
?face3d=1
```

`face3d_preview.js` will take over the existing `#face` canvas only in that mode.

## Live integration sketch

```js
import { Face3DEngine } from '/face3d_engine.js';
import { Face3DCanvasRenderer } from '/face3d_renderer.js';

const engine = new Face3DEngine();
const renderer = new Face3DCanvasRenderer(document.getElementById('face'));

window.addEventListener('master:clusters', event => {
  engine.setEmotion(event.detail.emotion);
});

engine.setPose({ yaw: 0.15, pitch: -0.04 });
engine.tick(dt);
renderer.draw(engine.snapshot());
```

The current `face.js` can consume `snapshot()` data gradually without losing the existing visual identity.
