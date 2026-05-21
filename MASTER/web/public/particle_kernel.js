// Pixel Field kernel. Typed-array cell pool, fixed-timestep update, bitmap
// rendering primitives. Replaces ad-hoc particle loops in face/codebase/ecology
// as they migrate one at a time. Renders semantic cells, not decorative
// particles — each cell carries kind, zone, confidence, pressure, valence,
// arousal, attention, age, decay.

(() => {
  "use strict";

  const FIELDS_PER_CELL = 12;
  const FIELD = {
    x: 0, y: 1, vx: 2, vy: 3,
    kind: 4, zone: 5, confidence: 6, pressure: 7,
    valence: 8, arousal: 9, attention: 10, age: 11
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
    pool.decay[i] = props.decay || 0.01;
    pool.alive[i] = 1;
    return i;
  }

  function step(pool, dt) {
    for (let i = 0; i < pool.count; i++) {
      if (!pool.alive[i]) continue;
      const base = i * FIELDS_PER_CELL;
      pool.cells[base + FIELD.x] += pool.cells[base + FIELD.vx] * dt;
      pool.cells[base + FIELD.y] += pool.cells[base + FIELD.vy] * dt;
      pool.cells[base + FIELD.age] += dt;
      pool.cells[base + FIELD.confidence] -= pool.decay[i] * dt;
      if (pool.cells[base + FIELD.confidence] <= 0) pool.alive[i] = 0;
    }
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
