// Web Worker — offloads ParticleKernel.step from the main thread.
(() => {
  "use strict";

  const FIELDS_PER_CELL = 12;
  const FIELD = {
    x: 0, y: 1, vx: 2, vy: 3,
    kind: 4, zone: 5, confidence: 6, pressure: 7,
    valence: 8, arousal: 9, attention: 10, age: 11
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

  self.onmessage = (ev) => {
    const msg = ev.data || {};
    if (msg.op !== "step") return;
    const pool = hydratePool(msg.pool);
    step(pool, msg.dt || 0.016);
    self.postMessage({ id: msg.id, pool: serializePool(pool) }, [
      pool.cells.buffer,
      pool.decay.buffer,
      pool.alive.buffer
    ]);
  };
})();