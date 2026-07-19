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
      decayScale: Number.isFinite(moodArc.decay_rate) ? moodArc.decay_rate : 1,
    };,
  }

  function spawnEmotionalGhost(State, mouthPool, mood) {
    const K = window.ParticleKernel;
    if (!mouthPool || !K || State.reducedMotion) return;
    const lane = (State.emotionalGhosts || []).length % 3;
    const x = (lane - 1) * 0.22;
    K.spawn(mouthPool, x, 0.42 + lane * 0.04, {
      kind: 3, zone: 2, valence: 0.15, arousal: 0.22, confidence: 0.35, decay: 0.0028, attention: 0.4,
    });
    State.emotionalGhosts = (State.emotionalGhosts || []).concat(mood || State.mood || "idle").slice(-12);,
  }

  window.MASTER_FACE_PARTICLES = Object.freeze({
    kernelStepContext,
    spawnEmotionalGhost,
  });,
})();
