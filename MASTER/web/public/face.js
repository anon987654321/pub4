"use strict";
import * as THREE from '/three.module.js';

const cv = document.getElementById('face');
const primer = document.getElementById('primer');
const zshBar = document.getElementById('zsh');
const zshIn  = document.getElementById('zin');
const rootBody = document.body;

const TINT = {
  idle:    new THREE.Color(0.62, 0.86, 1.00),
  claude:  new THREE.Color(0.86, 0.74, 0.96),
  deepseek:new THREE.Color(0.42, 0.78, 1.00),
  gemini:  new THREE.Color(0.50, 0.92, 0.74),
  gpt:     new THREE.Color(0.92, 0.86, 0.46),
  tense:   new THREE.Color(1.00, 0.50, 0.40),
  curious: new THREE.Color(0.50, 0.82, 0.96),
  focused: new THREE.Color(0.36, 0.66, 0.92),
  weary:   new THREE.Color(0.62, 0.62, 0.72),
  pass:    new THREE.Color(0.50, 0.92, 0.62),
  veto:    new THREE.Color(0.96, 0.32, 0.28),
  unclear: new THREE.Color(0.84, 0.78, 0.40)
};

const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;

const State = {
  mode: 'idle', mood: 'idle', model: '', modelName: '',
  lastTouch: performance.now(), confidence: 1.0,
  tiltX: 0, tiltY: 0, mouseX: 0, mouseY: 0,
  viseme: 'neutral', visemeAmp: 0,
  flash: 0, shake: 0, pulse: 0, sttActive: false,
  hidden: document.hidden, reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches,
  coarsePointer: matchMedia('(pointer: coarse)').matches
};

function updateRuntimeProfile() {
  State.hidden = document.hidden;
  rootBody.dataset.runtimeVisible = State.hidden ? 'false' : 'true';
  rootBody.dataset.runtimeProfile = (State.hidden || State.reducedMotion || State.coarsePointer) ? 'battery' : 'full';
}

updateRuntimeProfile();
matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', event => {
  State.reducedMotion = event.matches;
  updateRuntimeProfile();
});
matchMedia('(pointer: coarse)').addEventListener('change', event => {
  State.coarsePointer = event.matches;
  updateRuntimeProfile();
});
document.addEventListener('visibilitychange', updateRuntimeProfile, { passive: true });

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ canvas: cv, antialias: false, alpha: false });
  renderer.setClearColor(0x000000, 1);
} catch (_) {}
if (!renderer) {
  Object.assign(primer.style, { color: '#fff', font: '12px monospace', display: 'flex', alignItems: 'center', justifyContent: 'center' });
  primer.textContent = 'webgl unavailable';
}
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);
camera.position.set(0, 0, 4.6);

let W = 0, H = 0, DPR = 1;
function resize() {
  if (!renderer) return;
  W = window.innerWidth; H = window.innerHeight;
  DPR = Math.min(window.devicePixelRatio || 1, State.coarsePointer ? 1.25 : 2);

  // Low internal render resolution + CSS upscale (topologies.yml + visual_clusters spec).
  // The Three canvas will render at modest internal size; browser + pixelated CSS does the integer scale.
  const limits = window.MASTER_VISUAL_LIMITS || {};
  const isReduced = State.reducedMotion || (limits.reducedMotionParticles && limits.reducedMotionParticles < 100);
  let internalW = W;
  let internalH = H;
  if (isReduced) {
    internalW = Math.min(640, Math.floor(W * 0.6));
    internalH = Math.min(360, Math.floor(H * 0.6));
  } else if (W * H > 1200000) {
    internalW = Math.floor(W * 0.75);
    internalH = Math.floor(H * 0.75);
  }

  renderer.setPixelRatio(1); // we control internal size manually
  renderer.setSize(internalW, internalH, false);
  camera.aspect = internalW / internalH;
  camera.updateProjectionMatrix();

  // Ensure the canvas element itself is styled for crisp upscale (already in CSS)
  const cv = renderer.domElement;
  if (cv) cv.style.imageRendering = "pixelated";
}
window.addEventListener('resize', resize, { passive: true });

function buildHeadGeometry() {
  const base = new THREE.IcosahedronGeometry(1.0, 4);
  const pos = base.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    let x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
    y *= 1.22;
    z *= 0.92;
    const jaw = Math.max(0, -y - 0.2);
    x *= 1 - jaw * 0.45;
    for (const sx of [-1, 1]) {
      const dx = x - 0.32 * sx, dy = y - 0.22, dz = z - 0.78;
      const d2 = dx*dx + dy*dy + dz*dz;
      if (d2 < 0.10) z -= (0.10 - d2) * 1.4;
    }
    const nd2 = x*x + (y + 0.02)*(y + 0.02);
    if (nd2 < 0.06 && z > 0.6) z += (0.06 - nd2) * 1.6;
    const md = Math.hypot(x, (y + 0.38) * 1.4, (z - 0.84) * 1.4);
    if (md < 0.22 && z > 0.5) z -= (0.22 - md) * 0.8;
    if (y > 0.85) y += (y - 0.85) * 0.4;
    pos.setXYZ(i, x, y, z);
  }
  return base;
}

