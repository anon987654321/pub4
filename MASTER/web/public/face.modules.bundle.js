// public/face_blendshape_bridge.js
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

// public/face_particles.js
(() => {
  "use strict";
  function kernelStepContext(State) {
    const pr = State.pressureFields || {};
    const moodArc = State.moodArc || {};
    return {
      entropy: Number.isFinite(pr.entropy) ? pr.entropy : State.entropy || 0,
      pressure: Math.min(1, (Number(pr.pct) || 0) / 100),
      confidence: State.confidence ?? 0.75,
      decayScale: Number.isFinite(moodArc.decay_rate) ? moodArc.decay_rate : 1
    };
  }
  function spawnEmotionalGhost(State, mouthPool, mood) {
    const K = window.ParticleKernel;
    if (!mouthPool || !K || State.reducedMotion) return;
    const lane = (State.emotionalGhosts || []).length % 3;
    const x = (lane - 1) * 0.22;
    K.spawn(mouthPool, x, 0.42 + lane * 0.04, {
      kind: 3,
      zone: 2,
      valence: 0.15,
      arousal: 0.22,
      confidence: 0.35,
      decay: 28e-4,
      attention: 0.4
    });
    State.emotionalGhosts = (State.emotionalGhosts || []).concat(mood || State.mood || "idle").slice(-12);
  }
  window.MASTER_FACE_PARTICLES = Object.freeze({
    kernelStepContext,
    spawnEmotionalGhost
  });
})();

// public/face_audio_bridge.js
(() => {
  "use strict";
  function applySttDuck(State, tts, actx) {
    if (!State.sttActive || State.sttDuck <= 0.02) return false;
    State.sttDuck = Math.max(0, State.sttDuck - 0.06);
    const duckTarget = 0.12 + State.sttDuck * 0.18;
    if (tts?.outputGain && actx) {
      tts.outputGain.gain.setTargetAtTime(duckTarget, actx.currentTime, 0.04);
    } else if (tts?.audio) {
      tts.audio.volume = Math.min(tts.audio.volume, duckTarget);
    }
    return true;
  }
  const TTS_PLAYBACK_GAIN = 1.9;
  function restorePlaybackGain(tts, actx, playing) {
    if (!playing) return;
    if (tts?.outputGain && actx) {
      tts.outputGain.gain.setTargetAtTime(tts.playbackGain || TTS_PLAYBACK_GAIN, actx.currentTime, 0.08);
    } else if (tts?.audio) {
      tts.audio.volume = 1;
    }
  }
  window.MASTER_FACE_AUDIO = Object.freeze({
    applySttDuck,
    restorePlaybackGain
  });
})();

// public/face_tts_bridge.js
(() => {
  "use strict";
  function syncStyleIndicator(style) {
    const indicator = document.getElementById("tts-style-indicator");
    if (indicator) indicator.textContent = style || "";
    document.documentElement.dataset.ttsStyle = style || "";
  }
  function effortSpawnCount(style) {
    return /energetic|dramatic|intense|storyteller/i.test(String(style || "")) ? 3 : 1;
  }
  window.MASTER_FACE_TTS = Object.freeze({
    syncStyleIndicator,
    effortSpawnCount
  });
})();

