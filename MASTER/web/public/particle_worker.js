// Web Worker — offloads ParticleKernel.step + compact from the main thread.
(() => {
  "use strict";

  const FIELDS_PER_CELL = 12;
  const FIELD = {
    x: 0, y: 1, vx: 2, vy: 3,
    kind: 4, zone: 5, confidence: 6, pressure: 7,
    valence: 8, arousal: 9, attention: 10, age: 11
  };

  function hydratePool(payload) {
    return {
      cells: new Float32Array(payload.cells),
      decay: new Float32Array(payload.decay),
      alive: new Uint8Array(payload.alive),
      capacity: payload.capacity,
      count: payload.count
    };
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

  self.onmessage = (ev) => {
    const msg = ev.data || {};
    if (msg.op === "warm") return;
    if (msg.op !== "step") return;
    const pool = hydratePool(msg.pool);
    step(pool, msg.dt || 0.016, msg.ctx || {});
    if (msg.compact) compact(pool);
    self.postMessage({ id: msg.id, pool: serializePool(pool) }, [
      pool.cells.buffer,
      pool.decay.buffer,
      pool.alive.buffer
    ]);
  };
})();