// Particle pool stepping — extracted from face.part3 for modular face runtime (web_001).
(() => {
  "use strict";

  let audio = { bass: 0, mid: 0, high: 0, onset: 0, rms: 0 };
  let lastAudioPulseAt = 0;
  window.addEventListener("audio:update", (event) => {
    audio = { ...audio, ...(event.detail || {}) };
  }, { passive: true });

  function kernelStepContext(State) {
    const pr = State.pressureFields || {};
    const moodArc = State.moodArc || {};
    return {
      entropy: Number.isFinite(pr.entropy) ? pr.entropy : (State.entropy || 0),
      pressure: Math.min(1, (Number(pr.pct) || 0) / 100),
      confidence: State.confidence ?? 0.75,
      decayScale: Number.isFinite(moodArc.decay_rate) ? moodArc.decay_rate : 1,
      audioBass: audio.bass,
      audioMid: audio.mid,
      audioHigh: audio.high,
      audioOnset: audio.onset,
      audioRms: audio.rms
    };
  }

  function reactAudio(State, mouthPool) {
    const K = window.ParticleKernel;
    if (!mouthPool || !K || State.reducedMotion) return;
    const now = performance.now();
    const onset = Number(audio.onset) || 0;
    if (onset < 0.14 || now - lastAudioPulseAt < 100) return;
    lastAudioPulseAt = now;
    const count = Math.min(4, 1 + Math.round(onset * 3));
    for (let i = 0; i < count; i += 1) {
      const lane = ((State.audioPulses || 0) + i) % 5;
      K.spawn(mouthPool, (lane - 2) * 0.12, 0.40 + audio.mid * 0.04, {
        kind: 24,
        zone: 1,
        valence: audio.high * 0.25,
        arousal: Math.max(0.28, onset + audio.mid * 0.35),
        confidence: 0.62,
        decay: 0.012,
        attention: 0.45 + audio.bass * 0.25
      });
    }
    State.audioPulses = (State.audioPulses || 0) + count;
  }

  function spawnEmotionalGhost(State, mouthPool, mood) {
    const K = window.ParticleKernel;
    if (!mouthPool || !K || State.reducedMotion) return;
    const lane = (State.emotionalGhosts || []).length % 3;
    const x = (lane - 1) * 0.22;
    K.spawn(mouthPool, x, 0.42 + lane * 0.04, {
      kind: 3, zone: 2, valence: 0.15, arousal: 0.22, confidence: 0.35, decay: 0.0028, attention: 0.4
    });
    State.emotionalGhosts = (State.emotionalGhosts || []).concat(mood || State.mood || "idle").slice(-12);
  }

  window.MASTER_FACE_PARTICLES = Object.freeze({
    kernelStepContext,
    spawnEmotionalGhost,
    reactAudio,
    audio: () => ({ ...audio })
  });
})();