// public/face_expression_bridge.js
(() => {
  "use strict";
  const SIGNAL_TTL_MS = 4200;
  const signalStack = [];
  function pushSignal(detail = {}) {
    signalStack.push({
      at: performance.now(),
      entropy: Number(detail.entropy ?? 0.2),
      confidence: Number(detail.confidence ?? 0.75),
      arousal: Number(detail.arousal ?? detail.expression?.arousal ?? 0.4),
      valence: Number(detail.valence ?? detail.expression?.valence ?? 0),
      mode: detail.mode || detail.name || "event"
    });
    while (signalStack.length > 8) signalStack.shift();
  }
  function blendSignals(now = performance.now()) {
    const live = signalStack.filter((row) => now - row.at < SIGNAL_TTL_MS);
    if (!live.length) return null;
    let wSum = 0;
    const out = { entropy: 0, confidence: 0, arousal: 0, valence: 0 };
    live.forEach((row) => {
      const w = 1 - (now - row.at) / SIGNAL_TTL_MS;
      wSum += w;
      out.entropy += row.entropy * w;
      out.confidence += row.confidence * w;
      out.arousal += row.arousal * w;
      out.valence += row.valence * w;
    });
    if (wSum <= 0) return null;
    return {
      entropy: out.entropy / wSum,
      confidence: out.confidence / wSum,
      arousal: out.arousal / wSum,
      valence: out.valence / wSum
    };
  }
  function pushMoodArcSample(State, detail) {
    State.moodArcSamples = State.moodArcSamples || [];
    State.moodArcSamples.push({
      entropy: detail.entropy ?? State.entropy ?? 0.2,
      valence: detail.valence ?? detail.expression?.valence ?? 0,
      arousal: detail.arousal ?? detail.expression?.arousal ?? State.pulse ?? 0.4
    });
    if (State.moodArcSamples.length > 16) State.moodArcSamples.shift();
    if (!State.sessionBaseline && State.moodArcSamples.length >= 6) {
      const samples2 = State.moodArcSamples;
      const mean2 = (key) => samples2.reduce((sum, row) => sum + (row[key] || 0), 0) / samples2.length;
      State.sessionBaseline = {
        entropy: mean2("entropy"),
        valence: mean2("valence"),
        arousal: mean2("arousal")
      };
    }
    const samples = State.moodArcSamples;
    const mean = (key) => samples.reduce((sum, row) => sum + (row[key] || 0), 0) / samples.length;
    const meanEntropy = mean("entropy");
    const base = State.sessionBaseline;
    const drift = base ? 0.12 : 0;
    State.moodArc = {
      entropy: meanEntropy * (1 - drift) + (base?.entropy ?? meanEntropy) * drift,
      valence: mean("valence") * (1 - drift) + (base?.valence ?? 0) * drift,
      arousal: mean("arousal") * (1 - drift) + (base?.arousal ?? 0.45) * drift,
      decay_rate: meanEntropy > 0.55 ? 0.32 : 0.68
    };
  }
  function persistMood(State) {
    try {
      localStorage.setItem("master:mood", State.mood || "idle");
      localStorage.setItem("master:mode", State.mode || "idle");
    } catch (err) {
      window.MASTER_LOG?.warn?.("face_expression_bridge:persist_mood", err);
    }
  }
  function restoreMood(State) {
    try {
      const mood = localStorage.getItem("master:mood");
      const mode = localStorage.getItem("master:mode");
      if (mood) State.mood = mood;
      if (mode && State.mode === "idle") State.mode = mode;
    } catch (err) {
      window.MASTER_LOG?.warn?.("face_expression_bridge:restore_mood", err);
    }
  }
  async function postUserExpression(expression, source = "face_drag") {
    const body = new URLSearchParams({
      topic: "user:expression",
      "payload[source]": source,
      "payload[valence]": String(expression.valence ?? 0),
      "payload[arousal]": String(expression.arousal ?? 0),
      "payload[attention]": String(expression.attention ?? 0.5)
    });
    try {
      await fetch("/canvas/event", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body, keepalive: true });
    } catch (err) {
      window.MASTER_LOG?.warn?.("face_expression_bridge:post_expression", err);
    }
    window.dispatchEvent(new CustomEvent("user:expression", {
      detail: { expression, source, blendshapes: expression.blendshapes || null }
    }));
  }
  window.MASTER_FACE_EXPRESSION = Object.freeze({
    pushSignal,
    blendSignals,
    pushMoodArcSample,
    persistMood,
    restoreMood,
    postUserExpression
  });
})();

