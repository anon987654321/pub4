const F_FACE_SEM = window.MASTER_FACE || {};
const VERTICAL_HINT = (document.documentElement.dataset.appHint || window.MASTER_RUNTIME?.app_hint || 'default').toString().toLowerCase();
const VERTICAL_BIAS = window.MASTER_RUNTIME?.vertical_timbre?.[VERTICAL_HINT]
  || window.MASTER_RUNTIME?.vertical_timbre?.default
  || {};
const State = F_FACE_SEM.State || window.State;
const mouthPool = F_FACE_SEM.mouthPool || window.mouthPool;
const eyePool = F_FACE_SEM.eyePool || window.eyePool;
const renderer = F_FACE_SEM.renderer || window.renderer;
const cv = F_FACE_SEM.cv || document.getElementById('face');
const faceHome = F_FACE_SEM.faceHome || window.faceHome;
const faceScatter = F_FACE_SEM.faceScatter || window.faceScatter;
const faceSeeds = F_FACE_SEM.faceSeeds || window.faceSeeds;
const FACE_N_2D = F_FACE_SEM.FACE_N_2D || window.FACE_N_2D;
const markFaceReady = F_FACE_SEM.markFaceReady || window.markFaceReady;
const resize = F_FACE_SEM.resize || window.resize;
const frame = F_FACE_SEM.frame || window.frame;
const _dbgEl = F_FACE_SEM.dbgEl || document.getElementById('_dbg');
const rootBody = document.body;
const MASTER_FACE_BLEND = window.MASTER_FACE_BLEND;
const FACE3D_ACTIVE = !!window.Face3DPreview;
function mouthCells() { return mouthPool && mouthPool["cells"]; }
function eyeCells() { return eyePool && eyePool["cells"]; }

function applyVerticalTimbre() {
  if (!VERTICAL_BIAS || !window.ParticleKernel) return;
  const K = window.ParticleKernel;
  if (mouthPool) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      if (VERTICAL_BIAS.arousal != null) mouthCells()[b + K.FIELD.arousal] = Math.min(1, (mouthCells()[b + K.FIELD.arousal] || 0.4) + VERTICAL_BIAS.arousal * 0.08);
      if (VERTICAL_BIAS.pressure != null) mouthCells()[b + K.FIELD.pressure] = Math.min(1, (mouthCells()[b + K.FIELD.pressure] || 0) + VERTICAL_BIAS.pressure * 0.06);
      if (VERTICAL_BIAS.valence != null) mouthCells()[b + K.FIELD.valence] = (mouthCells()[b + K.FIELD.valence] || 0) + VERTICAL_BIAS.valence * 0.05;
    }
  }
  if (VERTICAL_BIAS.scanline != null && F_FACE_SEM.faceMat?.uniforms?.uScanline) {
    F_FACE_SEM.faceMat.uniforms.uScanline.value = Math.min(0.5, VERTICAL_BIAS.scanline);
  }
}
applyVerticalTimbre();

function crossPoolInfluence() {
  const K = window.ParticleKernel;
  if (!K || !mouthPool || !eyePool) return;
  const density = (window.MASTER_FACE_EXPRESSION?.blendSignals?.() ? 1.2 : 1) +
    Math.min(1.5, (State.moodArcSamples?.length || 0) * 0.08);
  if (density < 1.15) return;
  let mouthArousal = 0, eyeAttn = 0, mn = 0, en = 0;
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const b = i * K.FIELDS_PER_CELL;
    mouthArousal += mouthCells()[b + K.FIELD.arousal];
    mn++;
  }
  for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
    const b = i * K.FIELDS_PER_CELL;
    eyeAttn += eyeCells()[b + K.FIELD.attention];
    en++;
  }
  if (!mn || !en) return;
  const share = 0.04 * density;
  const targetA = mouthArousal / mn;
  const targetE = eyeAttn / en;
  for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
    const b = i * K.FIELDS_PER_CELL;
    eyeCells()[b + K.FIELD.arousal] = Math.min(1, (eyeCells()[b + K.FIELD.arousal] || 0) * (1 - share) + targetA * share);
  }
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const b = i * K.FIELDS_PER_CELL;
    mouthCells()[b + K.FIELD.attention] = Math.min(1, (mouthCells()[b + K.FIELD.attention] || 0) * (1 - share) + targetE * share);
  }
}
setInterval(crossPoolInfluence, 480);
// Semantic reaction — now primarily driven by server Expression payloads
// (from lib/voice/expression.rb) with lightweight event-specific overrides.
// This structure makes the remaining 50+ ideas from runtime_ui_direction.md
// (pre-speech anticipation, style bleed, mood arc, vertical timbre, etc.)
// implementable with small deltas on the Ruby side instead of JS sprawl.
function boostEyePool(delta, field = 'attention') {
  const K = window.ParticleKernel;
  if (!eyePool || !K) return;
  const key = K.FIELD[field] ?? K.FIELD.attention;
  for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
    const b = i * K.FIELDS_PER_CELL;
    eyeCells()[b + key] = Math.min(1, (eyeCells()[b + key] || 0.5) + delta);
  }
}

