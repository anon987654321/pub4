const F_FACE_SEM = window.MASTER_FACE || {};
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

// Semantic reaction — now primarily driven by server Expression payloads
// (from lib/voice/expression.rb) with lightweight event-specific overrides.
// This structure makes the remaining 50+ ideas from runtime_ui_direction.md
// (pre-speech anticipation, style bleed, mood arc, vertical timbre, etc.)
// implementable with small deltas on the Ruby side instead of JS sprawl.
window.addEventListener('master:visual', (ev) => {
  const d = ev.detail || {};
  State.entropy = d.entropy ?? State.entropy ?? 0.2;
  State.confidence = d.confidence ?? State.confidence ?? 1.0;
  const name = String(d.name || d.mode || '');
  if (/error|failure|veto|rollback/.test(name)) {
    State.fracture = Math.max(State.fracture || 0, 0.55);
    State.shake = Math.max(State.shake || 0, 0.45);
    State.mood = 'veto';
  }
  if (/complete|success|done|pass/.test(name)) {
    State.bloom = Math.max(State.bloom || 0, 0.65);
    State.mood = /pass/.test(name) ? 'pass' : State.mood;
  }
  if (/council:deliberation|council:start/.test(name)) {
    State.pulse = Math.max(State.pulse || 0, 0.48);
    State.mode = State.mode === 'speaking' ? State.mode : 'thinking';
  }
  if (/llm:request|pipeline:start|thinking/.test(name) && State.mode !== 'speaking') {
    State.mode = 'thinking';
    State.pulse = Math.max(State.pulse || 0, 0.32);
  }
  if (/escalat|fallback|retry/.test(name)) {
    State.tremor = Math.max(State.tremor || 0, 0.4);
    State.mood = 'tense';
  }
  if (/memory|retriev|context/.test(name)) {
    State.ripplePhase = State.ripplePhase < 0 ? 0 : State.ripplePhase;
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
      eyePool.cells[b + window.ParticleKernel.FIELD.confidence] = Math.max(0.2, (eyePool.cells[b + window.ParticleKernel.FIELD.confidence] || 0.9) - (ex.eye_confidence_drop || 0.3));
    }
  }

  if (/tts:style|style:active/i.test(d.name || '')) {
    const s = d.name || '';
    const hi = /dramatic|intense|energetic|storyteller/i.test(s);
    const lo = /whisper|ethereal|robotic|intimate/i.test(s);

    if (mouthPool) for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] = ex.arousal ?? (hi ? 1.0 : lo ? 0.3 : 0.7);
      if (hi || ex.breath_boost) State.breath = Math.min(1.6, (State.breath || 1.0) + (ex.breath_boost || 0.25));

      const pitch = parseFloat(d.pitch || (d.raw && d.raw.pitch)) || 0;
      if (Math.abs(pitch) > 20) eyePool && eyePool.alive && (eyePool.cells[b + window.ParticleKernel.FIELD.confidence] = 0.6);
    }

    if (hi) State.creativeBleed = (State.creativeBleed || 0) + 0.9;
  }

  if (/council:deliberation|council:start/i.test(d.name || '')) {
    const cDrop  = ex.eye_confidence_drop || 0.25;
    if (eyePool) for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i])
      eyePool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.confidence] = Math.max(0.2, (eyePool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.confidence]||0.9) - cDrop);
  }

  if (/input:long|cmd:long/i.test(d.name || '')) {
    State.jitter = Math.max(State.jitter || 0.2, 0.55);
  }

  if (ex && (ex.arousal != null || ex.valence != null || ex.attention != null)) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      if (ex.arousal != null) mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] = smoothExpressionValue('arousal', ex.arousal);
      if (ex.valence != null) mouthPool.cells[b + window.ParticleKernel.FIELD.valence] = smoothExpressionValue('valence', ex.valence);
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
  const ex = (ev.detail && ev.detail.expression) || {};
  if (!mouthPool || !eyePool) return;
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const b = i * window.ParticleKernel.FIELDS_PER_CELL;
    mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] = Math.min(1.0, (mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] || 0.6) + (ex.arousal || 0.25));
  }
  State.pulse = Math.max(State.pulse || 0, 0.35);
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
  requestAnimationFrame(frame);
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
        ctx2.fillStyle = `rgb(${_r2},${_g2},${_b2})`;
        ctx2.fillRect((px - sz * 0.5) | 0, (py - sz * 0.5) | 0, Math.ceil(sz), Math.ceil(sz));
      }
      ctx2.globalAlpha = 1.0;

      F_FACE_SEM.incrementDbgFrames?.();
      markFaceReady();
      requestAnimationFrame(frame2);
    }
    requestAnimationFrame(frame2);
  })();
}
