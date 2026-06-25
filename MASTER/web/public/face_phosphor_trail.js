// Phosphor afterimage trail — captures prior frame decay (web_006).
(() => {
  "use strict";

  const TRAIL_DECAY = 0.82;
  let trailCanvas = null;
  let trailCtx = null;

  function ensureTrail(w, h) {
    if (!trailCanvas) {
      trailCanvas = document.createElement("canvas");
      trailCanvas.id = "face-phosphor-trail";
      trailCanvas.style.cssText = "position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:1;opacity:0.55;mix-blend-mode:screen;image-rendering:pixelated";
      document.body.appendChild(trailCanvas);
      trailCtx = trailCanvas.getContext("2d");
    }
    if (trailCanvas.width !== w || trailCanvas.height !== h) {
      trailCanvas.width = w;
      trailCanvas.height = h;
    }
    return trailCtx;
  }

  function capturePhosphorTrail(sourceCanvas) {
    if (!sourceCanvas || window.State?.reducedMotion) return;
    const profile = document.body?.dataset?.runtimeProfile;
    if (profile === "battery") return;
    const w = sourceCanvas.width;
    const h = sourceCanvas.height;
    const ctx = ensureTrail(w, h);
    if (!ctx) return;
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = TRAIL_DECAY;
    ctx.drawImage(sourceCanvas, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = "lighter";
    ctx.fillStyle = "rgba(0,0,0,0.08)";
    ctx.fillRect(0, 0, w, h);
  }

  window.MASTER_PHOSPHOR_TRAIL = Object.freeze({ capture: capturePhosphorTrail });
})();