function payloadConfidence(d) {
  const raw = d.raw || d.payload || {};
  const v = raw.confidence ?? d.confidence;
  return typeof v === 'number' ? v : null;
}

window.addEventListener('master:pressure', (ev) => {
  const d = ev.detail || {};
  const pct = Number(d.pct ?? d.value ?? 0);
  if (!Number.isFinite(pct)) return;
  if (typeof d.entropy === 'number') State.entropy = d.entropy;
  if (typeof d.turbulence === 'number') State.turbulence = d.turbulence;
  if (typeof d.gravity === 'number') State.gravity = d.gravity;
  State.breath = Math.max(0.55, 1 - pct / 120);
  const K = window.ParticleKernel;
  if (!mouthPool || !K) return;
  const push = Math.min(0.85, pct / 100);
  const turb = typeof d.turbulence === 'number' ? Math.min(0.35, d.turbulence) : 0;
  const grav = typeof d.gravity === 'number' ? Math.min(0.4, d.gravity) : 0;
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const b = i * K.FIELDS_PER_CELL;
    mouthCells()[b + K.FIELD.pressure] = Math.min(1, push + turb);
    if (grav > 0) mouthCells()[b + K.FIELD.valence] = Math.max(-0.2, (mouthCells()[b + K.FIELD.valence] || 0) - grav * 0.12);
  }
});

window.addEventListener('master:palette', (ev) => {
  const accent = ev.detail?.accent;
  if (accent) document.documentElement.style.setProperty('--master-accent', accent);
});

function dropMouthConfidence(drop) {
  const K = window.ParticleKernel;
  if (!mouthPool || !K) return;
  const n = Math.min(6, mouthPool.count);
  let dropped = 0;
  for (let i = 0; i < mouthPool.count && dropped < n; i++) {
    if (!mouthPool.alive[i]) continue;
    const b = i * K.FIELDS_PER_CELL;
    mouthCells()[b + K.FIELD.confidence] = Math.max(0.15, (mouthCells()[b + K.FIELD.confidence] || 0.8) - drop);
    dropped++;
  }
}

function pushMoodArcSample(detail) {
  window.MASTER_FACE_EXPRESSION?.pushMoodArcSample?.(State, detail);
}
window.MASTER_FACE_EXPRESSION?.restoreMood?.(State);

