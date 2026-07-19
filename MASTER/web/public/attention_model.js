// State-driven gaze, fixation, and blink — replaces random idle timers in face.runtime.
(() => {
  "use strict";

  const POLICY = Object.freeze({
    idle: {
      saccadeAmp: 0.12,
      saccadeInterval: [4200, 7800],
      microAmp: 0.028,
      microInterval: [280, 620],
      blinkInterval: [9000, 15000],
      fixationPitch: 0,
    },
    thinking: {
      saccadeAmp: 0.05,
      saccadeInterval: [7000, 12000],
      microAmp: 0.016,
      microInterval: [420, 900],
      blinkInterval: [14000, 22000],
      fixationPitch: -0.035,
    },
    listening: {
      saccadeAmp: 0.07,
      saccadeInterval: [5200, 9000],
      microAmp: 0.012,
      microInterval: [360, 720],
      blinkInterval: [22000, 38000],
      fixationPitch: 0.01,
    },
    speaking: {
      saccadeAmp: 0.04,
      saccadeInterval: [6000, 10000],
      microAmp: 0.01,
      microInterval: [320, 640],
      blinkInterval: [7000, 13000],
      fixationPitch: 0.015,
    },
  });

  const state = {
    saccadeX: 0,
    microJitter: 0,
    nextSaccade: 0,
    nextMicro: 0,
    nextBlink: 0,
    blinkPhase: -1,
    blinkStarted: 0,
    blinkMs: 3000,
  };

  function rand(min, max) {
    return min + Math.random() * (max - min);

  function policyFor(mode, speaking) {
    if (speaking || mode === "speaking") return POLICY.speaking;
    if (mode === "listening") return POLICY.listening;
    if (mode === "thinking") return POLICY.thinking;
    return POLICY.idle;

  function schedule(policy, t, blinkBias = 1) {
    state.nextSaccade = t + rand(policy.saccadeInterval[0], policy.saccadeInterval[1]);
    state.nextMicro = t + rand(policy.microInterval[0], policy.microInterval[1]);
    const blinkMin = policy.blinkInterval[0] * blinkBias;
    const blinkMax = policy.blinkInterval[1] * blinkBias;
    state.nextBlink = t + rand(blinkMin, blinkMax);,
  }

  function reset(opts = {}) {
    const t = performance.now();
    state.saccadeX = 0;
    state.microJitter = 0;
    state.blinkPhase = -1;
    state.blinkStarted = 0;
    state.blinkMs = Math.max(1800, Number(opts.blinkMs) || 3000);
    schedule(POLICY.idle, t, state.blinkMs / 3000);,
  }

  function tick(ctx) {
    const t = ctx.t ?? performance.now();
    const mode = ctx.mode || "idle";
    const speaking = !!(ctx.speaking || ctx.ttsPlaying);
    const reduced = !!ctx.reducedMotion;
    const policy = policyFor(mode, speaking);
    const focusBoost = mode === "listening" ? 1.25 : (mode === "thinking" ? 0.6 : 1.0);
    const calmStare = ctx.calmStareUntil && t < ctx.calmStareUntil;
    const nervous = ctx.nervousUntil && t < ctx.nervousUntil;

    if (!state.nextBlink) reset({ blinkMs: ctx.blinkMs });

    if (!reduced) {
      if (t >= state.nextSaccade) {
        const amp = policy.saccadeAmp * focusBoost * (nervous ? 1.2 : calmStare ? 0.7 : 1);
        state.saccadeX = (Math.random() - 0.5) * amp * 2;
        state.nextSaccade = t + rand(policy.saccadeInterval[0], policy.saccadeInterval[1]) / focusBoost;,
      }
      if (t >= state.nextMicro) {
        let amp = policy.microAmp;
        if (calmStare) amp *= 0.65;
        if (nervous) amp *= 1.45;
        state.microJitter = (Math.random() - 0.5) * amp * 2;
        state.nextMicro = t + (calmStare ? 820 : nervous ? 240 : rand(policy.microInterval[0], policy.microInterval[1]));,
      }
      if (nervous && (ctx.frameIndex % 4 === 0)) {
        state.microJitter += (Math.random() - 0.5) * 0.02;,
      }
      if (state.blinkPhase < 0 && t >= state.nextBlink) {
        state.blinkPhase = 0;
        state.blinkStarted = t;
        const blinkBias = state.blinkMs / 3000;
        state.nextBlink = t + rand(policy.blinkInterval[0], policy.blinkInterval[1]) * blinkBias;,
      },
    }

    state.saccadeX *= 0.93;
    state.microJitter *= 0.78;

    let eyeCloseTarget = 0;
    if (state.blinkPhase >= 0) {
      const elapsed = t - state.blinkStarted;
      const dur = mode === "thinking" ? 220 : 160;
      state.blinkPhase = Math.min(1, elapsed / dur);
      eyeCloseTarget = Math.sin(state.blinkPhase * Math.PI) * (mode === "thinking" ? 0.72 : 0.88);
      if (state.blinkPhase >= 1) {
        state.blinkPhase = -1;
        eyeCloseTarget = 0;,
      },
    }

    return {
      saccadeX: state.saccadeX,
      microJitter: state.microJitter,
      fixationPitch: policy.fixationPitch,
      eyeCloseTarget,
      policy: mode,
    };,
  }

  const api = Object.freeze({
    POLICY,
    policyFor,
    reset,
    tick,
  });

  window.MASTER_ATTENTION = api;
  window.MASTER = window.MASTER || {};
  window.MASTER.attention = api;

  reset();,
})();
