// public/face_blendshape_bridge.js
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
    const arousal = ex.arousal ?? (hi ? 1 : lo ? 0.3 : 0.7);
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

// public/face_particles.js
(() => {
  "use strict";
  const COMPACT_INTERVAL = 128;
  let compactFrame = 0;
  const VISEME_VALENCE = { A: 0.35, E: 0.2, I: 0.45, O: 0.15, M: -0.1, U: 0.1, neutral: 0 };
  function kernelStepContext(State) {
    const pr = State.pressureFields || {};
    const moodArc = State.moodArc || {};
    const speaking = State.mode === "speaking" || !!window.MASTER_FACE?.tts?.playing;
    const baseEntropy = Number.isFinite(pr.entropy) ? pr.entropy : State.entropy || 0;
    const arousal = Number(State.pulse ?? State.expressionCurrent?.arousal ?? 0.35);
    const radial = Number(pr.radial ?? (Number(pr.pct) || 0) / 100);
    return {
      entropy: speaking ? baseEntropy * 0.82 : baseEntropy,
      pressure: Math.min(1, radial) + (speaking ? 0.08 : 0),
      pressureRadial: radial,
      pressureCx: Number(State.pressureCx ?? 0),
      pressureCy: Number(State.pressureCy ?? 0.02),
      confidence: State.confidence ?? 0.75,
      decayScale: speaking ? 0.88 : Number.isFinite(moodArc.decay_rate) ? moodArc.decay_rate : 1,
      spatialRepulsion: (speaking || arousal > 0.42) && !State.reducedMotion,
      repelStrength: 4e-3 + arousal * 8e-3
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
        vy: (Math.random() - 0.5) * 8e-3,
        decay: 0.014 + arousal * 0.01
      });
      if (arousal > 0.35) {
        K.spawn(pool, jitter * 1.4, (Math.random() - 0.5) * 0.05, {
          kind: 1,
          zone: 1,
          valence: valence * 0.7,
          arousal: arousal * 0.8,
          vx: jitter * 0.2,
          vy: -6e-3,
          decay: 0.016
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
    if ((compactFrame & COMPACT_INTERVAL - 1) !== 0) return;
    const K = window.ParticleKernel;
    if (!K?.compact) return;
    pools.forEach((pool) => {
      if (pool) K.compact(pool);
    });
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
  function restorePlaybackGain(tts, actx, playing) {
    if (!playing || !tts?.outputGain || !actx) return;
    tts.outputGain.gain.setTargetAtTime(1.9, actx.currentTime, 0.08);
  }
  window.MASTER_FACE_AUDIO = Object.freeze({
    applySttDuck,
    restorePlaybackGain
  });
})();

// public/face_tts_bridge.js
(() => {
  "use strict";
  const VISEME_LERP = 0.22;
  const WAVE_DECAY = 0.88;
  let visemeTarget = { shape: "neutral", amp: 0 };
  let visemeSmooth = { shape: "neutral", amp: 0 };
  let visemeRaf = 0;
  let queueDepth = 0;
  function syncStyleIndicator(style) {
    const indicator = document.getElementById("tts-style-indicator");
    if (indicator) indicator.textContent = style || "";
    document.documentElement.dataset.ttsStyle = style || "";
  }
  function effortSpawnCount(style) {
    return /energetic|dramatic|intense|storyteller/i.test(String(style || "")) ? 3 : 1;
  }
  function faceState() {
    return window.MASTER_FACE?.State || window.State || {};
  }
  function applySmoothViseme() {
    const st = faceState();
    const ampDelta = visemeTarget.amp - visemeSmooth.amp;
    visemeSmooth.amp += ampDelta * VISEME_LERP;
    if (Math.abs(ampDelta) < 4e-3) visemeSmooth.amp = visemeTarget.amp;
    if (visemeTarget.shape !== visemeSmooth.shape && visemeSmooth.amp < 0.08) {
      visemeSmooth.shape = visemeTarget.shape;
    }
    st.viseme = visemeSmooth.shape;
    st.visemeAmp = visemeSmooth.amp;
    visemeRaf = requestAnimationFrame(applySmoothViseme);
  }
  function setVisemeTarget(shape, amp) {
    visemeTarget = { shape: shape || "neutral", amp: Number.isFinite(amp) ? amp : 0 };
    if (!visemeRaf) visemeRaf = requestAnimationFrame(applySmoothViseme);
  }
  function stopVisemeSmooth() {
    if (visemeRaf) cancelAnimationFrame(visemeRaf);
    visemeRaf = 0;
    visemeTarget = { shape: "neutral", amp: 0 };
    visemeSmooth = { shape: "neutral", amp: 0 };
  }
  function syncQueueBadge() {
    const ui = document.querySelector(".ui-status");
    const tts = window.MASTER_FACE?.tts;
    if (!ui || !tts) return;
    const depth = (tts.queue?.length || 0) + (tts.lanes?.error?.length || 0) + (tts.lanes?.nudge?.length || 0) + (tts.lanes?.response?.length || 0);
    if (depth === queueDepth) return;
    queueDepth = depth;
    if (depth > 1 && tts.playing) ui.dataset.ttsQueue = String(depth);
    else delete ui.dataset.ttsQueue;
  }
  function decayWaveBars() {
    const wave = document.getElementById("zsh-wave");
    if (!wave) return;
    wave.querySelectorAll("span").forEach((bar) => {
      const h = parseFloat(bar.style.height || "4") || 4;
      bar.style.height = `${Math.max(3, h * WAVE_DECAY)}px`;
      const op = parseFloat(bar.style.opacity || "0.25") || 0.25;
      bar.style.opacity = String(Math.max(0.12, op * WAVE_DECAY));
    });
  }
  function onViseme(ev) {
    const { shape, amp } = ev.detail || {};
    setVisemeTarget(shape, amp);
    const pool = window.mouthPool || window.MASTER_FACE?.mouthPool;
    window.MASTER_FACE_PARTICLES?.burstViseme?.(pool, shape, amp);
  }
  function onPlaybackStart(ev) {
    const detail = ev.detail || {};
    document.body.dataset.ttsWave = "1";
    syncStyleIndicator(detail.style || document.documentElement.dataset.ttsStyle);
    const count = effortSpawnCount(detail.style);
    const pool = window.mouthPool || window.MASTER_FACE?.mouthPool;
    window.MASTER_FACE_PARTICLES?.anticipateSpeech?.(pool, count);
    syncQueueBadge();
  }
  function onPlaybackEnd() {
    document.body.dataset.ttsWave = "";
    stopVisemeSmooth();
    const st = faceState();
    st.viseme = "neutral";
    st.visemeAmp = 0;
    decayWaveBars();
    syncQueueBadge();
  }
  function onAnticipate(ev) {
    syncStyleIndicator(ev.detail?.style);
    syncQueueBadge();
  }
  ["tts:viseme", "master:tts:viseme"].forEach((name) => {
    window.addEventListener(name, onViseme);
  });
  ["tts:playback:start", "master:tts:playback:start"].forEach((name) => {
    window.addEventListener(name, onPlaybackStart);
  });
  ["tts:playback:end", "master:tts:playback:end"].forEach((name) => {
    window.addEventListener(name, onPlaybackEnd);
  });
  ["tts:anticipate", "master:tts:anticipate"].forEach((name) => {
    window.addEventListener(name, onAnticipate);
  });
  window.addEventListener("tts:style:active", (ev) => syncStyleIndicator(ev.detail?.style));
  window.MASTER_FACE_TTS = Object.freeze({
    syncStyleIndicator,
    effortSpawnCount,
    setVisemeTarget,
    stopVisemeSmooth,
    syncQueueBadge
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
    } catch (_) {
    }
  }
  function restoreMood(State) {
    try {
      const mood = localStorage.getItem("master:mood");
      const mode = localStorage.getItem("master:mode");
      if (mood) State.mood = mood;
      if (mode && State.mode === "idle") State.mode = mode;
    } catch (_) {
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
    } catch (_) {
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
  } catch (_) {
  }
})();

// public/face_micro_interactions.js
(() => {
  "use strict";
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const cv = document.getElementById("face");
  const face = () => window.MASTER_FACE;
  const st = () => face()?.State;
  const BLEND = () => window.MASTER_FACE_BLEND;
  function boostEye(delta = 0.12) {
    BLEND()?.boostEye?.(delta);
  }
  function spawnCrown(n = 2, opts = {}) {
    BLEND()?.boostEye?.(0.06 * n + (opts.attention ?? 0.12));
    BLEND()?.pushEmotion?.({
      valence: opts.valence ?? 0.35,
      confidence: opts.confidence ?? 0.82,
      focus: opts.attention ?? 0.7
    });
    window.MASTEREcology?.burst?.(n, opts.valence ?? 0.22);
  }
  function mouthPressure(delta = 0.18) {
    BLEND()?.mouthPressure?.(delta);
  }
  setInterval(() => {
    const ecology = window.MASTEREcology;
    if (!ecology?.agents) return;
    const focus = BLEND()?.focusLevel?.() ?? 0.5;
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
    BLEND()?.applyMouthDrive?.(drive, state.visemeAmp || 0);
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
      const speaking = window.MASTER_FACE?.tts?.playing || window.MASTER_FACE?.State?.mode === "speaking";
      if (window.MASTER_RUNTIME?.enhancements?.includes?.("spatial_repulsion_2d") || speaking) {
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
      window.MASTER_LOG?.warn?.("perf:particle_worker_warm", err);
    }
  });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) return;
    window.MASTER_FACE_TTS?.stopVisemeSmooth?.();
  });
  window.addEventListener("visual:ready", () => {
    if (!window.MASTER_RUNTIME?.enhancements?.includes?.("primer_kernel_spawn")) return;
    window.MASTER_FACE_BLEND?.boostEye?.(0.12);
    window.MASTEREcology?.burst?.(3, 0.18);
  });
  window.addEventListener("master:visual", (ev) => {
    const name = String(ev.detail?.name || "");
    if (/autocommit|auto.commit|auto_commit/i.test(name)) {
      window.MASTER_FACE_BLEND?.boostEye?.(0.15);
      window.MASTEREcology?.burst?.(5, 0.22);
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
  function applyBrutalist() {
    document.documentElement.dataset.runtimeProfile = "brutalist";
    document.documentElement.style.setProperty("--transition-fast", "0ms");
    document.documentElement.style.setProperty("--transition-normal", "0ms");
    document.documentElement.style.setProperty("--ease-out", "steps(2,end)");
    document.documentElement.style.setProperty("--face-phosphor-decay", "0.55");
    document.body.classList.add("brutalist-mode");
  }
  if (hasBrutalist || new URLSearchParams(location.search).get("brutalist") === "1") applyBrutalist();
  let strip = document.getElementById("brutalist-strip");
  if (!strip) {
    strip = document.createElement("pre");
    strip.id = "brutalist-strip";
    strip.className = "brutalist-strip";
    strip.setAttribute("aria-hidden", "true");
    document.body.appendChild(strip);
  }
  const ring = [];
  function pushLine(tag, val) {
    ring.push(`${tag}=${val}`);
    while (ring.length > 6) ring.shift();
    strip.textContent = ring.join(" ");
  }
  window.addEventListener("master:visual", (ev) => {
    const d = ev.detail || {};
    pushLine("mode", (d.mode || "idle").toString().slice(0, 12));
    if (d.entropy != null) pushLine("H", Number(d.entropy).toFixed(2));
    if (d.confidence != null) pushLine("C", Number(d.confidence).toFixed(2));
  });
  const primer = document.getElementById("primer");
  if (primer) {
    const flashPrimer = () => {
      document.body.dataset.primerFlash = "1";
      setTimeout(() => delete document.body.dataset.primerFlash, 180);
    };
    primer.addEventListener("click", flashPrimer, { passive: true });
    primer.addEventListener("pointerup", flashPrimer, { passive: true });
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