window.addEventListener('master:visual', (ev) => {
  const d = ev.detail || {};
  State.entropy = d.entropy ?? State.entropy ?? 0.2;
  State.confidence = d.confidence ?? State.confidence ?? 1.0;
  pushMoodArcSample(d);
  const name = String(d.name || d.mode || '');
  if (/input:focus|input:focus-visible/.test(name)) boostEyePool(0.07);
  if (/input:paste/.test(name)) boostEyePool(0.04, 'attention');
  if (/user:interrupt/.test(name)) {
    State.shake = Math.max(State.shake || 0, 0.35);
    State.pulse = Math.max(State.pulse || 0, 0.2);
  }
  if ((d.confidence ?? State.confidence) > 0.85) State.calmStareUntil = performance.now() + 900;
  if ((d.confidence ?? State.confidence) < 0.3) State.nervousUntil = performance.now() + 2500;
  if (/error|failure|veto|rollback|events:disconnected/.test(name)) {
    State.fracture = Math.max(State.fracture || 0, 0.55);
    State.shake = Math.max(State.shake || 0, 0.45);
    State.mood = 'veto';
    State.chromaVeto = 0.28;
    State.mode = State.mode === 'speaking' ? State.mode : 'error';
    dropMouthConfidence(0.35);
    if (F_FACE_SEM.faceMat?.uniforms?.uChroma) F_FACE_SEM.faceMat.uniforms.uChroma.value = 0.28;
    rootBody.dataset.errorInstrument = '1';
    setTimeout(() => { delete rootBody.dataset.errorInstrument; }, 2200);
  }
  if (/phantom:detected|phantom:retry|flinch/.test(name) || d.flinch) {
    State.shake = Math.max(State.shake || 0, 0.65);
    State.surpriseY = Math.max(State.surpriseY || 0, 0.42);
    State.pulse = Math.max(State.pulse || 0, 0.38);
  }
  if (/complete|success|done|pass/.test(name)) {
    State.bloom = Math.max(State.bloom || 0, 0.65);
    State.mood = /pass/.test(name) ? 'pass' : State.mood;
    if (/pass/.test(name)) window._chatPassHairline?.();
  }
  const prevMood = State.mood;
  if (d.mood && d.mood !== prevMood) {
    State.mood = d.mood;
    window.MASTER_FACE?.updateMoodHistory?.(d.mood);
    window.MASTER_FACE?.spawnEmotionalGhost?.(d.mood);
    window.MASTER_FACE_EXPRESSION?.persistMood?.(State);
  }
  if (/chat:first/.test(name) && mouthPool && window.ParticleKernel) {
    const K = window.ParticleKernel;
    for (let i = 0; i < 5; i++) K.spawn(mouthPool, 0, 0.55, { kind: 4, zone: 1, valence: 0.7, confidence: 0.85, decay: 0.004, label: d.provider || 'seed' });
  }
  if (/photo:preview/.test(name)) boostEyePool(0.12);
  if (/photo:ready/.test(name) && mouthPool && window.ParticleKernel) {
    const K = window.ParticleKernel;
    K.spawn(mouthPool, 0, 0.5, { kind: 4, zone: 1, valence: 0.6, attention: 0.8, decay: 0.006 });
  }
  if (/council:deliberation|council:start/.test(name)) {
    State.pulse = Math.max(State.pulse || 0, 0.48);
    State.mode = State.mode === 'speaking' ? State.mode : 'thinking';
  }
  if (/llm:request|pipeline:start|thinking/.test(name) && State.mode !== 'speaking') {
    State.mode = 'thinking';
    State.pulse = Math.max(State.pulse || 0, 0.32);
  }
  const K = window.ParticleKernel;
  if (/infer:resolved|infer:confidence|route:resolved|llm:routed/.test(name) && mouthPool && K) {
    const bump = 0.12 + (d.confidence ?? payloadConfidence(d) ?? 0.7) * 0.18;
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      mouthCells()[b + K.FIELD.arousal] = Math.min(1, (mouthCells()[b + K.FIELD.arousal] || 0.3) + bump);
      mouthCells()[b + K.FIELD.pressure] = Math.min(1, (mouthCells()[b + K.FIELD.pressure] || 0) + bump * 0.45);
    }
    State.pulse = Math.max(State.pulse || 0, 0.28);
  }
  if (/infer:rejected/.test(name)) {
    State.tremor = Math.max(State.tremor || 0, 0.25);
    dropMouthConfidence(0.12);
  }
  if (/escalat|fallback|retry/.test(name)) {
    State.tremor = Math.max(State.tremor || 0, 0.4);
    State.mood = 'tense';
  }
  if (/memory|retriev|context/.test(name)) {
    State.ripplePhase = State.ripplePhase < 0 ? 0 : State.ripplePhase;
  }
  if (mouthPool && K) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      if (/speaking|tts/.test(name)) mouthCells()[b + K.FIELD.arousal] = Math.min(1, (mouthCells()[b + K.FIELD.arousal] || 0.3) + 0.2);
      if (d.expression?.arousal != null) mouthCells()[b + K.FIELD.arousal] = d.expression.arousal;
    }
  }
  if (eyePool && K && /council:deliberation|council:start|error|veto/.test(name)) {
    for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      eyeCells()[b + K.FIELD.confidence] = Math.max(0.25, (eyeCells()[b + K.FIELD.confidence] || 0.9) - 0.18);
    }
  }
  if (!mouthPool || !eyePool) return;

  const ex = d.expression || {};

  // Genuine readout: a rendered emotion patch (server Expression.emotion_for,
  // built from council risk/reversibility and the evidence verdict) drives the
  // face directly. This is real state — not the event-name heuristics.
  const emo = d.emotion || ex.emotion;
  if (emo) window.Face3DPreview?.engine?.setEmotion?.(emo);

  if ((d.entropy || 0) > 0.6 || d.mode === 'veto' || /veto|error|failure/.test(d.name || '')) {
    for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      eyeCells()[b + window.ParticleKernel.FIELD.confidence] = Math.max(0.2, (eyeCells()[b + window.ParticleKernel.FIELD.confidence] || 0.9) - (ex.eye_confidence_drop || 0.3));
    }
  }

  if (/tts:style|style:active/i.test(d.name || '')) {
    const s = d.name || '';
    const hi = /dramatic|intense|energetic|storyteller/i.test(s);
    const lo = /whisper|ethereal|robotic|intimate/i.test(s);

    if (mouthPool) for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      mouthCells()[b + window.ParticleKernel.FIELD.arousal] = ex.arousal ?? (hi ? 1.0 : lo ? 0.3 : 0.7);
      if (hi || ex.breath_boost) State.breath = Math.min(1.6, (State.breath || 1.0) + (ex.breath_boost || 0.25));

      const pitch = parseFloat(d.pitch || (d.raw?.pitch)) || 0;
      if (Math.abs(pitch) > 20) eyePool?.alive && (eyeCells()[b + window.ParticleKernel.FIELD.confidence] = 0.6);
    }

    if (hi) State.creativeBleed = (State.creativeBleed || 0) + 0.9;
  }

  if (/council:deliberation|council:start/i.test(d.name || '')) {
    const cDrop  = ex.eye_confidence_drop || 0.25;
    if (eyePool) for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i])
      eyeCells()[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.confidence] = Math.max(0.2, (eyeCells()[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.confidence]||0.9) - cDrop);
  }

  if (/input:long|cmd:long/i.test(d.name || '')) {
    State.jitter = Math.max(State.jitter || 0.2, 0.55);
  }

  if (ex && (ex.arousal != null || ex.valence != null || ex.attention != null)) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      if (ex.arousal != null) mouthCells()[b + window.ParticleKernel.FIELD.arousal] = smoothExpressionValue('arousal', ex.arousal);
      if (ex.valence != null) mouthCells()[b + window.ParticleKernel.FIELD.valence] = smoothExpressionValue('valence', ex.valence);
    }
  }
});