// public/face_council_multi.js
(() => {
  "use strict";
  const LANES = [
    { id: "left", personas: ["Architect", "Mentor"], x: "18%" },
    { id: "center", personas: ["Pragmatist", "User"], x: "50%" },
    { id: "right", personas: ["Skeptic", "Security"], x: "82%" }
  ];
  let strip = null;
  let activeCouncil = false;
  function ensureStrip() {
    if (strip) return strip;
    strip = document.createElement("div");
    strip.id = "council-multi-face";
    strip.className = "council-multi-face";
    strip.setAttribute("aria-hidden", "true");
    strip.innerHTML = LANES.map(
      (lane) => `<span class="council-lane" data-lane="${lane.id}" style="left:${lane.x}"></span>`
    ).join("");
    document.body.appendChild(strip);
    return strip;
  }
  function setLaneActive(lane, persona) {
    const el = ensureStrip().querySelector(`[data-lane="${lane}"]`);
    if (!el) return;
    el.dataset.persona = persona || "";
    el.dataset.active = "1";
    el.classList.add("pulse");
    setTimeout(() => el.classList.remove("pulse"), 900);
  }
  function clearLanes() {
    if (!strip) return;
    strip.querySelectorAll(".council-lane").forEach((el) => {
      delete el.dataset.active;
      delete el.dataset.persona;
    });
    strip.dataset.visible = "0";
    activeCouncil = false;
    document.body.dataset.councilMulti = "";
  }
  function personaLane(persona) {
    const name = String(persona || "");
    const hit = LANES.find((lane) => lane.personas.includes(name));
    return hit?.id || "center";
  }
  function onCouncilStart() {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("council_multi_face")) return;
    activeCouncil = true;
    ensureStrip().dataset.visible = "1";
    document.body.dataset.councilMulti = "1";
    window.MASTERVisual?.event?.("council:multi:start", { topology: "papua-mask", entropy: 0.38, confidence: 0.62, mode: "council" });
  }
  window.addEventListener("master:visual", (ev) => {
    const d = ev.detail || {};
    const name = String(d.name || d.mode || "");
    if (/council:deliberation|council:start/i.test(name)) onCouncilStart();
    if (/council:(?:vote|speech|end)|tribunal:rendered/i.test(name)) clearLanes();
  });
  window.addEventListener("tts:style:active", (ev) => {
    const persona = ev.detail?.persona;
    if (!persona || !activeCouncil) return;
    setLaneActive(personaLane(persona), persona);
  });
  window.MASTERCouncilMulti = Object.freeze({
    personaLane,
    setLaneActive,
    clearLanes,
    onCouncilStart
  });
})();