const head = buildHeadGeometry();

function uniqueVertexPositions(geom) {
  const pos = geom.attributes.position;
  const seen = new Map();
  const out = [];
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
    const key = (x.toFixed(4) + ',' + y.toFixed(4) + ',' + z.toFixed(4));
    if (seen.has(key)) continue;
    seen.set(key, true);
    out.push(x, y, z);
  }
  return new Float32Array(out);
}

function edgeMidpointPositions(geom) {
  const pos = geom.attributes.position;
  const idx = geom.index;
  const out = [];
  const seen = new Set();
  function add(a, b) {
    const lo = Math.min(a, b), hi = Math.max(a, b);
    const key = lo + ':' + hi;
    if (seen.has(key)) return;
    seen.add(key);
    const mx = (pos.getX(lo) + pos.getX(hi)) * 0.5;
    const my = (pos.getY(lo) + pos.getY(hi)) * 0.5;
    const mz = (pos.getZ(lo) + pos.getZ(hi)) * 0.5;
    out.push(mx, my, mz);
  }
  for (let i = 0; i < idx.count; i += 3) {
    const a = idx.getX(i), b = idx.getX(i + 1), c = idx.getX(i + 2);
    add(a, b); add(b, c); add(c, a);
  }
  return new Float32Array(out);
}

const vertPositions = uniqueVertexPositions(head);
const edgePositions = edgeMidpointPositions(head);
const VERT_COUNT = vertPositions.length / 3;

const vertHome = vertPositions.slice();
const vertVel  = new Float32Array(VERT_COUNT * 3);

const mouthMask = new Uint8Array(VERT_COUNT);
const eyeMask   = new Uint8Array(VERT_COUNT);
for (let i = 0; i < VERT_COUNT; i++) {
  const x = vertHome[i*3], y = vertHome[i*3+1], z = vertHome[i*3+2];
  const md = Math.hypot(x, (y + 0.38) * 1.4, (z - 0.84) * 1.4);
  if (md < 0.30 && z > 0.5) mouthMask[i] = 1;
  for (const sx of [-1, 1]) {
    const dx = x - 0.32 * sx, dy = y - 0.22, dz = z - 0.78;
    if (dx*dx + dy*dy + dz*dz < 0.06) eyeMask[i] = 1;
  }
}

// Semantic driver pools per data/topologies.yml face cell_rules + data/ops/visual.yml limits.
// Respect MASTER_VISUAL_LIMITS and reducedMotion for battery/coarse profiles.
let mouthPool = null;
let eyePool = null;
if (window.ParticleKernel) {
  const K = window.ParticleKernel;
  const limits = window.MASTER_VISUAL_LIMITS || { maxParticles: 200, reducedMotionParticles: 64 };
  const isReduced = State?.reducedMotion || matchMedia('(prefers-reduced-motion: reduce)').matches;
  const cap = isReduced ? limits.reducedMotionParticles : Math.min(48, limits.maxParticles);
  const mouthCount = Math.max(4, Math.floor(cap * 0.25));
  const eyeCount = Math.max(3, Math.floor(cap * 0.15));
  mouthPool = K.createPool(mouthCount);
  eyePool = K.createPool(eyeCount);
  for (let i = 0; i < Math.floor(mouthCount * 0.6); i++) K.spawn(mouthPool, 0, 0, { kind: 2, zone: 1, confidence: 0.85, arousal: 0.1, attention: 0.6, decay: 0.12 });
  for (let i = 0; i < Math.floor(eyeCount * 0.6); i++) K.spawn(eyePool, 0, 0, { kind: 1, zone: 0, confidence: 0.9, arousal: 0.2, attention: 0.7, decay: 0.03 });
}