function smoothExpressionValue(key, target) {
  State.expressionTarget[key] = target;
  const current = State.expressionCurrent[key] ?? target;
  const next = current + (target - current) * (State.reducedMotion ? 0.35 : 0.18);
  State.expressionCurrent[key] = next;
  return next;
}

setInterval(() => {
  if (State.creativeBleed > 0.01) State.creativeBleed *= 0.82;
}, 420);

window.addEventListener('tts:anticipate', (ev) => {
  const ex = (ev.detail?.expression) || {};
  if (!mouthPool || !eyePool) return;
  boostEyePool(0.15);
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const b = i * window.ParticleKernel.FIELDS_PER_CELL;
    mouthCells()[b + window.ParticleKernel.FIELD.arousal] = Math.min(1.0, (mouthCells()[b + window.ParticleKernel.FIELD.arousal] || 0.6) + (ex.arousal || 0.25));
  }
  State.pulse = Math.max(State.pulse || 0, 0.35);
});

window.addEventListener('tts:style:active', (ev) => {
  const d = ev.detail || {};
  const ex = d.expression || {};
  State.currentSpeechStyle = d.style || State.currentSpeechStyle;
  if (ex.emotion) window.Face3DPreview?.engine?.setEmotion?.(ex.emotion);
  if (d.blendshapes && window.Face3DPreview?.engine?.setBlend) {
    window.Face3DPreview.engine.setBlend(d.blendshapes);
  }
  if (mouthPool && window.ParticleKernel) {
    const K = window.ParticleKernel;
    const hi = /dramatic|intense|energetic|storyteller/i.test(String(d.style || ''));
    const lo = /whisper|ethereal|robotic|intimate/i.test(String(d.style || ''));
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      mouthCells()[b + K.FIELD.arousal] = ex.arousal ?? (hi ? 1.0 : lo ? 0.3 : 0.7);
      if (ex.pressure != null) mouthCells()[b + K.FIELD.pressure] = ex.pressure;
    }
    if (hi || ex.breath_boost) State.breath = Math.min(1.6, (State.breath || 1.0) + (ex.breath_boost || 0.25));
  }
});

