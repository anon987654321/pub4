// Particle pool stepping — extracted from face.part3 for modular face runtime (web_001).
(() => {
  "use strict";

  function kernelStepContext(State) {
    const pr = State.pressureFields || {};
    const moodArc = State.moodArc || {};
    return {
      entropy: Number.isFinite(pr.entropy) ? pr.entropy : (State.entropy || 0),
      pressure: Math.min(1, (Number(pr.pct) || 0) / 100),
      confidence: State.confidence ?? 0.75,
      decayScale: Number.isFinite(moodArc.decay_rate) ? moodArc.decay_rate : 1
    };
  }

  function spawnEmotionalGhost(State, _mouthPool, mood) {
    if (State.reducedMotion) return;
    window.MASTER_FACE_BLEND?.pushEmotion?.({
      arousal: 0.22,
      valence: 0.15,
      focus: 0.4,
      confidence: 0.35
    });
    State.emotionalGhosts = (State.emotionalGhosts || []).concat(mood || State.mood || "idle").slice(-12);
  }

  window.MASTER_FACE_PARTICLES = Object.freeze({
    kernelStepContext,
    spawnEmotionalGhost
  });
})();