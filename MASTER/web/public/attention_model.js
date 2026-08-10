// State-driven gaze, fixation, and blink — replaces random idle timers in face.runtime.
(() => {
  "use strict";

  // Blink intervals are the strongest single cue for "alive", and the old ones
  // sat far outside human physiology: measured over ten simulated minutes, this
  // face blinked 5.1/min idle, 3.4 thinking, 5.9 speaking and 2.1 listening —
  // one blink every 29 seconds while holding your gaze. A person who does that
  // does not read as composed, they read as dead. Humans rest at 15-20/min and
  // blink MORE while speaking, not less; the old table had that inverted.
  //
  // The "future-human" intent in VOICE_IDLE_SIGNATURES ("composed, steady gaze,
  // still baseline, slow deliberate blink") was right and was implemented as
  // less motion, which crosses from composed into inanimate. Composure is small,
  // smooth, economical motion — not absence of it. So amplitudes stay low and
  // the rates come back inside human range, biased slow: idle ~14/min,
  // listening ~12, thinking ~10, speaking ~18. Operator decision 2026-08-10.
  //
  // Rates above are at blinkBias 1.0; a voice signature's blink_ms scales them.
  const POLICY = Object.freeze({
    idle: {
      saccadeAmp: 0.12,
      saccadeInterval: [4200, 7800],
      microAmp: 0.028,
      microInterval: [280, 620],
      blinkInterval: [3200, 5400],
      fixationPitch: 0,
    },
    thinking: {
      saccadeAmp: 0.05,
      saccadeInterval: [7000, 12000],
      microAmp: 0.016,
      microInterval: [420, 900],
      blinkInterval: [4500, 7500],
      fixationPitch: -0.035,
    },
    listening: {
      saccadeAmp: 0.07,
      saccadeInterval: [5200, 9000],
      microAmp: 0.012,
      microInterval: [360, 720],
      blinkInterval: [3800, 6200],
      fixationPitch: 0.01,
    },
    speaking: {
      saccadeAmp: 0.04,
      saccadeInterval: [6000, 10000],
      microAmp: 0.01,
      microInterval: [320, 640],
      blinkInterval: [2400, 4200],
      fixationPitch: 0.015,
    },
  });

  // A real blink is not symmetric: the lid falls fast and opens slowly, roughly
  // 90ms down and 160ms back. sin(phase * PI) gave an equal rise and fall, which
  // is the shape of a machine cycling a shutter. Closing is eased-in (gravity),
  // opening eased-out (muscle).
  const BLINK_CLOSE_MS = 90;
  const BLINK_OPEN_MS = 160;

  // Ocular drift. Between microsaccades a real eye never holds still — it wanders
  // slowly and is pulled back by fixation. The old model decayed gaze to exactly
  // zero and left it there, so the face settled into perfect stillness, which is
  // the single most statue-like thing it did. This is a bounded random walk with
  // weak mean reversion, deliberately slower and smaller than a microsaccade.
  const DRIFT_STEP = 0.0016;
  const DRIFT_LIMIT = 0.018;
  const DRIFT_RETURN = 0.006;

  const state = {
    saccadeX: 0,
    microJitter: 0,
    driftX: 0,
    nextSaccade: 0,
    nextMicro: 0,
    nextBlink: 0,
    blinkPhase: -1,
    blinkStarted: 0,
    blinkMs: 3000,
    // A second blink queued right behind the first. Real blinks cluster, and a
    // double is common at the end of an utterance; one lone blink on a timer is
    // the tell that a machine is driving it.
    doubleBlink: false,
    lastTick: 0,
  };

  function rand(min, max) {
    return min + Math.random() * (max - min);
  }

  function policyFor(mode, speaking) {
    if (speaking || mode === "speaking") return POLICY.speaking;
    if (mode === "listening") return POLICY.listening;
    if (mode === "thinking") return POLICY.thinking;
    return POLICY.idle;
  }

  function schedule(policy, t, blinkBias = 1) {
    state.nextSaccade = t + rand(policy.saccadeInterval[0], policy.saccadeInterval[1]);
    state.nextMicro = t + rand(policy.microInterval[0], policy.microInterval[1]);
    const blinkMin = policy.blinkInterval[0] * blinkBias;
    const blinkMax = policy.blinkInterval[1] * blinkBias;
    state.nextBlink = t + rand(blinkMin, blinkMax);
  }

  function reset(opts = {}) {
    const t = performance.now();
    state.saccadeX = 0;
    state.microJitter = 0;
    state.driftX = 0;
    state.blinkPhase = -1;
    state.blinkStarted = 0;
    state.doubleBlink = false;
    state.lastTick = t;
    state.blinkMs = Math.max(1800, Number(opts.blinkMs) || 3000);
    schedule(POLICY.idle, t, state.blinkMs / 3000);
  }

  // Blinking as punctuation rather than as a timer. Humans blink at clause
  // boundaries and just after finishing a thought, and that coupling is most of
  // what makes a blink read as intentional. Called by the speech runtime when an
  // utterance ends, and internally on a large gaze shift.
  //
  // `soon` rather than `now`: firing on the exact frame an utterance ends looks
  // mechanically triggered. A short human-plausible lag reads as a person
  // finishing a sentence and settling.
  function cue(kind = "utterance_end") {
    const t = performance.now();
    if (state.blinkPhase >= 0) return;
    const lag = kind === "gaze_shift" ? rand(20, 70) : rand(90, 220);
    state.nextBlink = Math.min(state.nextBlink || Infinity, t + lag);
    // A finished thought usually gets the double; a gaze shift rarely does.
    state.doubleBlink = kind === "utterance_end" && Math.random() < 0.35;
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
    // Persona composure dial, normalized against 0.2 -- the mid-range
    // VOICE_IDLE_SIGNATURES value POLICY.idle's amplitudes were tuned
    // against. A still persona (anchor: saccade 0.10) halves gaze-jitter
    // amplitude; a fidgety one (ezinne: 0.26) adds some. This value was
    // already declared per-persona but never actually wired to anything.
    const composure = Math.max(0.3, Math.min(1.6, Number(ctx.saccade ?? 0.2) / 0.2));

    if (!state.nextBlink) reset({ blinkMs: ctx.blinkMs });

    if (!reduced) {
      if (t >= state.nextSaccade) {
        const amp = policy.saccadeAmp * focusBoost * composure * (nervous ? 1.2 : calmStare ? 0.7 : 1);
        const next = (Math.random() - 0.5) * amp * 2;
        // A gaze shift of any size is one of the two places humans reliably
        // blink. Only the larger ones, so a microsaccade-scale correction does
        // not trigger it.
        if (Math.abs(next - state.saccadeX) > amp * 0.8) cue("gaze_shift");
        state.saccadeX = next;
        state.nextSaccade = t + rand(policy.saccadeInterval[0], policy.saccadeInterval[1]) / focusBoost;
      }
      if (t >= state.nextMicro) {
        let amp = policy.microAmp * composure;
        if (calmStare) amp *= 0.65;
        if (nervous) amp *= 1.45;
        state.microJitter = (Math.random() - 0.5) * amp * 2;
        state.nextMicro = t + (calmStare ? 820 : nervous ? 240 : rand(policy.microInterval[0], policy.microInterval[1]));
      }
      if (nervous && (ctx.frameIndex % 4 === 0)) {
        state.microJitter += (Math.random() - 0.5) * 0.02;
      }
      if (state.blinkPhase < 0 && t >= state.nextBlink) {
        state.blinkPhase = 0;
        state.blinkStarted = t;
        const blinkBias = state.blinkMs / 3000;
        state.nextBlink = t + rand(policy.blinkInterval[0], policy.blinkInterval[1]) * blinkBias;
      }
    }

    state.saccadeX *= 0.93;
    state.microJitter *= 0.78;

    // Ocular drift, scaled by frame time so it does not run at a different speed
    // on a 120Hz display. Weak pull toward centre keeps it bounded without ever
    // parking there — a real eye is never exactly still, and the previous decay
    // to zero is what made the face settle into a waxwork between movements.
    const dt = Math.min(64, Math.max(1, t - (state.lastTick || t)));
    state.lastTick = t;
    if (!reduced) {
      const scale = dt / 16.7;
      state.driftX += (Math.random() - 0.5) * DRIFT_STEP * scale * composure;
      state.driftX -= state.driftX * DRIFT_RETURN * scale;
      state.driftX = Math.max(-DRIFT_LIMIT, Math.min(DRIFT_LIMIT, state.driftX));
    }

    let eyeCloseTarget = 0;
    if (state.blinkPhase >= 0) {
      const elapsed = t - state.blinkStarted;
      // Asymmetric: the lid falls faster than it lifts. `thinking` blinks are
      // heavier and slower, as before, but keep the same shape.
      const slow = mode === "thinking" ? 1.35 : 1;
      const closeMs = BLINK_CLOSE_MS * slow;
      const openMs = BLINK_OPEN_MS * slow;
      const depth = mode === "thinking" ? 0.72 : 0.88;
      if (elapsed <= closeMs) {
        const p = elapsed / closeMs;
        eyeCloseTarget = depth * (p * p); // ease-in falling
        state.blinkPhase = p * 0.4;
      } else if (elapsed <= closeMs + openMs) {
        const p = (elapsed - closeMs) / openMs;
        eyeCloseTarget = depth * (1 - p) * (1 - p * 0.35); // slower, eased lift
        state.blinkPhase = 0.4 + p * 0.6;
      } else {
        state.blinkPhase = -1;
        eyeCloseTarget = 0;
        if (state.doubleBlink) {
          state.doubleBlink = false;
          state.nextBlink = t + rand(90, 180);
        }
      }
    }

    return {
      // Drift rides on top of the saccade so the eye is always in motion, but
      // it is an order of magnitude smaller — this is aliveness, not fidgeting.
      saccadeX: state.saccadeX + state.driftX,
      microJitter: state.microJitter,
      fixationPitch: policy.fixationPitch,
      eyeCloseTarget,
      policy: mode,
    };
  }

  const api = Object.freeze({
    POLICY,
    policyFor,
    reset,
    tick,
    cue,
  });

  window.MASTER_ATTENTION = api;
  window.MASTER = window.MASTER || {};
  window.MASTER.attention = api;

  reset();
})();