window.addEventListener('tts:playback:start', (ev) => {
  const d = ev.detail || {};
  State.mode = 'speaking';
  State.pulse = Math.max(State.pulse || 0, 0.28);
  State.currentSpeechStyle = d.style || State.currentSpeechStyle || 'calm';
  const K = window.ParticleKernel;
  const effort = window.MASTER_FACE_TTS?.effortSpawnCount?.(State.currentSpeechStyle) ?? 1;
  window.MASTER_FACE_TTS?.syncStyleIndicator?.(State.currentSpeechStyle);
  if (mouthPool && K && effort > 1) {
    for (let n = 0; n < effort; n++) {
      K.spawn(mouthPool, (Math.random() - 0.5) * 0.2, 0.48, {
        kind: 4, zone: 1, arousal: 0.75, pressure: 0.42, confidence: 0.55, decay: 0.005
      });
    }
  }
});

window.addEventListener('tts:playback:end', (ev) => {
  const d = ev.detail || {};
  const decay = Number.isFinite(Number(d.decay_rate)) ? Number(d.decay_rate) : 0.82;
  const K = window.ParticleKernel;
  if (mouthPool && K) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      mouthCells()[b + K.FIELD.arousal] = Math.max(0.12, (mouthCells()[b + K.FIELD.arousal] || 0.5) * decay);
      mouthCells()[b + K.FIELD.pressure] = Math.max(0.08, (mouthCells()[b + K.FIELD.pressure] || 0) * decay);
    }
  }
  State.pulse = Math.max(0, (State.pulse || 0) * decay);
  if (State.mode === 'speaking') State.mode = 'idle';
  State.currentSpeechStyle = null;
  // clearViseme() lives in face.runtime.js's own closure, not exposed to this
  // module — referencing it threw ReferenceError on every tts:playback:end
  // (optional chaining only guards a null/undefined value, not an undeclared
  // identifier), so the mouth shape never relaxed to neutral between speech
  // segments. Reset State directly, mirroring face.runtime.js's clearViseme().
  State.viseme = 'neutral';
  State.visemeAmp = 0;
});

window.addEventListener('tts:viseme', (ev) => {
  const d = ev.detail || {};
  State.viseme = d.shape || State.viseme || 'neutral';
  State.visemeAmp = Number.isFinite(Number(d.amp)) ? Number(d.amp) : State.visemeAmp;
});

resize();