// public/face_phosphor_trail.js
(() => {
  "use strict";
  const aesthetic = window.MASTER_RUNTIME?.aesthetic || document.documentElement.dataset.aesthetic;
  if (aesthetic === "wscons") return;
  const TRAIL_DECAY = 0.86;
  let trailCanvas = null;
  let trailCtx = null;
  function ensureTrail(w, h) {
    if (!trailCanvas) {
      trailCanvas = document.createElement("canvas");
      trailCanvas.id = "face-phosphor-trail";
      trailCanvas.style.cssText = "position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:1;opacity:0.46;mix-blend-mode:screen;image-rendering:pixelated";
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

// public/face_offscreen_ecology.js
(() => {
  "use strict";
  if (typeof OffscreenCanvas === "undefined") return;
  const E = window.MASTEREcology;
  if (!E?.canvas || !E?.ctx) return;
  try {
    const probe = new OffscreenCanvas(4, 4);
    if (!probe.getContext("2d")) return;
    const w = E.internalW || E.canvas.width;
    const h = E.internalH || E.canvas.height;
    const off = new OffscreenCanvas(w, h);
    const offCtx = off.getContext("2d", { alpha: true });
    if (!offCtx) return;
    E.offscreen = off;
    E.offscreenCtx = offCtx;
    E.drawToOffscreen = () => {
      if (!E.offscreenCtx) return;
      E.offscreenCtx.drawImage(E.canvas, 0, 0);
    };
    E.blitOffscreen = () => {
      if (!E.offscreen || !E.ctx) return;
      const bitmap = E.offscreen.transferToImageBitmap?.();
      if (bitmap) {
        E.ctx.clearRect(0, 0, E.canvas.width, E.canvas.height);
        E.ctx.drawImage(bitmap, 0, 0);
        bitmap.close?.();
        return;
      }
      E.drawToOffscreen?.();
    };
    window.MASTER_OFFSCREEN_ECOLOGY = true;
  } catch (err) {
    window.MASTER_LOG?.warn?.("face_offscreen_ecology:setup", err);
  }
})();

// public/face_micro_interactions.js
(() => {
  "use strict";
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const cv = document.getElementById("face");
  const K = () => window.ParticleKernel;
  const face = () => window.MASTER_FACE;
  const st = () => face()?.State;
  const eyePool = () => face()?.eyePool || window.eyePool;
  const mouthPool = () => face()?.mouthPool || window.mouthPool;
  function boostEye(delta = 0.12) {
    const pool = eyePool();
    const kernel = K();
    if (!pool || !kernel) return;
    for (let i = 0; i < pool.count; i++) if (pool.alive[i]) {
      const b = i * kernel.FIELDS_PER_CELL;
      pool.cells[b + kernel.FIELD.attention] = Math.min(1, (pool.cells[b + kernel.FIELD.attention] || 0.5) + delta);
    }
  }
  function spawnCrown(n = 2, opts = {}) {
    const pool = eyePool();
    const kernel = K();
    if (!pool || !kernel) return;
    for (let i = 0; i < n; i++) {
      kernel.spawn(pool, (Math.random() - 0.5) * 0.35, -0.55 + Math.random() * 0.12, {
        kind: 3,
        zone: 13,
        valence: opts.valence ?? 0.35,
        confidence: opts.confidence ?? 0.82,
        attention: opts.attention ?? 0.7,
        decay: opts.decay ?? 7e-3
      });
    }
  }
  function mouthPressure(delta = 0.18) {
    const pool = mouthPool();
    const kernel = K();
    if (!pool || !kernel) return;
    for (let i = 0; i < pool.count; i++) if (pool.alive[i]) {
      const b = i * kernel.FIELDS_PER_CELL;
      pool.cells[b + kernel.FIELD.pressure] = Math.min(1, (pool.cells[b + kernel.FIELD.pressure] || 0) + delta);
    }
  }
  setInterval(() => {
    const ecology = window.MASTEREcology;
    if (!ecology?.agents) return;
    const pool = eyePool();
    const kernel = K();
    if (!pool || !kernel) return;
    let attn = 0, n = 0;
    for (let i = 0; i < pool.count; i++) if (pool.alive[i]) {
      const b = i * kernel.FIELDS_PER_CELL;
      attn += pool.cells[b + kernel.FIELD.attention] || 0;
      n++;
    }
    if (!n) return;
    const focus = attn / n;
    const tighten = 0.88 + focus * 0.12;
    ecology.agents.forEach((agent) => {
      const base = agent._radiusBase ?? agent.radius;
      agent._radiusBase = base;
      agent.radius = base * tighten;
    });
  }, 520);
  window.addEventListener("master:visual", (ev) => {
    const name = String(ev.detail?.name || ev.detail?.mode || "");
    if (/memory|retriev|context|compact/.test(name)) spawnCrown(2, { valence: 0.42 });
    if (/photo:ready|input:photo/.test(name)) spawnCrown(3, { valence: 0.55, confidence: 0.9 });
  });
  const breathScale = reducedMotion ? 0.42 : 1;
  setInterval(() => {
    const state = st();
    if (!state) return;
    if (state._breathScale == null) state._breathScale = breathScale;
    state.breath = Math.min(1.4, (state.breath || 1) * state._breathScale + (1 - state._breathScale) * 0.08);
  }, 900);
  if (cv) {
    cv.addEventListener("pointermove", (e) => {
      const state = st();
      if (!state) return;
      const nx = (e.clientX / innerWidth - 0.5) * 2;
      const ny = (e.clientY / innerHeight - 0.5) * 2;
      state.eyeMaskBiasX = (state.eyeMaskBiasX || 0) * 0.82 + nx * 0.06;
      state.eyeMaskBiasY = (state.eyeMaskBiasY || 0) * 0.82 + ny * 0.04;
      if (face()?.faceMat?.uniforms?.uMouse) {
        face().faceMat.uniforms.uMouse.value.x = nx;
        face().faceMat.uniforms.uMouse.value.y = ny;
      }
    }, { passive: true });
  }
  if (cv) {
    cv.addEventListener("pointermove", (e) => {
      const edge = Math.min(e.clientX, innerWidth - e.clientX, e.clientY, innerHeight - e.clientY);
      if (edge > 72) return;
      const state = st();
      if (!state) return;
      state.pulse = Math.max(state.pulse || 0, 0.08 + (1 - edge / 72) * 0.22);
    }, { passive: true });
  }
  if (reducedMotion) {
    let phase = 0;
    setInterval(() => {
      phase += 0.08;
      const state = st();
      if (!state) return;
      state.mouseX = Math.sin(phase) * 0.35;
      state.mouseY = Math.cos(phase * 0.7) * 0.18;
      boostEye(0.03);
    }, 120);
  }
  window.addEventListener("chat:chunk", () => boostEye(0.05));
  const origChunk = window._chatOnChunk;
  if (typeof origChunk === "function") {
    window._chatOnChunk = (raw) => {
      window.dispatchEvent(new CustomEvent("chat:chunk", { detail: { raw } }));
      if (/[.!?]\s*$/.test(String(raw || ""))) mouthPressure(0.14);
      return origChunk(raw);
    };
  }
  window.addEventListener("chat:dmesg", (ev) => {
    const line = String(ev.detail?.line || "");
    if (!/veto|pass/i.test(line)) return;
    window.MASTEREcology?.burst?.(5, /pass/i.test(line) ? 0.18 : 0.32);
    if (/pass/i.test(line)) boostEye(0.08);
    else mouthPressure(-0.12);
  });
  window.addEventListener("master:visual", (ev) => {
    if (/stt:start|listening/.test(String(ev.detail?.name || ev.detail?.mode || ""))) boostEye(0.18);
  });
  setInterval(() => {
    const state = st();
    if (!state) return;
    const drive = Math.min(1, (state.mouthDrive || 0) + (state.visemeAmp || 0) * 0.35);
    window.MASTER_FACE_BLEND?.applyMouthDrive?.(drive, state.visemeAmp || 0);
    const mat = face()?.faceMat;
    if (mat?.uniforms?.uJaw) mat.uniforms.uJaw.value = Math.max(mat.uniforms.uJaw.value, drive * 0.42);
  }, 48);
  setInterval(() => {
    if (!cv) return;
    const state = st();
    const mode = state?.mode || document.documentElement.dataset.masterMode || "idle";
    const conf = Number(document.documentElement.style.getPropertyValue("--master-confidence") || 0.86);
    cv.setAttribute("aria-label", `MASTER face \u2014 ${mode}, confidence ${Math.round(conf * 100)}%`);
  }, 2e3);
  window.MASTER_FACE_MICRO = Object.freeze({ boostEye, spawnCrown, mouthPressure });
})();

// public/face_perf_guards.js
(() => {
  "use strict";
  const MIN_KERNEL_DT = 8e-3;
  const RESIZE_THRESHOLD = 50;
  let lastResizeW = 0;
  let lastResizeH = 0;
  if (window.ParticleKernel && typeof window.ParticleKernel.step === "function") {
    const origStep = window.ParticleKernel.step;
    window.ParticleKernel.step = function stepGuarded(pool, dt, ctx = {}) {
      const clamped = Math.max(MIN_KERNEL_DT, Math.min(0.05, Number(dt) || MIN_KERNEL_DT));
      const next = { ...ctx };
      if (window.MASTER_RUNTIME?.enhancements?.includes?.("spatial_repulsion_2d")) {
        next.spatialRepulsion = true;
      }
      return origStep.call(this, pool, clamped, next);
    };
  }
  window.addEventListener("primer:ready", () => {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("particle_worker")) return;
    try {
      const worker = new Worker(window.MASTER_ASSET_PATHS?.faceModules?.particle_worker || "/particle_worker.js");
      worker.postMessage({ type: "warm", dt: 0.016 });
      setTimeout(() => worker.terminate(), 120);
    } catch (err) {
      window.MASTER_LOG?.warn?.("face_perf_guards:worker_warm", err);
    }
  });
  window.addEventListener("visual:ready", () => {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("primer_kernel_spawn")) return;
    const K = window.ParticleKernel;
    const pool = window.MASTER_FACE?.eyePool || window.eyePool;
    if (!K || !pool) return;
    for (let i = 0; i < 4; i++) {
      K.spawn(pool, (Math.random() - 0.5) * 0.3, (Math.random() - 0.5) * 0.2, {
        kind: 2,
        zone: 2,
        attention: 0.85,
        confidence: 0.9,
        decay: 0.01
      });
    }
  });
  window.addEventListener("master:visual", (ev) => {
    const name = String(ev.detail?.name || "");
    if (/autocommit|auto.commit|auto_commit/i.test(name)) {
      const K = window.ParticleKernel;
      const pool = window.MASTER_FACE?.eyePool || window.eyePool;
      if (!K || !pool) return;
      for (let i = 0; i < 5; i++) {
        K.spawn(pool, (Math.random() - 0.5) * 0.25, -0.5 + Math.random() * 0.1, {
          kind: 3,
          zone: 13,
          valence: 0.75,
          confidence: 0.95,
          decay: 6e-3
        });
      }
      window.MASTERVisual?.event?.("autocommit:joy", { topology: "papua-mask", entropy: 0.1, confidence: 0.96, mode: "commit" });
    }
  });
  let streamStartAt = 0;
  window.addEventListener("chat:chunk", () => {
    if (!streamStartAt) streamStartAt = performance.now();
    const elapsed = performance.now() - streamStartAt;
    if (elapsed > 12e3) {
      const st = window.MASTER_FACE?.State;
      if (st) st.mouseX = Math.sin(elapsed * 4e-4) * 0.12;
    }
  });
  window.addEventListener("master:visual", (ev) => {
    if (/llm:request|pipeline:start|thinking/.test(String(ev.detail?.name || ""))) streamStartAt = performance.now();
    if (/complete|done|error/.test(String(ev.detail?.name || ""))) streamStartAt = 0;
  });
  window.MASTER_FACE_PERF = Object.freeze({
    resizeThreshold: RESIZE_THRESHOLD,
    minKernelDt: MIN_KERNEL_DT,
    shouldResize(w, h) {
      if (Math.abs(w - lastResizeW) < RESIZE_THRESHOLD && Math.abs(h - lastResizeH) < RESIZE_THRESHOLD) return false;
      lastResizeW = w;
      lastResizeH = h;
      return true;
    }
  });
})();

// public/face_brutalist.js
(() => {
  "use strict";
  const PROFILES = window.MASTER_RUNTIME?.ui_philosophy?.profiles || [];
  const hasBrutalist = PROFILES.some((p) => (typeof p === "string" ? p : p.id) === "brutalist") || window.MASTER_RUNTIME?.enhancements?.includes?.("brutalist_profile");
  function applyWscons() {
    document.documentElement.dataset.runtimeProfile = "wscons";
    document.documentElement.style.setProperty("--transition-fast", "0ms");
    document.documentElement.style.setProperty("--transition-normal", "0ms");
    document.documentElement.style.setProperty("--ease-out", "steps(2,end)");
    document.documentElement.style.setProperty("--face-phosphor-decay", "0");
    document.documentElement.style.setProperty("--c-text", "#63c363");
    document.documentElement.style.setProperty("--x-text", "#63c363");
    document.body.classList.add("wscons-mode");
  }
  function applyBrutalist() {
    document.documentElement.dataset.runtimeProfile = "brutalist";
    document.documentElement.style.setProperty("--transition-fast", "0ms");
    document.documentElement.style.setProperty("--transition-normal", "0ms");
    document.documentElement.style.setProperty("--ease-out", "steps(2,end)");
    document.documentElement.style.setProperty("--face-phosphor-decay", "0");
    document.documentElement.style.setProperty("--face-glow-scale", "1.0");
    document.body.classList.add("brutalist-mode");
  }
  const aesthetic = window.MASTER_RUNTIME?.aesthetic || document.documentElement.dataset.aesthetic || "brutalist";
  if (aesthetic === "wscons") applyWscons();
  else if (aesthetic !== "phosphor") applyBrutalist();
  const primer = document.getElementById("primer");
  if (primer) {
    primer.addEventListener("pointerdown", () => {
      document.body.dataset.primerFlash = "1";
      setTimeout(() => delete document.body.dataset.primerFlash, 180);
    }, { passive: true });
  }
  const cursor = document.querySelector("#zin, #input");
  if (cursor) {
    let primerPulse = 0;
    setInterval(() => {
      primerPulse = (primerPulse + 1) % 2;
      const blink = document.querySelector(".cursor");
      if (!blink) return;
      const primerLive = document.getElementById("primer")?.classList.contains("gone");
      if (primerLive) blink.style.animationDuration = primerPulse ? "600ms" : "900ms";
    }, 450);
  }
  let idleSince = performance.now();
  const zin = document.getElementById("zin");
  setInterval(() => {
    if (!zin || document.activeElement === zin || zin.value) {
      idleSince = performance.now();
      return;
    }
    if (performance.now() - idleSince < 18e3) return;
    const hint = document.getElementById("idle-help-trail");
    if (!hint) {
      const el = document.createElement("div");
      el.id = "idle-help-trail";
      el.className = "idle-help-trail";
      el.textContent = "\u2193 ask";
      document.body.appendChild(el);
    }
    document.body.dataset.longSilence = "1";
  }, 2e3);
  window.MASTER_BRUTALIST = Object.freeze({ apply: applyBrutalist, pushLine });
})();
