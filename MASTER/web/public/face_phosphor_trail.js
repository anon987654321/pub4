// Phosphor afterimage trail — adaptive decay, visibility throttle (web_006).
(() => {
  "use strict";

  let trailCanvas = null;
  let trailCtx = null;
  let frameSkip = 0;

  function readDecay() {
    const css = getComputedStyle(document.documentElement).getPropertyValue("--face-phosphor-decay").trim();
    const parsed = parseFloat(css);
    return Number.isFinite(parsed) ? parsed : 0.82;
  }

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
    if (!sourceCanvas || document.hidden) return;
    const st = window.MASTER_FACE?.State || window.State || {};
    if (st.reducedMotion || st.hidden) return;
    const profile = document.body?.dataset?.runtimeProfile;
    if (profile === "battery") {
      frameSkip += 1;
      if (frameSkip & 1) return;
    }
    const speaking = st.mode === "speaking" || !!window.MASTER_FACE?.tts?.playing;
    let decay = readDecay();
    if (speaking) decay = Math.max(0.68, decay - 0.06);
    const w = sourceCanvas.width;
    const h = sourceCanvas.height;
    const ctx = ensureTrail(w, h);
    if (!ctx) return;
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = decay;
    ctx.drawImage(sourceCanvas, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = "lighter";
    const fade = speaking ? 0.06 : 0.08;
    ctx.fillStyle = `rgba(0,0,0,${fade})`;
    ctx.fillRect(0, 0, w, h);
  }

  window.MASTER_PHOSPHOR_TRAIL = Object.freeze({ capture: capturePhosphorTrail });
})();