if (renderer) {
  if (_dbgEl) {
    const _dbgTimer = setInterval(() => {
      if (!_dbgEl.isConnected) { clearInterval(_dbgTimer); return; }
      _dbgEl.textContent = `webgl ok · f:${F_FACE_SEM.dbgFrames ?? 0} m:${Number(F_FACE_SEM.morphCurrent ?? 0).toFixed(2)}`;
    }, 500);
    setTimeout(() => { clearInterval(_dbgTimer); _dbgEl.remove(); }, 30000);
  }
  if (window._primerFired && !F_FACE_SEM.primerFired) { window._primerFired = true; F_FACE_SEM.startEverything?.(); }
} else {
  (function start2D() {
    const cv2 = document.createElement('canvas');
    Object.assign(cv2.style, { position:'fixed', inset:'0', width:'100vw', height:'100dvh', display:'block', zIndex:'0' });
    document.body.insertBefore(cv2, cv);
    cv.style.display = 'none';

    const ctx2 = cv2.getContext('2d');
    if (!ctx2) { console.error('2d ctx failed'); return; }

    const N2 = FACE_N_2D;
    const pts = new Float32Array(N2 * 7);
    for (let i = 0; i < N2; i++) {
      pts[i*7]   = faceHome[i*3];   pts[i*7+1] = faceHome[i*3+1];   pts[i*7+2] = faceHome[i*3+2];
      pts[i*7+3] = faceScatter[i*3]; pts[i*7+4] = faceScatter[i*3+1]; pts[i*7+5] = faceScatter[i*3+2];
      pts[i*7+6] = faceSeeds[i];
    }

    let cw2 = 0, ch2 = 0;
    function resize2() {
      cw2 = window.innerWidth; ch2 = window.innerHeight;
      cv2.width = cw2; cv2.height = ch2;
    }
    resize2();
    window.addEventListener('resize', resize2, { passive: true });

    if (window._primerFired && !F_FACE_SEM.primerFired) { window._primerFired = true; F_FACE_SEM.startEverything?.(); }

    let lastT2 = 0;
    function frame2(t) {
      if (t - lastT2 < 33) { requestAnimationFrame(frame2); return; }
      lastT2 = t;
      const sec = t * 0.001;
      const mTgt = window._primerFired ? 1.0 : 0.0;
      const mNext = (F_FACE_SEM.morphCurrent ?? 0) + (mTgt - (F_FACE_SEM.morphCurrent ?? 0)) * 0.06;
      F_FACE_SEM.setMorphCurrent?.(mNext);
      const m = F_FACE_SEM.morphCurrent ?? 0;

      const cosY = Math.cos(State.mouseX * 0.7 + Math.sin(sec * 0.2) * 0.05);
      const sinY = Math.sin(State.mouseX * 0.7 + Math.sin(sec * 0.2) * 0.05);
      const cosX = Math.cos(State.mouseY * 0.4 + Math.sin(sec * 0.27) * 0.03);
      const sinX = Math.sin(State.mouseY * 0.4 + Math.sin(sec * 0.27) * 0.03);
      const f2 = Math.min(cw2, ch2) * 0.5 / Math.tan(38 * Math.PI / 360);
      const camZ = 4.6;

      ctx2.fillStyle = '#000';
      ctx2.fillRect(0, 0, cw2, ch2);
      ctx2.fillStyle = '#fff';
      ctx2.globalAlpha = State.highContrast ? 1.0 : (State.contrastMore ? 0.9 : 0.72);

      const noiseAmp = m > 0.98 ? 0 : (1 - m) * 0.28;
      for (let i = 0; i < N2; i++) {
        const b = i * 7;
        const noise = noiseAmp > 0 ? noiseAmp * Math.sin(sec * 0.4 + pts[b+6]) : 0;
        const wx = pts[b+3] + (pts[b]   - pts[b+3]) * m + noise;
        const wy = pts[b+4] + (pts[b+1] - pts[b+4]) * m + noise * 0.5;
        const wz = pts[b+5] + (pts[b+2] - pts[b+5]) * m;
        const rx  = wx * cosY + wz * sinY;
        const rz0 = -wx * sinY + wz * cosY;
        const ry  = wy * cosX - rz0 * sinX;
        const rz  = wy * sinX + rz0 * cosX;
        const dz  = camZ - rz;
        if (dz <= 0.1) continue;
        const px = rx / dz * f2 + cw2 * 0.5;
        const py = -ry / dz * f2 + ch2 * 0.5;
        const sz = Math.max(2, 2.4 * f2 / (dz * 80));
        const _dz2 = Math.max(0, Math.min(1, (pts[b+2] * 0.78 + 0.5)));
        const _r2 = (0.60 + _dz2 * 0.40) * 255 | 0;
        const _g2 = (0.64 + _dz2 * 0.30) * 255 | 0;
        const _b2 = (0.88 - _dz2 * 0.08) * 255 | 0;
        const K2 = window.ParticleKernel;
        const pxI = (px - sz * 0.5) | 0;
        const pyI = (py - sz * 0.5) | 0;
        const lum = (_r2 + _g2 + _b2) / (255 * 3);
        if (K2?.ditherThreshold(pxI, pyI, lum)) {
          ctx2.fillStyle = `rgb(${_r2},${_g2},${_b2})`;
          ctx2.fillRect(pxI, pyI, Math.ceil(sz), Math.ceil(sz));
        }
      }
      ctx2.globalAlpha = 1.0;

      F_FACE_SEM.incrementDbgFrames?.();
      markFaceReady();
      requestAnimationFrame(frame2);
    }
    requestAnimationFrame(frame2);
  })();
}