function makeSprite() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  grad.addColorStop(0.0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.4, 'rgba(255,255,255,0.6)');
  grad.addColorStop(1.0, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const sprite = makeSprite();

const vertGeom = new THREE.BufferGeometry();
vertGeom.setAttribute('position', new THREE.BufferAttribute(vertPositions, 3));
const vertMat = new THREE.PointsMaterial({
  size: 0.055, map: sprite, transparent: true, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
  color: TINT.idle.clone()
});
const vertPoints = new THREE.Points(vertGeom, vertMat);
scene.add(vertPoints);

const edgeGeom = new THREE.BufferGeometry();
edgeGeom.setAttribute('position', new THREE.BufferAttribute(edgePositions, 3));
const edgeMat = new THREE.PointsMaterial({
  size: 0.025, map: sprite, transparent: true, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
  color: TINT.idle.clone(), opacity: 0.55
});
const edgePoints = new THREE.Points(edgeGeom, edgeMat);
scene.add(edgePoints);

const colorCurrent = TINT.idle.clone();
const colorTarget  = TINT.idle.clone();
function fadeColorTo(c) { colorTarget.copy(c); }

let lastT = performance.now();
const head3 = new THREE.Object3D();
scene.add(head3);
head3.add(vertPoints);
head3.add(edgePoints);

function frame(t) {
  if (!renderer || State.hidden) {
    lastT = t;
    requestAnimationFrame(frame);
    return;
  }

  const dt = Math.min(State.coarsePointer ? 66 : 50, t - lastT); lastT = t;
  const sec = t * 0.001;

  const lerpSpeed = State.reducedMotion ? 0.12 : 0.04 + Math.min(0.08, State.pulse * 0.6);
  colorCurrent.lerp(colorTarget, lerpSpeed);
  vertMat.color.copy(colorCurrent);
  edgeMat.color.copy(colorCurrent).multiplyScalar(0.78);

  const yaw   = State.mouseX * 0.7 + State.tiltX * 0.5 + Math.sin(sec * 0.2) * 0.05;
  const pitch = State.mouseY * 0.4 + State.tiltY * 0.4 + Math.sin(sec * 0.27) * 0.03;
  head3.rotation.y += (yaw   - head3.rotation.y) * 0.06;
  head3.rotation.x += (pitch - head3.rotation.x) * 0.06;

  const breath = State.reducedMotion ? 1 : 1 + Math.sin(sec * 1.1) * (0.012 + (1 - State.confidence) * 0.008 + (State.entropy || 0) * 0.005) + State.pulse * 0.08;
  head3.scale.setScalar(breath);
  State.pulse *= 0.92;

  if (State.shake > 0.01 && !State.reducedMotion) {
    head3.position.x = (Math.random() - 0.5) * State.shake * 0.18;
    head3.position.y = (Math.random() - 0.5) * State.shake * 0.18;
    State.shake *= 0.86;
  } else {
    head3.position.set(0, 0, 0);
  }

  const vPos = vertGeom.attributes.position.array;
  const visAmp = State.visemeAmp;
  const visOpen = (State.viseme === 'A' || State.viseme === 'O' || State.viseme === 'U') ? 1.0
                : (State.viseme === 'I' || State.viseme === 'E') ? 0.45
                : (State.viseme === 'M') ? 0.05 : 0.0;

  // Kernel cells now drive expression (data/topologies.yml face.cell_rules + visual_clusters migration).
  // mouthPool: kind=speech (fast decay); eyePool: kind=focus (slow decay). Values feed displacement.
  let mouthDrive = visAmp;
  let eyeJitter = 0.02;
  if (mouthPool) {
    window.ParticleKernel.step(mouthPool, 0.016);
    let sum = 0, n = 0;
    for (let i = 0; i < mouthPool.count; i++) {
      if (mouthPool.alive[i]) { sum += mouthPool.cells[i * window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.arousal]; n++; }
    }
    if (n > 0) mouthDrive = Math.max(visAmp, sum / n);
    window.ParticleKernel.compact(mouthPool);
  }
  if (eyePool) {
    window.ParticleKernel.step(eyePool, 0.016);
    let sum = 0, n = 0;
    for (let i = 0; i < eyePool.count; i++) {
      if (eyePool.alive[i]) { sum += eyePool.cells[i * window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.attention]; n++; }
    }
    if (n > 0) eyeJitter = 0.01 + (sum / n) * 0.04;
    if (State.confidence > 0.85) eyeJitter *= 0.92;
    eyeJitter += (State.entropy || 0) * 0.03;
    window.ParticleKernel.compact(eyePool);
  }

  for (let i = 0; i < VERT_COUNT; i++) {
    const i3 = i * 3;
    let hx = vertHome[i3], hy = vertHome[i3+1], hz = vertHome[i3+2];
    if (mouthMask[i]) {
      const open = visOpen * mouthDrive;
      hy -= open * 0.05;
      hz += open * 0.04;
    }
    if (eyeMask[i] && !State.reducedMotion && Math.random() < eyeJitter) {
      vertVel[i3]   += (Math.random() - 0.5) * (eyeJitter * 0.2);
      vertVel[i3+1] += (Math.random() - 0.5) * (eyeJitter * 0.2);
    }
    const sx = vertVel[i3]   = vertVel[i3]   * 0.9 + (hx - vPos[i3])   * 0.18;
    const sy = vertVel[i3+1] = vertVel[i3+1] * 0.9 + (hy - vPos[i3+1]) * 0.18;
    const sz = vertVel[i3+2] = vertVel[i3+2] * 0.9 + (hz - vPos[i3+2]) * 0.18;
    vPos[i3]   += sx * 0.5;
    vPos[i3+1] += sy * 0.5;
    vPos[i3+2] += sz * 0.5;
  }
  State.visemeAmp *= 0.85;
  vertGeom.attributes.position.needsUpdate = true;

  vertMat.opacity = 1 - State.flash * 0.4;
  State.flash *= 0.9;

  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}

let pressTimer = null, pressStart = 0;
cv.addEventListener('pointermove', (e) => {
  State.mouseX = (e.clientX / innerWidth  - 0.5) * 1.6;
  State.mouseY = (e.clientY / innerHeight - 0.5) * 0.9;
}, { passive: true });

cv.addEventListener('pointerdown', () => {
  pressStart = performance.now();
  State.lastTouch = pressStart;
  pressTimer = setTimeout(startSTT, 420);
});
cv.addEventListener('pointerup', () => {
  if (pressTimer) { clearTimeout(pressTimer); pressTimer = null; }
  if (State.sttActive) { stopSTT(); return; }
  if (performance.now() - pressStart < 240) ttsSkip();
});
cv.addEventListener('pointercancel', () => {
  if (pressTimer) { clearTimeout(pressTimer); pressTimer = null; }
});

function bindOrientation() {
  window.addEventListener('deviceorientation', (e) => {
    if (e.gamma != null) State.tiltX = e.gamma / 90;
    if (e.beta  != null) State.tiltY = (e.beta - 45) / 90;
  }, { passive: true });
}
async function requestMotionPermission() {
  if (typeof DeviceOrientationEvent !== 'undefined' &&
      typeof DeviceOrientationEvent.requestPermission === 'function') {
    try { if ((await DeviceOrientationEvent.requestPermission()) === 'granted') bindOrientation(); } catch (_) {}
  } else if (window.DeviceOrientationEvent) {
    bindOrientation();
  }
}

let lastShake = 0, lastAccel = [0, 0, 0];
if (window.DeviceMotionEvent) {
  window.addEventListener('devicemotion', (e) => {
    const a = e.accelerationIncludingGravity || e.acceleration;
    if (!a) return;
    const dx = a.x - lastAccel[0], dy = a.y - lastAccel[1], dz = a.z - lastAccel[2];
    const m = Math.hypot(dx, dy, dz);
    lastAccel = [a.x, a.y, a.z];
    const now = performance.now();
    if (m > 24 && now - lastShake > 800) { lastShake = now; ttsSkip(); State.shake = 1.2; }
    // Harden mobile sensor integration: subtle kernel pressure/jitter from device motion (for "shaky hand" expressiveness)
    if (mouthPool && m > 8) {
      for (let i=0; i<mouthPool.count; i++) if (mouthPool.alive[i]) {
        const b = i*window.ParticleKernel.FIELDS_PER_CELL;
        mouthPool.cells[b + window.ParticleKernel.FIELD.pressure] = Math.min(1, (mouthPool.cells[b + window.ParticleKernel.FIELD.pressure]||0) + m*0.01);
        if (m > 18) { mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] = Math.min(1, (mouthPool.cells[b + window.ParticleKernel.FIELD.arousal]||0) + 0.08); mouthPool.cells[b + window.ParticleKernel.FIELD.valence] = Math.max(-1, (mouthPool.cells[b + window.ParticleKernel.FIELD.valence]||0) - 0.04); }
      }
    }
  }, { passive: true });
}

