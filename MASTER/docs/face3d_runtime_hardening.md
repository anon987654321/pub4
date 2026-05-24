# Face3D Runtime Hardening

The current Face3D preview remains the canonical path. It is enabled by `?face3d=1` and uses `web/public/face3d_engine.js`, `web/public/face3d_renderer.js`, and `web/public/face3d_preview.js`.

## Implementation order

1. Keep the current typed-array particle core.
2. Replace allocation-heavy spatial lookup with fixed typed-array buckets.
3. Add spatial repulsion only inside the existing CPU tick.
4. Gate expensive effects through the existing quality controller.
5. Add visibility throttling before worker or GPU experiments.
6. Add worker physics only after the main-thread CPU path is stable.
7. Add WebGPU only as an optional acceleration path after CPU fallback is proven.

## Runtime rules

- No parallel Face3D runtime.
- No WebGPU until CPU fallback is complete.
- No per-frame object particles.
- No synchronous GPU readback.
- No canvas resize inside the animation loop.
- No layout-changing DOM writes in the render path.

## Quality degradation order

1. Bloom.
2. Spatial repulsion.
3. Oscilloscope effects.
4. Frame cap.
5. Particle count on next engine rebuild.

Core face motion and expression blendshapes stay active even in degraded mode.

## Next safe patch

The next code patch should update `SpatialHash2D` to use fixed typed arrays and add a `ParticleField3D#repelNeighbors(hash, quality, dtMs)` pass after projected positions are updated.
