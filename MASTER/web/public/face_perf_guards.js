// Perf guards — resize debounce, kernel min-delta, primer boot burst (web_069–web_071, mi_032–mi_036).
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
    window.MASTER_FACE_BLEND?.boostEye?.(0.12);
    window.MASTEREcology?.burst?.(3, 0.18);
  });

  window.addEventListener("master:visual", (ev) => {
    const name = String(ev.detail?.name || "");
    if (/autocommit|auto.commit|auto_commit/i.test(name)) {
      window.MASTER_FACE_BLEND?.boostEye?.(0.15);
      window.MASTEREcology?.burst?.(5, 0.22);
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