// Pixel Field kernel. Typed-array cell pool, fixed-timestep update, bitmap
// rendering primitives. Replaces ad-hoc particle loops in face/codebase/ecology
// as they migrate one at a time. Renders semantic cells, not decorative
// particles — each cell carries kind, zone, confidence, pressure, valence,
// arousal, attention, age, decay.

(() => {
  "use strict";

  // z and vz are appended at 12 and 13 rather than inserted, so every existing
  // index is untouched and nothing that already reads this pool changes. A cell
  // spawned without a z sits at 0, which is the focal plane -- so the 2D callers
  // that predate depth keep behaving exactly as they did.
  //
  // Depth is here because a face made of flat points reads as a solid the moment
  // it moves coherently: parallax alone carries the volume. That is the kinetic
  // depth effect, and design_rules.kinetic_depth is where the house says so.
  //
  // particle_worker.js carries its own copy of this layout, because a Worker
  // cannot see this scope. The two must widen together: the worker strides a
  // transferred pool by its own FIELDS_PER_CELL, so a mismatch reads every
  // field of every cell from the wrong offset.
  const FIELDS_PER_CELL = 14;
  const FIELD = {
    x: 0, y: 1, vx: 2, vy: 3,
    kind: 4, zone: 5, confidence: 6, pressure: 7,
    valence: 8, arousal: 9, attention: 10, age: 11,
    z: 12, vz: 13
  };

  function createPool(capacity) {
    const cells = new Float32Array(capacity * FIELDS_PER_CELL);
    const decay = new Float32Array(capacity);
    const alive = new Uint8Array(capacity);
    return { cells, decay, alive, capacity, count: 0 };
  }

  function spawn(pool, x, y, props = {}) {
    if (pool.count >= pool.capacity) return -1;
    const i = pool.count++;
    const base = i * FIELDS_PER_CELL;
    pool.cells[base + FIELD.x] = x;
    pool.cells[base + FIELD.y] = y;
    pool.cells[base + FIELD.vx] = props.vx || 0;
    pool.cells[base + FIELD.vy] = props.vy || 0;
    pool.cells[base + FIELD.kind] = props.kind || 0;
    pool.cells[base + FIELD.zone] = props.zone || 0;
    pool.cells[base + FIELD.confidence] = props.confidence || 0.5;
    pool.cells[base + FIELD.pressure] = props.pressure || 0;
    pool.cells[base + FIELD.valence] = props.valence || 0;
    pool.cells[base + FIELD.arousal] = props.arousal || 0;
    pool.cells[base + FIELD.attention] = props.attention || 0;
    pool.cells[base + FIELD.age] = 0;
    pool.cells[base + FIELD.z] = props.z || 0;
    pool.cells[base + FIELD.vz] = props.vz || 0;
    pool.decay[i] = props.decay || 0.01;
    pool.alive[i] = 1;
    return i;
  }

  function spatialRepel(pool, strength = 0.006) {
    const cell = 0.04;
    const buckets = new Map();
    const key = (x, y) => `${Math.floor(x / cell)},${Math.floor(y / cell)}`;
    for (let i = 0; i < pool.count; i++) {
      if (!pool.alive[i]) continue;
      const base = i * FIELDS_PER_CELL;
      const k = key(pool.cells[base + FIELD.x], pool.cells[base + FIELD.y]);
      let bucket = buckets.get(k);
      if (!bucket) buckets.set(k, bucket = []);
      bucket.push(i);
    }
    for (let i = 0; i < pool.count; i++) {
      if (!pool.alive[i]) continue;
      const base = i * FIELDS_PER_CELL;
      const x = pool.cells[base + FIELD.x];
      const y = pool.cells[base + FIELD.y];
      const cx = Math.floor(x / cell);
      const cy = Math.floor(y / cell);
      for (let yy = cy - 1; yy <= cy + 1; yy++) {
        for (let xx = cx - 1; xx <= cx + 1; xx++) {
          const bucket = buckets.get(`${xx},${yy}`);
          if (!bucket) continue;
          for (let n = 0; n < bucket.length; n++) {
            const j = bucket[n];
            if (j === i || !pool.alive[j]) continue;
            const jb = j * FIELDS_PER_CELL;
            const dx = x - pool.cells[jb + FIELD.x];
            const dy = y - pool.cells[jb + FIELD.y];
            const dist = Math.hypot(dx, dy);
            if (dist > 0.06 || dist < 0.0004) continue;
            const push = strength / dist;
            pool.cells[base + FIELD.vx] += (dx / dist) * push;
            pool.cells[base + FIELD.vy] += (dy / dist) * push;
          }
        }
      }
    }
  }

  function step(pool, dt, ctx = {}) {
    const entropy = Number.isFinite(ctx.entropy) ? ctx.entropy : 0;
    const pressure = Number.isFinite(ctx.pressure) ? ctx.pressure : 0;
    const confidence = Number.isFinite(ctx.confidence) ? ctx.confidence : 0.75;
    const decayScale = Number.isFinite(ctx.decayScale) ? ctx.decayScale : 1;
    const velDamp = Math.max(0.72, 0.94 - entropy * 0.18 - pressure * 0.12);
    const attnDecay = 0.004 + entropy * 0.008;

    for (let i = 0; i < pool.count; i++) {
      if (!pool.alive[i]) continue;
      const base = i * FIELDS_PER_CELL;
      pool.cells[base + FIELD.vx] *= velDamp;
      pool.cells[base + FIELD.vy] *= velDamp;
      pool.cells[base + FIELD.x] += pool.cells[base + FIELD.vx] * dt;
      pool.cells[base + FIELD.y] += pool.cells[base + FIELD.vy] * dt;
      pool.cells[base + FIELD.vz] *= velDamp;
      pool.cells[base + FIELD.z] += pool.cells[base + FIELD.vz] * dt;
      pool.cells[base + FIELD.age] += dt;
      pool.cells[base + FIELD.attention] = Math.max(0, (pool.cells[base + FIELD.attention] || 0) - attnDecay * dt);
      const cellDecay = pool.decay[i] * decayScale * (1.0 + (1 - confidence) * 0.12);
      pool.cells[base + FIELD.confidence] -= cellDecay * dt;
      if (pool.cells[base + FIELD.confidence] <= 0) pool.alive[i] = 0;
    }
    if (ctx.spatialRepulsion) spatialRepel(pool, Number(ctx.repelStrength) || 0.006);
  }

  function compact(pool) {
    let write = 0;
    for (let read = 0; read < pool.count; read++) {
      if (!pool.alive[read]) continue;
      if (write !== read) {
        const src = read * FIELDS_PER_CELL;
        const dst = write * FIELDS_PER_CELL;
        for (let f = 0; f < FIELDS_PER_CELL; f++) pool.cells[dst + f] = pool.cells[src + f];
        pool.decay[write] = pool.decay[read];
        pool.alive[write] = 1;
      }
      write++;
    }
    pool.count = write;
  }

  function configureContext(ctx) {
    ctx.imageSmoothingEnabled = false;
    if ("webkitImageSmoothingEnabled" in ctx) ctx.webkitImageSmoothingEnabled = false;
    if ("mozImageSmoothingEnabled" in ctx) ctx.mozImageSmoothingEnabled = false;
  }

  function fitInternalResolution(canvas, resolution) {
    canvas.width = resolution.w;
    canvas.height = resolution.h;
    canvas.style.imageRendering = "pixelated";
  }

  function clear(ctx, color) {
    ctx.fillStyle = color;
    ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
  }

  function drawCell(ctx, x, y, size, color) {
    ctx.fillStyle = color;
    ctx.fillRect(x | 0, y | 0, size | 0, size | 0);
  }

  function bayer4(x, y) {
    const m = [[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]];
    return m[y & 3][x & 3] / 16;
  }

  function ditherThreshold(x, y, value) {
    return value > bayer4(x, y);
  }

  function makePalette(definition) {
    return { bg: definition.bg, fg: definition.fg, accent: definition.accent };
  }

  function createFrameClock(targetHz = 60) {
    const step = 1000 / targetHz;
    let last = performance.now();
    let accumulator = 0;
    return function tick(now, onStep) {
      accumulator += now - last;
      last = now;
      let steps = 0;
      while (accumulator >= step && steps < 4) {
        onStep(step / 1000);
        accumulator -= step;
        steps++;
      }
    };
  }

  window.ParticleKernel = {
    FIELD,
    FIELDS_PER_CELL,
    createPool,
    spawn,
    step,
    stepWithContext: step,
    spatialRepel,
    compact,
    configureContext,
    fitInternalResolution,
    clear,
    drawCell,
    bayer4,
    ditherThreshold,
    makePalette,
    createFrameClock
  };
})();
