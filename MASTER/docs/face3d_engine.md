# Face3D particle system migration

This document describes the incremental path from the current retro canvas face to a more coherent semantic 3D face-as-particles engine.

## Goals

- Keep the existing retro Atkinson/Bayer/ZX/phosphor look.
- Move face geometry into normalized 3D coordinates.
- Move expression logic into blendshape state.
- Keep particles semantically assigned to anatomical zones.
- Use typed arrays in hot loops.
- Make speech, mood, confidence, tool events, and verdicts drive one coherent face state.

## New module

`web/public/face3d_engine.js` adds a standalone engine namespace at `window.MasterFace3D` and exports the same API as an ES module.

The module is intentionally additive. It does not replace `face.js` yet.

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

### Quality controller

Performance policy should live in one controller. It can lower frame rate, disable bloom, disable oscilloscope, or skip spatial repulsion when frame time or battery status requires it.

## Suggested migration order

1. Load `face3d_engine.js` next to `face.js`.
2. Use `MasterFace3D.VisemeDriver` for duration-based lipsync while keeping the existing renderer.
3. Replace direct mouth zone mutation with blendshape-driven mouth targets.
4. Convert existing mask builders to normalized anchors one mask at a time.
5. Move particle storage from objects to typed arrays.
6. Add spatial hash repulsion for high-density zones.
7. Add an optional WebGL renderer while preserving the retro canvas renderer as default.

## Live integration sketch

```js
import { Face3DEngine } from '/face3d_engine.js';

const engine = new Face3DEngine();
engine.setEmotion({ focus: 0.4, confidence: 0.8 });
engine.setPose({ yaw: 0.15, pitch: -0.04 });
engine.tick(dt);
const frame = engine.snapshot();
```

The current `face.js` can consume `snapshot()` data gradually without losing the existing visual identity.
