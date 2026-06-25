// Routes expression signals through Face3D blendshapes + emotion (canonical when FACE3D_ACTIVE).
(() => {
  "use strict";

  const DEFAULT_BLEND = Object.freeze({ jawOpen: 0, mouthWide: 0, mouthRound: 0, smile: 0, frown: 0 });
  const DEFAULT_EMOTION = Object.freeze({ arousal: 0.32, valence: 0, focus: 0.45, confidence: 0.82, fatigue: 0.08 });

  let mouthBlend = { ...DEFAULT_BLEND };
  let emotionState = { ...DEFAULT_EMOTION };

  function clamp(v, lo = 0, hi = 1) {
    return Math.max(lo, Math.min(hi, v));
  }

  function engine() {
    return window.Face3DPreview?.engine;
  }

  function pushEmotion(patch) {
    emotionState = { ...emotionState, ...patch };
    const eng = engine();
    if (eng?.setEmotion) eng.setEmotion(emotionState);
    window.dispatchEvent(new CustomEvent("face:emotion", { detail: { ...emotionState } }));
  }

  function pushBlend(patch) {
    mouthBlend = { ...mouthBlend, ...patch };
    const eng = engine();
    if (eng?.setBlend) eng.setBlend(mouthBlend);
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
    const patch = {};
    if (ex.arousal != null) patch.arousal = Number(ex.arousal);
    if (ex.valence != null) patch.valence = Number(ex.valence);
    if (ex.focus != null) patch.focus = Number(ex.focus);
    if (ex.attention != null) patch.focus = Number(ex.attention);
    if (ex.confidence != null) patch.confidence = Number(ex.confidence);
    if (ex.fatigue != null) patch.fatigue = Number(ex.fatigue);
    if (ex.emotion && typeof ex.emotion === "object") Object.assign(patch, ex.emotion);
    if (Object.keys(patch).length) pushEmotion(patch);
    pushBlend(expressionToBlend(ex));
  }

  function applyMouthDrive(drive, visemeAmp = 0) {
    const d = clamp(Number(drive || 0) + Number(visemeAmp || 0) * 0.35);
    pushBlend({ jawOpen: d * 0.42, mouthWide: d * 0.18 });
  }

  function boostEye(delta = 0.12) {
    pushEmotion({ focus: clamp((emotionState.focus || 0) + delta) });
  }

  function mouthPressure(delta = 0.18) {
    pushBlend({
      jawOpen: clamp((mouthBlend.jawOpen || 0) + delta * 0.55),
      mouthWide: clamp((mouthBlend.mouthWide || 0) + delta * 0.22)
    });
  }

  function dropConfidence(drop = 0.3) {
    pushEmotion({ confidence: clamp((emotionState.confidence ?? 1) - drop, 0.1, 1) });
  }

  function applyPressure({ pct = 0, turbulence = 0, gravity = 0 } = {}) {
    const push = Math.min(0.85, Number(pct) / 100);
    const turb = Math.min(0.35, Number(turbulence) || 0);
    const grav = Math.min(0.4, Number(gravity) || 0);
    pushEmotion({
      arousal: clamp((emotionState.arousal || 0) + push * 0.35),
      valence: grav > 0 ? Math.max(-0.2, (emotionState.valence || 0) - grav * 0.12) : emotionState.valence,
      confidence: clamp((emotionState.confidence ?? 1) - turb * 0.08)
    });
    pushBlend({ jawOpen: clamp(push + turb * 0.2), mouthRound: clamp(grav * 0.15) });
  }

  function applyVerticalTimbre(bias = {}) {
    const patch = {};
    if (bias.arousal != null) patch.arousal = clamp((emotionState.arousal || 0.4) + bias.arousal * 0.08);
    if (bias.valence != null) patch.valence = (emotionState.valence || 0) + bias.valence * 0.05;
    if (Object.keys(patch).length) pushEmotion(patch);
    if (bias.pressure != null) pushBlend({ jawOpen: clamp((mouthBlend.jawOpen || 0) + bias.pressure * 0.06) });
  }

  function applyStyleArousal(ex = {}, style = "") {
    const hi = /dramatic|intense|energetic|storyteller/i.test(String(style));
    const lo = /whisper|ethereal|robotic|intimate/i.test(String(style));
    const arousal = ex.arousal ?? (hi ? 1.0 : lo ? 0.3 : 0.7);
    pushEmotion({ arousal });
    if (ex.pressure != null) pushBlend({ jawOpen: clamp(ex.pressure * 0.42) });
  }

  function applyInferBump(confidence = 0.7) {
    const bump = 0.12 + confidence * 0.18;
    pushEmotion({ arousal: clamp((emotionState.arousal || 0.3) + bump) });
    pushBlend({ jawOpen: clamp(bump * 0.35) });
  }

  function resetMouth(decay = 0.82) {
    const rate = clamp(Number(decay) || 0.82, 0.1, 1);
    pushBlend({
      jawOpen: clamp((mouthBlend.jawOpen || 0) * rate),
      mouthWide: clamp((mouthBlend.mouthWide || 0) * rate),
      mouthRound: clamp((mouthBlend.mouthRound || 0) * rate)
    });
    pushEmotion({ arousal: clamp((emotionState.arousal || 0.5) * rate, 0.12, 1) });
  }

  function focusLevel() {
    return clamp(emotionState.focus ?? 0.5);
  }

  window.addEventListener("master:visual", (ev) => {
    const d = ev.detail || {};
    const name = String(d.name || d.mode || "");
    if (d.expression) applyExpression(d.expression);
    if (d.emotion) pushEmotion(typeof d.emotion === "object" ? d.emotion : { valence: 0, arousal: 0.4 });
    if (/speaking|tts:viseme|tts:playback:start/.test(name)) {
      const amp = Number(d.amp ?? d.visemeAmp ?? d.energy ?? 0.35);
      pushBlend({ jawOpen: amp * 0.48, mouthWide: amp * 0.16 });
    }
    if (/tts:playback:end|speaking:end|speaking:idle/.test(name)) {
      pushBlend(DEFAULT_BLEND);
      pushEmotion({ arousal: clamp((emotionState.arousal || 0.5) * 0.82, 0.12, 1) });
    }
  });

  window.addEventListener("user:expression", (ev) => {
    const ex = ev.detail?.expression;
    if (ex) applyExpression(ex);
  });

  window.MASTER_FACE_BLEND = Object.freeze({
    pushBlend,
    pushEmotion,
    applyExpression,
    applyMouthDrive,
    expressionToBlend,
    boostEye,
    mouthPressure,
    dropConfidence,
    applyPressure,
    applyVerticalTimbre,
    applyStyleArousal,
    applyInferBump,
    resetMouth,
    focusLevel,
    current: () => ({ ...mouthBlend }),
    currentEmotion: () => ({ ...emotionState })
  });
})();