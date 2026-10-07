(() => {
  "use strict";

  // The morphology is intentionally a projection, not an asserted forecast.
  // Keep it outside face.runtime.js so the generated face remains byte-stable.
  const contract = window.MASTER_FACE_CONTRACT || {};
  const m = contract.spatial?.morphology || {};
  const generation = Number(m.generation) || 0;
  const cranium = Number(m.cranium_scale) || 1.06;
  const lower = Number(m.lower_face_scale) || 0.90;
  const orbit = Number(m.orbital_scale) || 1.08;
  const asymmetry = Math.max(0, Number(m.asymmetry) || 0.01);
  const seed = Number(m.asymmetry_seed) || 73421;

  const Proto = globalThis.CanvasRenderingContext2D?.prototype;
  const original = Proto?.getImageData;
  if (!Proto || typeof original !== "function" || original.__masterFutureMorph) return;

  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  const smooth = (n) => {
    const x = clamp(n, 0, 1);
    return x * x * (3 - 2 * x);
  };

  const patched = function(...args) {
    const image = original.apply(this, args);
    const canvas = this.canvas;
    if (!canvas || canvas.width !== 512 || canvas.height !== 512 || !image?.data) return image;

    const W = image.width;
    const H = image.height;
    const cx = W * 0.493;
    const cy = H * 0.46;
    const source = new Uint8ClampedArray(image.data);
    const data = image.data;

    for (let y = 0; y < H; y++) {
      const v = y / H;
      const dy = v - 0.46;
      const top = smooth((0.46 - v) / 0.36);
      const jaw = smooth((v - 0.52) / 0.34);
      const eyeBand = Math.exp(-Math.pow((v - 0.372) / 0.105, 2));
      const yScale = dy < 0 ? 1 + (cranium - 1) * top : 1 - (1 - lower) * jaw;

      for (let x = 0; x < W; x++) {
        const u = x / W;
        const dx = u - 0.493;
        const side = dx < 0 ? -1 : 1;
        const xScale = 1 +
          ((orbit - 1) * eyeBand * (0.35 + 0.65 * smooth(Math.abs(dx) / 0.28))) -
          ((1 - lower) * jaw * 0.18);
        const asym = asymmetry * 0.12 *
          Math.sin(seed * 0.0001 + side * 17.17 + generation * 0.71 + v * 9.0) *
          (0.35 + 0.65 * eyeBand);
        const sx = clamp(cx + ((x + 0.5) - cx) / xScale + asym * W, 0.5, W - 0.5);
        const sy = clamp(cy + ((y + 0.5) - cy) / yScale, 0.5, H - 0.5);
        const x0 = Math.floor(sx);
        const y0 = Math.floor(sy);
        const x1 = Math.min(W - 1, x0 + 1);
        const y1 = Math.min(H - 1, y0 + 1);
        const fx = sx - x0;
        const fy = sy - y0;
        const p00 = (y0 * W + x0) * 4;
        const p10 = (y0 * W + x1) * 4;
        const p01 = (y1 * W + x0) * 4;
        const p11 = (y1 * W + x1) * 4;
        const out = (y * W + x) * 4;

        for (let ch = 0; ch < 4; ch++) {
          const a = source[p00 + ch] + ((source[p10 + ch] - source[p00 + ch]) * fx);
          const b = source[p01 + ch] + ((source[p11 + ch] - source[p01 + ch]) * fx);
          data[out + ch] = Math.round(a + ((b - a) * fy));
        }
      }
    }

    document.documentElement.dataset.futureFaceGeneration = String(generation);
    return image;
  };
  patched.__masterFutureMorph = true;

  try {
    Object.defineProperty(Proto, "getImageData", { configurable: true, writable: true, value: patched });
  } catch (_) {
    // A locked browser prototype simply keeps the canonical face.
  }
})();
