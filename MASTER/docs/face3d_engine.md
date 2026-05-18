# Face3D particle system migration

This document describes the incremental path from the current retro canvas face to a more coherent semantic 3D face-as-particles engine.

## Goals

- Keep the existing retro Atkinson/Bayer/ZX/phosphor look.
- Move face geometry into normalized 3D coordinates.
- Move expression logic into blendshape state.
- Keep particles semantically assigned to anatomical zones.
- Use typed arrays in hot loops.
- Make speech, mood, confidence, tool events, and verdicts drive one coherent face state.

## New modules

`web/public/face3d_engine.js` adds a standalone engine namespace at `window.MasterFace3D` and exports the same API as an ES module.

`web/public/face3d_renderer.js` adds a `Face3DCanvasRenderer` adapter that can render the engine snapshot back through a retro low-resolution phosphor/dither canvas path.

`web/public/face3d_preview.js` is an optional boot module. It only runs when the page URL includes `?face3d=1`, so it can be used as a safe preview path before replacing the live `face.js` renderer.

The modules are intentionally additive. They do not replace `face.js` yet.

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

It accumulates particles into a low-resolution float buffer, applies phosphor decay, runs Atkinson or Bayer dithering, tints pixels by semantic zone, and blits the result to the face canvas.

### Quality controller

Performance policy should live in one controller. It can lower frame rate, disable bloom, disable oscilloscope, or skip spatial repulsion when frame time or battery status requires it.

## Suggested migration order

1. Load `face3d_engine.js`, `face3d_renderer.js`, and `face3d_preview.js` next to `face.js`.
2. Verify the preview with `?face3d=1`.
3. Use `MasterFace3D.VisemeDriver` for duration-based lipsync while keeping the existing renderer.
4. Replace direct mouth zone mutation with blendshape-driven mouth targets.
5. Convert existing mask builders to normalized anchors one mask at a time.
6. Move particle storage from objects to typed arrays.
7. Add spatial hash repulsion for high-density zones.
8. Add an optional WebGL renderer while preserving the retro canvas renderer as default.

## Preview integration

Add these after the existing `face.js` script:

```html
<script type="module" src="/face3d_engine.js"></script>
<script type="module" src="/face3d_renderer.js"></script>
<script type="module" src="/face3d_preview.js"></script>
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

engine.setEmotion({ focus: 0.4, confidence: 0.8 });
engine.setPose({ yaw: 0.15, pitch: -0.04 });
engine.tick(dt);
renderer.draw(engine.snapshot());
```

The current `face.js` can consume `snapshot()` data gradually without losing the existing visual identity.
