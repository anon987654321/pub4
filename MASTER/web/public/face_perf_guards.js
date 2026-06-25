// Perf guards — resize debounce, kernel min-delta, primer boot spawn (web_069–web_071, mi_032–mi_036).
(() => {
  "use strict";

  const MIN_KERNEL_DT = 0.008;
  const RESIZE_THRESHOLD = 50;
  let lastResizeW = 0;
  let lastResizeH = 0;

  if (window.ParticleKernel && typeof window.ParticleKernel.step === "function") {
    const origStep = window.ParticleKernel.step;
    window.ParticleKernel.step = function stepGuarded(pool, dt, ctx = {}) {
      const clamped = Math.max(MIN_KERNEL_DT, Math.min(0.05, Number(dt) || MIN_KERNEL_DT));
      const next = { ...ctx };
      if (window.MASTER_RUNTIME?.enhancements?.includes?.("spatial_repulsion_2d")) {
        next.spatialRepulsion = true;
      }
      return origStep.call(this, pool, clamped, next);
    };
  }

  window.addEventListener("primer:ready", () => {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("particle_worker")) return;
    try {
      const worker = new Worker(window.MASTER_ASSET_PATHS?.faceModules?.particle_worker || "/particle_worker.js");
      worker.postMessage({ type: "warm", dt: 0.016 });
      setTimeout(() => worker.terminate(), 120);
    } catch (_) {}
  });

  window.addEventListener("visual:ready", () => {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("primer_kernel_spawn")) return;
    const K = window.ParticleKernel;
    const pool = window.MASTER_FACE?.eyePool || window.eyePool;
    if (!K || !pool) return;
    for (let i = 0; i < 4; i++) {
      K.spawn(pool, (Math.random() - 0.5) * 0.3, (Math.random() - 0.5) * 0.2, {
        kind: 2, zone: 2, attention: 0.85, confidence: 0.9, decay: 0.01
      });
    }
  });

  window.addEventListener("master:visual", (ev) => {
    const name = String(ev.detail?.name || "");
    if (/autocommit|auto.commit|auto_commit/i.test(name)) {
      const K = window.ParticleKernel;
      const pool = window.MASTER_FACE?.eyePool || window.eyePool;
      if (!K || !pool) return;
      for (let i = 0; i < 5; i++) {
        K.spawn(pool, (Math.random() - 0.5) * 0.25, -0.5 + Math.random() * 0.1, {
          kind: 3, zone: 13, valence: 0.75, confidence: 0.95, decay: 0.006
        });
      }
      window.MASTERVisual?.event?.("autocommit:joy", { topology: "papua-mask", entropy: 0.1, confidence: 0.96, mode: "commit" });
    }
  });

  let streamStartAt = 0;
  window.addEventListener("chat:chunk", () => {
    if (!streamStartAt) streamStartAt = performance.now();
    const elapsed = performance.now() - streamStartAt;
    if (elapsed > 12000) {
      const st = window.MASTER_FACE?.State;
      if (st) st.mouseX = Math.sin(elapsed * 0.0004) * 0.12;
    }
  });
  window.addEventListener("master:visual", (ev) => {
    if (/llm:request|pipeline:start|thinking/.test(String(ev.detail?.name || ""))) streamStartAt = performance.now();
    if (/complete|done|error/.test(String(ev.detail?.name || ""))) streamStartAt = 0;
  });

  window.MASTER_FACE_PERF = Object.freeze({
    resizeThreshold: RESIZE_THRESHOLD,
    minKernelDt: MIN_KERNEL_DT,
    shouldResize(w, h) {
      if (Math.abs(w - lastResizeW) < RESIZE_THRESHOLD && Math.abs(h - lastResizeH) < RESIZE_THRESHOLD) return false;
      lastResizeW = w;
      lastResizeH = h;
      return true;
    }
  });
})();