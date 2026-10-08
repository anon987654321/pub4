// Web Worker — offloads ParticleKernel.step from the main thread.
(() => {
  "use strict";

  // The same layout particle_kernel.js declares, restated because a Worker
  // cannot see that scope. It is the stride for a pool transferred in from the
  // main thread, so a narrower copy here does not merely skip the depth axis —
  // it reads every field of every cell from the wrong offset.
  const FIELDS_PER_CELL = 14;
  const FIELD = {
    x: 0, y: 1, vx: 2, vy: 3,
    kind: 4, zone: 5, confidence: 6, pressure: 7,
    valence: 8, arousal: 9, attention: 10, age: 11,
    z: 12, vz: 13
  };

  function hydratePool(payload) {
    const pool = {
      cells: new Float32Array(payload.cells),
      decay: new Float32Array(payload.decay),
      alive: new Uint8Array(payload.alive),
      capacity: payload.capacity,
      count: payload.count
    };
    return pool;
  }

  function serializePool(pool) {
    return {
      cells: pool.cells.buffer,
      decay: pool.decay.buffer,
      alive: pool.alive.buffer,
      capacity: pool.capacity,
      count: pool.count
    };
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
  }

  self.onmessage = (ev) => {
    const msg = ev.data || {};
    if (msg.op !== "step") return;
    const pool = hydratePool(msg.pool);
    step(pool, msg.dt || 0.016, msg.ctx || {});
    self.postMessage({ id: msg.id, pool: serializePool(pool) }, [
      pool.cells.buffer,
      pool.decay.buffer,
      pool.alive.buffer
    ]);
  };
})();