let actx = null;
function initAudio() {
  if (actx) return;
  try {
    actx = new (window.AudioContext || window.webkitAudioContext)();
  } catch (_) {}
}
function beep(freq, dur) {
  if (!actx) return;
  const o = actx.createOscillator(), g = actx.createGain();
  o.type = 'square'; o.frequency.value = freq;
  g.gain.setValueAtTime(0.08, actx.currentTime);
  g.gain.exponentialRampToValueAtTime(0.001, actx.currentTime + dur);
  o.connect(g); g.connect(actx.destination);
  o.start(); o.stop(actx.currentTime + dur);
}

const tts = { queue: [], muted: false, playing: false, voice: null, current: null };

function pickVoice() {
  const list = speechSynthesis.getVoices();
  if (!list.length) return;
  tts.voice = list.find(v => /ms[-_]MY/i.test(v.lang))
           || list.find(v => /en[-_](GB|US)/i.test(v.lang) && /male|osman|daniel|alex/i.test(v.name))
           || list.find(v => /en[-_]/i.test(v.lang))
           || list[0];
}
if ('speechSynthesis' in window) {
  pickVoice();
  speechSynthesis.onvoiceschanged = pickVoice;
}

const VOWEL_VISEME = { a:'A', e:'E', i:'I', o:'O', u:'U' };
function enqueueSpeech(text) {
  if (tts.muted || !('speechSynthesis' in window)) return;
  const clean = text.replace(/```[\s\S]*?```/g, '').replace(/[*_`~]/g, '').trim();
  if (!clean) return;
  tts.queue.push(clean);
  ttsTick();
}
function ttsTick() {
  if (tts.muted || tts.playing) return;
  const text = tts.queue.shift();
  if (!text) return;
  const u = new SpeechSynthesisUtterance(text);
  if (tts.voice) u.voice = tts.voice;
  u.rate = 0.95; u.pitch = 0.92;
  tts.playing = true; tts.current = u; State.mode = 'speaking';
  u.onboundary = (ev) => {
    const c = (text.charAt(ev.charIndex || 0) || '').toLowerCase();
    State.viseme = VOWEL_VISEME[c] || (('mbpfwv'.indexOf(c) >= 0) ? 'M' : 'E');
    State.visemeAmp = 1.0;
    // Push speech energy into the kernel cells (topologies.yml mouth: kind speech).
    if (mouthPool) {
      for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
        const base = i * window.ParticleKernel.FIELDS_PER_CELL;
        mouthPool.cells[base + window.ParticleKernel.FIELD.arousal] = 1.0;
        mouthPool.cells[base + window.ParticleKernel.FIELD.pressure] = 0.8;
        mouthPool.cells[base + window.ParticleKernel.FIELD.valence] = 0.6;
      }
    }
  };
  u.onend = () => {
    tts.playing = false; tts.current = null;
    State.viseme = 'neutral'; State.visemeAmp = 0;
    if (State.mode === 'speaking') State.mode = 'idle';
    // Let kernel cells decay naturally (fast decay on mouth pool).
    ttsTick();
  };
  u.onerror = u.onend;
  try { speechSynthesis.speak(u); } catch (_) { tts.playing = false; }
}
function ttsSkip() {
  try { speechSynthesis.cancel(); } catch (_) {}
  tts.queue.length = 0; tts.playing = false; tts.current = null;
  State.viseme = 'neutral'; State.visemeAmp = 0;
  // Reset driver cells on skip (preserves fast-decay intent from topologies.yml).
  if (mouthPool) for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) mouthPool.cells[i * window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.arousal] = 0.05;
}
function ttsToggleMute() {
  tts.muted = !tts.muted;
  if (tts.muted) ttsSkip();
  beep(tts.muted ? 220 : 880, 0.05);
}

let recognition = null;
if ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  recognition = new SR();
  recognition.continuous = false; recognition.interimResults = true;
  recognition.onresult = (e) => {
    let final = '';
    for (let i = e.resultIndex; i < e.results.length; i++) {
      if (e.results[i].isFinal) final += e.results[i][0].transcript;
    }
    if (final.trim()) { State.sttActive = false; sendMessage(final.trim()); }
  };
  recognition.onend = () => { State.sttActive = false; };
  recognition.onerror = () => { State.sttActive = false; };
}
function startSTT() {
  if (!recognition || State.sttActive) return;
  try { recognition.start(); State.sttActive = true; State.mode = 'listening'; } catch (_) {}
}
function stopSTT() {
  if (!recognition || !State.sttActive) return;
  try { recognition.stop(); } catch (_) {}
}

let evtSrc = null;
async function sendMessage(text) {
  if (evtSrc) { try { evtSrc.close(); } catch (_) {} }
  ttsSkip();

  let finalText = text, preEnhanced = false;
  try {
    const r = await fetch(`/chat/enhance?message=${encodeURIComponent(text)}`);
    const data = await r.json();
    if (data.changed && data.enhanced && data.enhanced !== text) {
      const chosen = await (window._chatConfirmEnhance?.(text, data.enhanced) ?? Promise.resolve(text));
      preEnhanced = chosen === data.enhanced;
      finalText = chosen;
    }
  } catch (_) {}

  State.mode = 'thinking'; State.pulse = 0.4;
  const stateBlob = encodeURIComponent(`${State.mood}|${State.mode}|${((performance.now() - State.lastTouch)/1000)|0}|0`);
  const url = `/chat/message?message=${encodeURIComponent(finalText)}&state=${stateBlob}${preEnhanced ? '&pre_enhanced=1' : ''}`;
  evtSrc = new EventSource(url);
  let pending = '';
  evtSrc.onmessage = (ev) => {
    const raw = ev.data || '';
    if (raw === '[DONE]') {
      if (pending.trim()) enqueueSpeech(pending.trim());
      pending = '';
      State.mode = 'idle';
      if (navigator.vibrate) navigator.vibrate([60]);
      try { evtSrc.close(); } catch (_) {}
      window._chatOnDone?.();
      return;
    }
    if (raw.startsWith('ERROR:')) {
      window._chatOnChunk?.('\n' + raw + '\n');
      State.mode = 'error'; State.flash = 1; State.shake = 0.8;
      fadeColorTo(TINT.veto);
      window._chatOnError?.();
      return;
    }
    const chunk = raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
    window._chatOnChunk?.(chunk);
    pending += chunk;
    State.pulse = Math.min(0.6, State.pulse + 0.05);
    let m;
    while ((m = pending.match(SENT_BREAK))) {
      const cut = m.index + m[0].length;
      const sent = pending.slice(0, cut).trim();
      pending = pending.slice(cut);
      if (sent) enqueueSpeech(sent);
    }
  };
  evtSrc.addEventListener('mood', (ev) => {
    const m = (ev.data || '').trim();
    if (!m) return;
    State.mood = m;
    if (TINT[m]) fadeColorTo(TINT[m]);
  });
  evtSrc.addEventListener('model', (ev) => {
    const m = (ev.data || '').trim();
    if (!m) return;
    State.model = m; State.modelName = m.split('/').pop();
    const key = Object.keys(TINT).find(k => m.toLowerCase().includes(k));
    if (key) fadeColorTo(TINT[key]);
  });
  evtSrc.addEventListener('verdict', (ev) => {
    const v = (ev.data || '').trim();
    if (TINT[v]) fadeColorTo(TINT[v]);
    State.pulse = 0.6;
    State.jitter = (State.confidence < 0.45 ? 0.75 : 0.15);
    if (State.confidence > 0.75) State.pulse = 0.9;
    if (v === 'pass') beep(880, 0.06);
    if (v === 'veto') { beep(220, 0.10); State.shake = 0.6; }
  });
  evtSrc.addEventListener('confidence', (ev) => {
    const c = parseFloat(ev.data); if (isNaN(c)) return;
    State.confidence = c;
  });
  evtSrc.addEventListener('dmesg', (ev) => {
    try { window._chatOnDmesg?.(JSON.parse(ev.data)); } catch (_) {}
  });
  evtSrc.onerror = () => {
    State.flash = 1; State.shake = 0.8; State.mode = 'error';
    try { evtSrc.close(); } catch (_) {}
  };
}

setInterval(() => {
  if (document.hidden) return;
  const idleS = ((performance.now() - State.lastTouch) / 1000) | 0;
  const body = new URLSearchParams({
    mood: State.mood, mode: State.mode, idle: String(idleS),
    palette: '0', confidence: State.confidence.toFixed(2),
    tilt_x: State.tiltX.toFixed(2), tilt_y: State.tiltY.toFixed(2)
  });
  try { fetch('/canvas/state', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body, keepalive: true }); } catch (_) {}
}, 8000);

let wakeLock = null;
async function acquireWakeLock() {
  if (!('wakeLock' in navigator)) return;
  async function req() { try { wakeLock = await navigator.wakeLock.request('screen'); wakeLock.addEventListener('release', () => { wakeLock = null; }); } catch (_) {} }
  await req();
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && !wakeLock) req(); });
}

const POST_LINES = [
  'MASTER (CONSTITUTIONAL)',
  'soul: ok',
  'constitution: ok',
  'pipeline: ok',
  'council: ok',
  'ready'
];
function startEverything() {
  initAudio();
  if (actx && actx.state === 'suspended') actx.resume();
  let li = 0;
  const postEl = Object.assign(document.createElement('pre'), {
    style: 'position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font:12px "Roboto Mono",monospace;color:#fff;text-align:left;white-space:pre;pointer-events:none;z-index:10'
  });
  primer.appendChild(postEl);
  const tick = () => {
    if (li < POST_LINES.length) {
      postEl.textContent += POST_LINES[li] + '\n';
      beep(li === POST_LINES.length - 1 ? 880 : 440 + li * 12, 0.04);
      li++;
      setTimeout(tick, li < POST_LINES.length ? 160 : 320);
    } else {
      primer.classList.add('gone');
      setTimeout(() => primer.remove(), 1000);
      zshBar.classList.add('live');
      requestMotionPermission(); acquireWakeLock();
      setTimeout(() => enqueueSpeech('ready'), 200);
      if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
  };
  setTimeout(tick, 80);
}
primer.addEventListener('pointerdown', startEverything, { once: true });
primer.addEventListener('keydown', event => {
  if (event.key !== 'Enter' && event.key !== ' ') return;
  event.preventDefault();
  startEverything();
}, { once: true });

zshBar.addEventListener('submit', (e) => {
  e.preventDefault();
  const v = zshIn.value.trim();
  if (!v) return;
  window._chatOnUser?.(v);
  zshIn.value = '';
  State.pulse = 0.4;
  sendMessage(v);
});
zshIn.addEventListener('focus', () => { State.lastTouch = performance.now(); });

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') ttsSkip();
  if (e.ctrlKey && e.key === 'm') { e.preventDefault(); ttsToggleMute(); }
});

window.sendMessage = sendMessage;

// Semantic reaction — now primarily driven by server Expression payloads
// (from lib/voice/expression.rb) with lightweight event-specific overrides.
// This structure makes the remaining 50+ ideas from runtime_ui_direction.md
// (pre-speech anticipation, style bleed, mood arc, vertical timbre, etc.)
// implementable with small deltas on the Ruby side instead of JS sprawl.
window.addEventListener('master:visual', (ev) => {
  const d = ev.detail || {};
  State.entropy = d.entropy ?? State.entropy ?? 0.2;
  if (!mouthPool || !eyePool) return;

  const ex = d.expression || {};

  // High-tension / veto / high-entropy baseline (still useful fallback)
  if ((d.entropy || 0) > 0.6 || d.mode === 'veto' || /veto|error|failure|pressure/.test(d.name || '')) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      mouthPool.cells[b + window.ParticleKernel.FIELD.pressure] = Math.min(1, (mouthPool.cells[b + window.ParticleKernel.FIELD.pressure] || 0) + (ex.mouth_pressure || 0.6));
    }
    for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      eyePool.cells[b + window.ParticleKernel.FIELD.confidence] = Math.max(0.2, (eyePool.cells[b + window.ParticleKernel.FIELD.confidence] || 0.9) - (ex.eye_confidence_drop || 0.3));
    }
  }

  // TTS creative style reactions — prefer server Expression data
  if (/tts:style|style:active/i.test(d.name || '')) {
    const s = d.name || '';
    const hi = /dramatic|intense|energetic|storyteller/i.test(s);
    const lo = /whisper|ethereal|robotic|intimate/i.test(s);

    if (mouthPool) for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] = ex.arousal ?? (hi ? 1.0 : lo ? 0.3 : 0.7);
      mouthPool.cells[b + window.ParticleKernel.FIELD.pressure] = ex.pressure ?? (hi ? 0.85 : lo ? 0.25 : 0.6);
      if (hi || ex.breath_boost) State.breath = Math.min(1.6, (State.breath || 1.0) + (ex.breath_boost || 0.25));

      // Prosody from server rate/pitch
      const rate = parseFloat(d.rate || (d.raw && d.raw.rate)) || 0;
      const pitch = parseFloat(d.pitch || (d.raw && d.raw.pitch)) || 0;
      mouthPool.cells[b + window.ParticleKernel.FIELD.velocity] = rate * 0.008;

      // Creative style "bleed" into eyes (pending idea from runtime_ui_direction)
      if (hi && Math.abs(pitch) > 15) {
        eyePool && eyePool.alive && (eyePool.cells[b + window.ParticleKernel.FIELD.attention] = Math.min(1.0, (eyePool.cells[b + window.ParticleKernel.FIELD.attention] || 0.6) + 0.18));
      }
      if (Math.abs(pitch) > 20) eyePool && eyePool.alive && (eyePool.cells[b + window.ParticleKernel.FIELD.confidence] = 0.6);
    }

    // Post-style creative bleed decay (small persistent effect on eyes after dramatic styles)
    if (hi) State.creativeBleed = (State.creativeBleed || 0) + 0.9;
  }

  // Council + reversibility — now richer via Expression
  if (/council:deliberation|council:start/i.test(d.name || '')) {
    const pBoost = ex.mouth_pressure || 0.5;
    const cDrop  = ex.eye_confidence_drop || 0.25;
    if (mouthPool) for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i])
      mouthPool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.pressure] = Math.min(1, (mouthPool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.pressure]||0) + pBoost);
    if (eyePool) for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i])
      eyePool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.confidence] = Math.max(0.2, (eyePool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.confidence]||0.9) - cDrop);
  }

  // Long input density signal
  if (/input:long|cmd:long/i.test(d.name || '')) {
    State.jitter = Math.max(State.jitter || 0.2, 0.55);
    const density = ex.pressure || 0.4;
    if (mouthPool) for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i])
      mouthPool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.pressure] = Math.min(1, (mouthPool.cells[i*window.ParticleKernel.FIELDS_PER_CELL + window.ParticleKernel.FIELD.pressure]||0) + density);
  }

  // Apply any broad expression fields that weren't caught above (future-proof for more ideas)
  if (ex && (ex.arousal != null || ex.valence != null || ex.attention != null)) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      if (ex.arousal != null) mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] = ex.arousal;
      if (ex.valence != null) mouthPool.cells[b + window.ParticleKernel.FIELD.valence] = ex.valence;
    }
  }
});

// Creative style bleed decay over time (small persistent "ringing" after dramatic TTS)
setInterval(() => {
  if (State.creativeBleed > 0.01 && eyePool) {
    for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
      const b = i * window.ParticleKernel.FIELDS_PER_CELL;
      eyePool.cells[b + window.ParticleKernel.FIELD.attention] = Math.max(0.3, (eyePool.cells[b + window.ParticleKernel.FIELD.attention] || 0.6) - 0.06);
    }
    State.creativeBleed *= 0.82;
  }
}, 420);

// Pre-speech anticipation (idea from runtime_ui_direction): eyes widen + arousal spike just before voice starts
window.addEventListener('tts:anticipate', (ev) => {
  const ex = (ev.detail && ev.detail.expression) || {};
  if (!mouthPool || !eyePool) return;
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const b = i * window.ParticleKernel.FIELDS_PER_CELL;
    mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] = Math.min(1.0, (mouthPool.cells[b + window.ParticleKernel.FIELD.arousal] || 0.6) + (ex.arousal || 0.25));
  }
  for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
    const b = i * window.ParticleKernel.FIELDS_PER_CELL;
    eyePool.cells[b + window.ParticleKernel.FIELD.attention] = Math.min(1.0, (eyePool.cells[b + window.ParticleKernel.FIELD.attention] || 0.6) + (ex.attention || 0.3));
  }
  State.pulse = Math.max(State.pulse || 0, 0.35);
});

resize();
if (renderer) requestAnimationFrame(frame);

// === ULTRAMINIMAL UI + GESTURES + CAM TRACKING + OSMAN VOICE (MASTER web + all apps sync) ===
// Philosophy: Almost nothing visible. Only the living face + tiny top-right logo.
// Reveal nav/content via swipe/gesture. Sensors, camera, Osman TTS as primary interaction.

(function bootstrapUltraMinimal() {
  const body = document.body;
  if (!body.classList.contains('zen')) body.classList.add('zen');

  // Bottom swipe up → reveal input (Osman-ready)
  let startY = 0;
  document.addEventListener('touchstart', e => { startY = e.touches[0].clientY; }, { passive: true });
  document.addEventListener('touchend', e => {
    if (e.changedTouches[0].clientY - startY < -90) {
      const zsh = document.getElementById('zsh');
      if (zsh) zsh.classList.add('revealed');
      // Bonus: subtle Osman anticipation pulse
      if (window.ParticleKernel && window.mouthPool) State.pulse = 0.7;
    }
  }, { passive: true });

  // Right edge swipe → reveal minimal actions
  document.addEventListener('touchstart', e => {
    if (innerWidth - e.touches[0].clientX < 55) body.dataset.edgeSwipe = '1';
  }, { passive: true });
  document.addEventListener('touchend', () => delete body.dataset.edgeSwipe);

  // Long-press face → Osman speaks last response or context
  const cvEl = document.getElementById('face');
  if (cvEl) {
    let t = null;
    cvEl.addEventListener('pointerdown', () => {
      t = setTimeout(() => {
        // Prefer existing chat voice hook, else trigger Osman via bus
        if (window._chatSpeakLast) window._chatSpeakLast();
        else if (window.sendMessage) window.sendMessage('/voice last osman dramatic');
        State.pulse = 1.1;
      }, 480);
    });
    ['pointerup','pointerleave'].forEach(ev => cvEl.addEventListener(ev, () => clearTimeout(t)));
  }

  // Camera face tracking → particle face "makes eye contact"
  async function enableCamTracking() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user', width: 240, height: 180 } });
      const v = document.createElement('video');
      v.srcObject = stream; v.play();
      const c = document.createElement('canvas');
      const ctx = c.getContext('2d', { willReadFrequently: true });
      c.width = 120; c.height = 90;

      setInterval(() => {
        if (!v || v.readyState < 2) return;
        ctx.drawImage(v, 0, 0, c.width, c.height);
        const d = ctx.getImageData(0, 0, c.width, c.height).data;
        let sx = 0, sy = 0, n = 0;
        for (let i = 0; i < d.length; i += 4) {
          if ((d[i] + d[i+1] + d[i+2]) / 3 > 65) {
            const p = i / 4;
            sx += p % c.width;
            sy += (p / c.width) | 0;
            n++;
          }
        }
        if (n > 40) {
          const nx = (sx / n / c.width - 0.5) * 2.1;
          const ny = (sy / n / c.height - 0.5) * 1.3;
          // Fleshed out cam "face tracking" (brightness center as user face proxy, synced from shared minimal-gesture)
          // Drives particle "eye contact" + creative pulse when user faces the UI
          State.mouseX = nx;
          State.mouseY = ny;
          if (Math.abs(nx) < 0.3 && Math.abs(ny) < 0.3) State.pulse = Math.max(State.pulse || 0, 0.5);
        }
      }, 160);
    } catch (_) {}
  }
  if (State.coarsePointer) setTimeout(enableCamTracking, 900);

  // Global hook so Rails apps can call the same minimal + Osman experience
  window.MASTERMinimalUI = {
    enableCam: enableCamTracking,
    revealConsole: () => { const z = document.getElementById('zsh'); if (z) z.classList.add('revealed'); },
    triggerOsman: (text) => { if (window.sendMessage) window.sendMessage(`/voice ${text || 'last'} osman`); }
  };

  // Web Speech "Osman" voice commands (synced with shared minimal-gesture for all apps)
  if ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window) {
    const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
    const rec = new SpeechRec();
    rec.continuous = false;
    rec.lang = 'en-US';
    rec.onresult = (ev) => {
      const t = ev.results[0][0].transcript.toLowerCase();
      if (t.includes('osman')) {
        const cmd = t.replace(/osman|hey|ok/gi,'').trim();
        if (cmd && window.sendMessage) window.sendMessage(`/voice ${cmd} osman`);
      }
    };
    document.addEventListener('keydown', e => { if (e.key === '?' ) { e.preventDefault(); rec.start(); } });
    window.startOsmanVoice = () => rec.start();
  }
})();
