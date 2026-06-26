// Particle pool stepping — mouth bursts, viseme coupling, compact cadence (web_001).
(() => {
  "use strict";

  const COMPACT_INTERVAL = 128;
  let compactFrame = 0;

  const VISEME_VALENCE = { A: 0.35, E: 0.2, I: 0.45, O: 0.15, M: -0.1, U: 0.1, neutral: 0 };

  function kernelStepContext(State) {
    const pr = State.pressureFields || {};
    const moodArc = State.moodArc || {};
    const speaking = State.mode === "speaking" || !!window.MASTER_FACE?.tts?.playing;
    const baseEntropy = Number.isFinite(pr.entropy) ? pr.entropy : (State.entropy || 0);
    const arousal = Number(State.pulse ?? State.expressionCurrent?.arousal ?? 0.35);
    const radial = Number(pr.radial ?? (Number(pr.pct) || 0) / 100);
    return {
      entropy: speaking ? baseEntropy * 0.82 : baseEntropy,
      pressure: Math.min(1, radial) + (speaking ? 0.08 : 0),
      pressureRadial: radial,
      pressureCx: Number(State.pressureCx ?? 0),
      pressureCy: Number(State.pressureCy ?? 0.02),
      confidence: State.confidence ?? 0.75,
      decayScale: speaking ? 0.88 : (Number.isFinite(moodArc.decay_rate) ? moodArc.decay_rate : 1),
      spatialRepulsion: (speaking || arousal > 0.42) && !State.reducedMotion,
      repelStrength: 0.004 + arousal * 0.008
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

  function burstViseme(pool, shape, amp) {
    const K = window.ParticleKernel;
    const st = window.MASTER_FACE?.State || window.State || {};
    if (!K || !pool || st.reducedMotion || st.hidden) return;
    const valence = VISEME_VALENCE[shape] ?? 0;
    const arousal = Math.min(1, (Number(amp) || 0.5) * 0.85);
    const spawnN = arousal > 0.55 ? 2 : 1;
    for (let n = 0; n < spawnN && pool.count < pool.capacity; n++) {
      const jitter = (Math.random() - 0.5) * 0.06;
      K.spawn(pool, jitter, (Math.random() - 0.5) * 0.04, {
        kind: 1,
        zone: 1,
        valence,
        arousal,
        attention: arousal * 0.6,
        confidence: 0.55 + arousal * 0.35,
        vx: (Math.random() - 0.5) * 0.012,
        vy: (Math.random() - 0.5) * 0.008,
        decay: 0.014 + arousal * 0.01
      });
      if (arousal > 0.35) {
        K.spawn(pool, jitter * 1.4, (Math.random() - 0.5) * 0.05, {
          kind: 1, zone: 1, valence: valence * 0.7, arousal: arousal * 0.8,
          vx: jitter * 0.2, vy: -0.006, decay: 0.016
        });
      }
    }
  }

  function anticipateSpeech(pool, count = 1) {
    const K = window.ParticleKernel;
    const st = window.MASTER_FACE?.State || window.State || {};
    if (!K || !pool || st.reducedMotion) return;
    const n = Math.min(4, Math.max(1, count));
    for (let i = 0; i < n && pool.count < pool.capacity; i++) {
      K.spawn(pool, (Math.random() - 0.5) * 0.08, 0.02 + Math.random() * 0.04, {
        kind: 1,
        zone: 1,
        valence: 0.25,
        arousal: 0.45,
        attention: 0.5,
        confidence: 0.7,
        decay: 0.012
      });
    }
    st.pulse = Math.max(st.pulse || 0, 0.28);
  }

  function maybeCompactPools(...pools) {
    compactFrame += 1;
    if ((compactFrame & (COMPACT_INTERVAL - 1)) !== 0) return;
    const K = window.ParticleKernel;
    if (!K?.compact) return;
    pools.forEach((pool) => { if (pool) K.compact(pool); });
  }

  window.MASTER_FACE_PARTICLES = Object.freeze({
    kernelStepContext,
    spawnEmotionalGhost,
    burstViseme,
    anticipateSpeech,
    maybeCompactPools,
    COMPACT_INTERVAL
  });
})();