// Routes mouth expression signals through blendshape targets (f3d_006).
(() => {
  "use strict";

  const DEFAULT = Object.freeze({ jawOpen: 0, mouthWide: 0, mouthRound: 0, smile: 0, frown: 0 });
  let mouthBlend = { ...DEFAULT };

  function clamp(v, lo = 0, hi = 1) {
    return Math.max(lo, Math.min(hi, v));
  }

  function pushBlend(patch) {
    mouthBlend = { ...mouthBlend, ...patch };
    const engine = window.Face3DPreview?.engine;
    if (engine?.setBlend) engine.setBlend(mouthBlend);
    window.dispatchEvent(new CustomEvent("face:mouth-blend", { detail: { ...mouthBlend } }));
  }

  function expressionToBlend(ex = {}) {
    const arousal = Number(ex.arousal ?? 0);
    const valence = Number(ex.valence ?? 0);
    const pressure = Number(ex.pressure ?? 0);
    return {
      jawOpen: clamp(arousal * 0.35 + pressure * 0.28),
      mouthWide: clamp(Math.max(0, valence) * 0.42),
      mouthRound: clamp(Math.max(0, -valence) * 0.32),
      smile: clamp(Math.max(0, valence) * 0.55),
      frown: clamp(Math.max(0, -valence) * 0.45)
    };
  }

  function applyExpression(ex) {
    pushBlend(expressionToBlend(ex));
  }

  function applyMouthDrive(drive, visemeAmp = 0) {
    const d = clamp(Number(drive || 0) + Number(visemeAmp || 0) * 0.35);
    pushBlend({ jawOpen: d * 0.42, mouthWide: d * 0.18 });
  }

  function boostEye(amount = 0.1) {
    window.dispatchEvent(new CustomEvent("face:eye-boost", { detail: { amount: clamp(Number(amount || 0)) } }));
  }

  function applyPressure(pressure = 0) {
    const p = clamp(Number(pressure || 0));
    pushBlend({ jawOpen: p * 0.28, mouthRound: p * 0.18 });
  }

  window.addEventListener("master:visual", (ev) => {
    const d = ev.detail || {};
    const name = String(d.name || d.mode || "");
    if (d.expression) applyExpression(d.expression);
    if (/speaking|tts:viseme|tts:playback:start/.test(name)) {
      const amp = Number(d.amp ?? d.visemeAmp ?? d.energy ?? 0.35);
      pushBlend({ jawOpen: amp * 0.48, mouthWide: amp * 0.16 });
    }
    if (/tts:playback:end|speaking:end|speaking:idle/.test(name)) pushBlend(DEFAULT);
  });

  window.addEventListener("user:expression", (ev) => {
    const ex = ev.detail?.expression;
    if (ex) applyExpression(ex);
  });

  window.MASTER_FACE_BLEND = Object.freeze({
    pushBlend,
    applyExpression,
    applyMouthDrive,
    boostEye,
    applyPressure,
    expressionToBlend,
    current: () => ({ ...mouthBlend })
  });
})();
