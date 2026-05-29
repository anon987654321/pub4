"use strict";
import * as THREE from '/three.module.js?v=11';

const cv = document.getElementById('face');
const primer = document.getElementById('primer');
const zshBar = document.getElementById('zsh');
const zshIn  = document.getElementById('zin');
const rootBody = document.body;

const TINT = {
  idle:    new THREE.Color(1.00, 1.00, 1.00),
  claude:  new THREE.Color(0.90, 0.82, 1.00),
  deepseek:new THREE.Color(0.76, 0.90, 1.00),
  gemini:  new THREE.Color(0.78, 1.00, 0.88),
  gpt:     new THREE.Color(1.00, 0.94, 0.72),
  tense:   new THREE.Color(1.00, 0.68, 0.60),
  curious: new THREE.Color(0.78, 0.94, 1.00),
  focused: new THREE.Color(0.70, 0.84, 1.00),
  weary:   new THREE.Color(0.82, 0.82, 0.88),
  pass:    new THREE.Color(0.78, 1.00, 0.84),
  veto:    new THREE.Color(1.00, 0.56, 0.52),
  unclear: new THREE.Color(0.96, 0.90, 0.66)
};

function dayNightTint() {
  const h = new Date().getHours() + new Date().getMinutes() / 60;
  if (h >= 5  && h < 7)  return new THREE.Color(1.00, 0.92, 0.78); // dawn — warm gold
  if (h >= 7  && h < 18) return new THREE.Color(1.00, 1.00, 1.00); // day — white
  if (h >= 18 && h < 21) return new THREE.Color(1.00, 0.88, 0.65); // dusk — amber
  return new THREE.Color(0.82, 0.88, 1.00);                         // night — cool blue-white
}

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
// Session-unique face: tiny golden-ratio perturbation seeds a distinct face each load
const SESSION_SEED = Math.random() * Math.PI * 2;
for (let i = 0; i < VERT_COUNT; i++) {
  const theta = SESSION_SEED + i * 2.3999632; // golden angle
  const r = 0.014 * Math.sin(theta * 2.71);
  vertHome[i*3]   += r * Math.cos(theta);
  vertHome[i*3+1] += r * Math.sin(theta) * 0.65;
  vertPositions[i*3]   = vertHome[i*3];
  vertPositions[i*3+1] = vertHome[i*3+1];
}
const CURSOR_R = 0.40; // repulsion radius in head-local units
const CURSOR_F = 0.035; // repulsion force per frame

const COUNCIL_VOICE = {
  Architect: 'ryan', Skeptic: 'steffan', Pragmatist: 'finn',
  Security: 'osman', User: 'pernille', Mentor: 'yasmin'
};

const BOOT_DUO = [
  ['osman',    'Good morning.'],
  ['pernille', 'Hei, og velkommen.'],
  ['osman',    'Constitutional AI — live and ready.'],
  ['pernille', 'Spør oss hva som helst.']
];

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
const vertColors = new Float32Array(VERT_COUNT * 3).fill(1);
const vertColorAttr = new THREE.BufferAttribute(vertColors, 3);
vertGeom.setAttribute('color', vertColorAttr);
const vertMat = new THREE.PointsMaterial({
  size: 0.055, map: sprite, transparent: true, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
  vertexColors: true
});
const vertPoints = new THREE.Points(vertGeom, vertMat);
scene.add(vertPoints);

const EDGE_COUNT = edgePositions.length / 3;
const edgeGeom = new THREE.BufferGeometry();
edgeGeom.setAttribute('position', new THREE.BufferAttribute(edgePositions, 3));
const edgeColors = new Float32Array(EDGE_COUNT * 3).fill(1);
const edgeColorAttr = new THREE.BufferAttribute(edgeColors, 3);
edgeGeom.setAttribute('color', edgeColorAttr);
const edgeMat = new THREE.PointsMaterial({
  size: 0.025, map: sprite, transparent: true, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
  vertexColors: true, opacity: 0.55
});
const edgePoints = new THREE.Points(edgeGeom, edgeMat);
scene.add(edgePoints);

const colorCurrent = TINT.idle.clone();
const colorTarget  = TINT.idle.clone();
function fadeColorTo(c) { colorTarget.copy(c); }
TINT.idle.copy(dayNightTint());
colorCurrent.copy(TINT.idle); colorTarget.copy(TINT.idle);
setInterval(() => { if (!State.mood || State.mood === 'idle') { TINT.idle.copy(dayNightTint()); fadeColorTo(TINT.idle); } }, 60000);

let bloomCtx = null, bloomCv = null;

// Dolly zoom (Hitchcock) — zoom in while dollying back, reversed smoothly
function dollyZoom(intensity) {
  const startFOV = camera.fov, startZ = camera.position.z;
  const targetFOV = Math.max(20, startFOV - intensity * 10);
  const targetZ   = startZ + intensity * 0.55;
  const t0 = performance.now();
  function forward(now) {
    const p = Math.min(1, (now - t0) / 1200);
    const e = p < 0.5 ? 2*p*p : -1+(4-2*p)*p;
    camera.fov = startFOV + (targetFOV - startFOV) * e;
    camera.position.z = startZ + (targetZ - startZ) * e;
    camera.updateProjectionMatrix();
    if (p < 1) { requestAnimationFrame(forward); return; }
    const t1 = performance.now();
    function back(now2) {
      const p2 = Math.min(1, (now2 - t1) / 2000);
      camera.fov = targetFOV + (38 - targetFOV) * p2;
      camera.position.z = targetZ + (4.6 - targetZ) * p2;
      camera.updateProjectionMatrix();
      if (p2 < 1) requestAnimationFrame(back);
    }
    requestAnimationFrame(back);
  }
  requestAnimationFrame(forward);
}

// Photo depth map: project vertex XY to image UV, use luminance as Z offset
function applyPhotoDepthMap(file) {
  const img = new Image();
  const url = URL.createObjectURL(file);
  img.onload = () => {
    const c = document.createElement('canvas');
    c.width = 64; c.height = 64;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0, 64, 64);
    const id = g.getImageData(0, 0, 64, 64);
    URL.revokeObjectURL(url);
    for (let i = 0; i < VERT_COUNT; i++) {
      const i3 = i * 3;
      const u = Math.max(0, Math.min(63, Math.floor((vertHome[i3]   + 1.1) / 2.2 * 63)));
      const v = Math.max(0, Math.min(63, Math.floor((1.0 - (vertHome[i3+1] + 1.0) / 2.4) * 63)));
      const px = (v * 64 + u) * 4;
      const lum = (id.data[px] + id.data[px+1] + id.data[px+2]) / (3 * 255);
      vertHome[i3+2] += (lum - 0.45) * 0.55;
    }
  };
  img.src = url;
}
const _photoEl = document.getElementById('photo');
if (_photoEl) _photoEl.addEventListener('change', () => { if (_photoEl.files[0]) applyPhotoDepthMap(_photoEl.files[0]); });

// Waveform ghost ring
const WAVEFORM_N = 72;
const waveformPos = new Float32Array(WAVEFORM_N * 3);
const waveformGeom = new THREE.BufferGeometry();
waveformGeom.setAttribute('position', new THREE.BufferAttribute(waveformPos, 3));
const waveformMat = new THREE.PointsMaterial({
  size: 0.018, map: sprite, transparent: true, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
  color: new THREE.Color(0.6, 0.85, 1.0), opacity: 0
});
scene.add(new THREE.Points(waveformGeom, waveformMat));

// Crowd orbit (thinking satellites)
const CROWD_N = 28;
const crowdPos = new Float32Array(CROWD_N * 3);
const crowdAngles = Float32Array.from({ length: CROWD_N }, (_, i) => (i / CROWD_N) * Math.PI * 2);
const crowdRadii  = Float32Array.from({ length: CROWD_N }, () => 1.45 + Math.random() * 0.45);
const crowdGeom = new THREE.BufferGeometry();
crowdGeom.setAttribute('position', new THREE.BufferAttribute(crowdPos, 3));
const crowdMat = new THREE.PointsMaterial({
  size: 0.016, map: sprite, transparent: true, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
  color: new THREE.Color(0.75, 0.88, 1.0), opacity: 0
});
scene.add(new THREE.Points(crowdGeom, crowdMat));

// Lens flare (one-shot drift across view)
const lensFlarePos = new Float32Array(3);
const lensFlareGeom = new THREE.BufferGeometry();
lensFlareGeom.setAttribute('position', new THREE.BufferAttribute(lensFlarePos, 3));
const lensFlareMat = new THREE.PointsMaterial({
  size: 0.18, map: sprite, transparent: true, depthWrite: false,
  blending: THREE.AdditiveBlending, sizeAttenuation: true,
  color: new THREE.Color(1.0, 0.97, 0.88), opacity: 0
});
scene.add(new THREE.Points(lensFlareGeom, lensFlareMat));
let lensFlareT = null, lensFlareStart = performance.now() + Math.random() * 20000 + 12000;

let lastT = performance.now();
let nextBlink    = performance.now() + 3000 + Math.random() * 3000;
let saccadeX     = 0, nextSaccade = performance.now() + Math.random() * 6000 + 3000;
let windPhase    = 0;
let nextMicro    = performance.now() + Math.random() * 20000 + 15000;
let nodImpulse   = 0;
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

  if (tts.analyser && tts.analyserBuf) {
    tts.analyser.getByteTimeDomainData(tts.analyserBuf);
    let rmsSum = 0;
    const bufLen = tts.analyserBuf.length;
    for (let bi = 0; bi < bufLen; bi++) { const s = (tts.analyserBuf[bi] - 128) / 128; rmsSum += s * s; }
    const rms = Math.sqrt(rmsSum / bufLen);
    if (rms > 0.01) State.pulse = Math.min(0.9, State.pulse + rms * 1.5);
    State.voiceRMS = rms;
    if (tts.analyserFreqBuf) {
      tts.analyser.getByteFrequencyData(tts.analyserFreqBuf);
      let bass = 0, mids = 0, highs = 0;
      for (let bi = 0; bi < 8; bi++) bass += tts.analyserFreqBuf[bi];
      for (let bi = 8; bi < 32; bi++) mids += tts.analyserFreqBuf[bi];
      for (let bi = 32; bi < 80 && bi < tts.analyserFreqBuf.length; bi++) highs += tts.analyserFreqBuf[bi];
      State.audioBass  = bass  / (8   * 255);
      State.audioMids  = mids  / (24  * 255);
      State.audioHighs = highs / (48  * 255);
    }
  } else {
    State.voiceRMS   = (State.voiceRMS   || 0) * 0.9;
    State.audioBass  = (State.audioBass  || 0) * 0.88;
    State.audioMids  = (State.audioMids  || 0) * 0.88;
    State.audioHighs = (State.audioHighs || 0) * 0.88;
  }

  const lerpSpeed = State.reducedMotion ? 0.12 : 0.04 + Math.min(0.08, State.pulse * 0.6);
  colorCurrent.lerp(colorTarget, lerpSpeed);
  vertMat.color.setRGB(1, 1, 1);
  edgeMat.color.setRGB(1, 1, 1);

  if (!State.reducedMotion && t > nextSaccade && State.mode !== 'thinking') {
    saccadeX = (Math.random() - 0.5) * 0.28;
    nextSaccade = t + Math.random() * 6000 + 3000;
  }
  saccadeX *= 0.93;
  const yaw   = State.mouseX * 0.7 + State.tiltX * 0.5 + Math.sin(sec * 0.2) * 0.05 + saccadeX;
  const pitch = State.mouseY * 0.4 + State.tiltY * 0.4 + Math.sin(sec * 0.27) * 0.03;
  head3.rotation.y += (yaw   - head3.rotation.y) * 0.06;
  head3.rotation.x += (pitch - head3.rotation.x) * 0.06;
  nodImpulse *= 0.87;
  head3.rotation.x += nodImpulse;

  const silenceScale = (State.mode === 'idle' && !tts.playing) ? 0.982 : 1.0;
  const breath = silenceScale * (State.reducedMotion ? 1 : 1 + Math.sin(sec * 1.1) * (0.012 + (1 - State.confidence) * 0.008 + (State.entropy || 0) * 0.005) + State.pulse * 0.08);
  head3.scale.setScalar(breath);
  State.pulse *= 0.92;

  State.lean = (State.lean || 0) * 0.97;
  if (State.shake > 0.01 && !State.reducedMotion) {
    head3.position.x = (Math.random() - 0.5) * State.shake * 0.18;
    head3.position.y = (Math.random() - 0.5) * State.shake * 0.18;
    head3.position.z = State.lean;
    State.shake *= 0.86;
  } else {
    head3.position.set(0, 0, State.lean);
  }

  if (!State.reducedMotion && t > nextBlink) {
    for (let i = 0; i < VERT_COUNT; i++) if (eyeMask[i]) vertVel[i*3+1] -= 0.10;
    nextBlink = t + Math.random() * 4000 + 3000;
  }
  if (!State.reducedMotion && State.mode === 'speaking' && t > nextMicro) {
    for (let i = 0; i < VERT_COUNT; i++) if (vertHome[i*3+1] > 0.55) vertVel[i*3+1] += 0.048;
    nextMicro = t + Math.random() * 20000 + 15000;
  }
  windPhase += dt * 0.00008;

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
    if (!State.reducedMotion && cursorActive) {
      const cdx = vPos[i3] - State.mouseX * 1.5, cdy = vPos[i3+1] + State.mouseY * 1.5;
      const cd2 = cdx * cdx + cdy * cdy;
      if (cd2 < CURSOR_R * CURSOR_R && cd2 > 0.0001) {
        const cd = Math.sqrt(cd2);
        const cf = CURSOR_F * (1 - cd / CURSOR_R);
        vertVel[i3]   += (cdx / cd) * cf;
        vertVel[i3+1] += (cdy / cd) * cf;
      }
    }
    if (!State.reducedMotion) {
      // Gaze gravity: particles drift slightly toward where face looks
      const gx = State.mouseX * 1.5, gy = -State.mouseY * 1.5;
      const gdx = gx - vPos[i3], gdy = gy - vPos[i3+1];
      const gd2 = gdx*gdx + gdy*gdy;
      if (gd2 > 0.04 && gd2 < 4.0) { const gf = 0.000025 / gd2; vertVel[i3] += gdx * gf; vertVel[i3+1] += gdy * gf; }
      // Wind: slow sinusoidal lateral drift
      vertVel[i3] += Math.sin(windPhase + hx * 2.1) * 0.00013;
      // Thinking: slow CCW orbit around y-axis
      if (State.mode === 'thinking') {
        vertVel[i3]   -= vPos[i3+2] * 0.0009;
        vertVel[i3+2] += vPos[i3]   * 0.0009;
      }
      // Audio frequency zones: bass=jaw, mids=cheeks, highs=crown
      if (mouthMask[i] && (State.audioBass || 0) > 0.04)
        vertVel[i3+1] -= State.audioBass * 0.028;
      if (!mouthMask[i] && !eyeMask[i] && Math.abs(hx) > 0.35 && Math.abs(hy) < 0.38 && (State.audioMids || 0) > 0.04)
        vertVel[i3] += (hx > 0 ? 1 : -1) * State.audioMids * 0.020;
      if (hy > 0.52 && (State.audioHighs || 0) > 0.04)
        vertVel[i3+1] += State.audioHighs * 0.024;
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

  // Per-vertex z-depth coloring (rack focus: near=bright, far=dim)
  for (let i = 0; i < VERT_COUNT; i++) {
    const z = vPos[i*3+2];
    const depth = Math.max(0, Math.min(1, (z + 0.8) / 1.8));
    const br = 0.25 + depth * 0.75;
    vertColors[i*3]   = colorCurrent.r * br;
    vertColors[i*3+1] = colorCurrent.g * br;
    vertColors[i*3+2] = colorCurrent.b * br;
  }
  vertColorAttr.needsUpdate = true;
  const ePos = edgeGeom.attributes.position.array;
  for (let i = 0; i < EDGE_COUNT; i++) {
    const z = ePos[i*3+2];
    const depth = Math.max(0, Math.min(1, (z + 0.8) / 1.8));
    const br = 0.12 + depth * 0.45;
    edgeColors[i*3]   = colorCurrent.r * br;
    edgeColors[i*3+1] = colorCurrent.g * br;
    edgeColors[i*3+2] = colorCurrent.b * br;
  }
  edgeColorAttr.needsUpdate = true;

  // Confidence → particle sharpness; whisper dims, shout brightens
  const voiceRMS = State.voiceRMS || 0;
  const whisperScale = tts.playing && voiceRMS < 0.015 ? 0.72 + voiceRMS * 19 : 1.0;
  const shoutBoost   = tts.playing && voiceRMS > 0.35  ? 1.0 + (voiceRMS - 0.35) * 1.2 : 1.0;
  vertMat.size = 0.055 * (0.55 + State.confidence * 0.45 + State.pulse * 0.12) * whisperScale * shoutBoost;
  edgeMat.size = 0.025 * (0.55 + State.confidence * 0.45) * whisperScale;
  edgeMat.opacity = 0.55 * (0.6 + State.confidence * 0.4) * (0.93 + Math.random() * 0.07);

  // Idle dissolve + grain
  const idleS = (t - State.lastTouch) / 1000;
  const dissolveT = idleS > 90 ? Math.min(1, (idleS - 90) / 90) : 0;
  vertMat.opacity = Math.max(0, (1 - State.flash * 0.4 - dissolveT * 0.55)) * (0.93 + Math.random() * 0.07);
  if (dissolveT > 0.25 && !State.reducedMotion && Math.random() < 0.009) {
    const ri = Math.floor(Math.random() * VERT_COUNT) * 3;
    vertVel[ri]   += (Math.random() - 0.5) * 0.055;
    vertVel[ri+1] += (Math.random() - 0.5) * 0.055;
    vertVel[ri+2] += (Math.random() - 0.5) * 0.028;
  }
  State.flash *= 0.9;

  // Waveform ghost ring
  if (tts.analyserBuf && tts.analyser && !State.reducedMotion) {
    waveformMat.opacity = Math.min(0.38, waveformMat.opacity + 0.015);
    for (let i = 0; i < WAVEFORM_N; i++) {
      const angle = (i / WAVEFORM_N) * Math.PI * 2;
      const bi = Math.floor(i / WAVEFORM_N * tts.analyserBuf.length);
      const sample = (tts.analyserBuf[bi] - 128) / 128;
      const r = 1.38 + sample * 0.28;
      waveformPos[i*3]   = Math.cos(angle) * r;
      waveformPos[i*3+1] = Math.sin(angle) * r * 0.78 - 0.08;
      waveformPos[i*3+2] = 0.45 + sample * 0.12;
    }
    waveformGeom.attributes.position.needsUpdate = true;
  } else {
    waveformMat.opacity = Math.max(0, waveformMat.opacity - 0.012);
  }

  // Crowd orbit during thinking
  const thinkingOn = State.mode === 'thinking' && !State.reducedMotion;
  crowdMat.opacity = Math.max(0, Math.min(0.32, crowdMat.opacity + (thinkingOn ? 0.007 : -0.007)));
  if (crowdMat.opacity > 0.005) {
    for (let i = 0; i < CROWD_N; i++) {
      crowdAngles[i] += 0.007 + i * 0.0004;
      const r = crowdRadii[i];
      crowdPos[i*3]   = Math.cos(crowdAngles[i]) * r;
      crowdPos[i*3+1] = Math.sin(crowdAngles[i]) * r * 0.38 - 0.15;
      crowdPos[i*3+2] = Math.sin(crowdAngles[i] * 0.63) * 0.28;
    }
    crowdGeom.attributes.position.needsUpdate = true;
  }

  // Lens flare one-shot
  if (lensFlareStart && t > lensFlareStart) {
    lensFlareT = t; lensFlareStart = null;
    lensFlarePos[1] = (Math.random() - 0.5) * 1.0;
    lensFlarePos[2] = 0.6;
  }
  if (lensFlareT !== null) {
    const lp = (t - lensFlareT) / 2800;
    lensFlarePos[0] = -2.4 + lp * 4.8;
    lensFlareMat.opacity = lp < 0.5 ? lp * 0.55 : (1 - lp) * 0.55;
    lensFlareGeom.attributes.position.needsUpdate = true;
    if (lp >= 1) { lensFlareMat.opacity = 0; lensFlareT = null; }
  }

  renderer.render(scene, camera);

  requestAnimationFrame(frame);
}

let pressTimer = null, pressStart = 0;
let cursorActive = false;
function updateCursor(e) {
  State.mouseX = (e.clientX / innerWidth  - 0.5) * 1.6;
  State.mouseY = (e.clientY / innerHeight - 0.5) * 0.9;
  cursorActive = true;
}
document.addEventListener('pointermove', updateCursor, { passive: true });
document.addEventListener('pointerdown', updateCursor, { passive: true });
document.addEventListener('pointerup',     () => { if (State.coarsePointer) cursorActive = false; }, { passive: true });
document.addEventListener('pointercancel', () => { if (State.coarsePointer) cursorActive = false; }, { passive: true });

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
    if (m > 24 && now - lastShake > 800) {
      lastShake = now; ttsSkip(); State.shake = 1.2;
      // Clap/shake scatter
      for (let i = 0; i < VERT_COUNT; i++) {
        vertVel[i*3]   += (Math.random() - 0.5) * 0.08;
        vertVel[i*3+1] += (Math.random() - 0.5) * 0.08;
        vertVel[i*3+2] += (Math.random() - 0.5) * 0.04;
      }
    }
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

// Primary voice is the server-rendered Osman neural model (soul.yml voice:
// ms-MY-OsmanNeural, GET /chat/tts). Browser speechSynthesis is the fallback
// only — server.unavailable flips once on 403/501/503 so we stop retrying.
const VISEME_STEP_MS = 90;
const LOCAL_RATE = 0.95;
const LOCAL_PITCH = 0.92;
const tts = { queue: [], muted: false, playing: false, voice: null, current: null, audio: null, visemeTimer: null, serverUnavailable: false, analyser: null, analyserBuf: null, analyserFreqBuf: null };

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

// Drive the mouth particle pool to an open/closed pose (topologies.yml mouth: kind speech).
function driveMouth(open) {
  if (!mouthPool) return;
  const K = window.ParticleKernel;
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const base = i * K.FIELDS_PER_CELL;
    mouthPool.cells[base + K.FIELD.arousal] = open ? 1.0 : 0.25;
    mouthPool.cells[base + K.FIELD.pressure] = open ? 0.8 : 0.2;
    mouthPool.cells[base + K.FIELD.valence] = 0.6;
  }
}

function setViseme(ch) {
  const c = (ch || '').toLowerCase();
  State.viseme = VOWEL_VISEME[c] || (('mbpfwv'.indexOf(c) >= 0) ? 'M' : 'E');
  State.visemeAmp = 1.0;
  driveMouth(true);
}

function clearViseme() {
  State.viseme = 'neutral';
  State.visemeAmp = 0;
}

function enqueueSpeech(text) {
  if (tts.muted) return;
  const clean = text.replace(/```[\s\S]*?```/g, '').replace(/[*_`~]/g, '').trim();
  if (!clean) return;
  tts.lastText = clean;
  tts.queue.push(clean);
  nodImpulse += 0.022; // brief forward nod on each sentence
  ttsTick();
}

function ttsTick() {
  if (tts.muted || tts.playing) return;
  const text = tts.queue.shift();
  if (!text) return;
  tts.playing = true;
  State.mode = 'speaking';
  if (tts.serverUnavailable) { speakLocal(text); return; }
  speakServer(text);
}

// Osman neural voice from the server, lip-synced to the actual audio duration.
function speakServer(text) {
  const url = `/chat/tts?voice=osman&text=${encodeURIComponent(text)}`;
  fetch(url)
    .then(r => {
      if (!r.ok) {
        if (r.status === 403 || r.status === 501 || r.status === 503) tts.serverUnavailable = true;
        throw new Error(`tts ${r.status}`);
      }
      return r.blob();
    })
    .then(blob => {
      const src = URL.createObjectURL(blob);
      const audio = new Audio(src);
      tts.audio = audio;
      if (actx && actx.state !== 'closed') {
        try {
          const msrc = actx.createMediaElementSource(audio);
          const analyser = actx.createAnalyser();
          analyser.fftSize = 256;
          msrc.connect(analyser);
          analyser.connect(actx.destination);
          tts.analyser = analyser;
          tts.analyserBuf = new Uint8Array(analyser.fftSize);
          tts.analyserFreqBuf = new Uint8Array(analyser.frequencyBinCount);
        } catch (_) {}
      }
      audio.onplay = () => startVisemeAnim(text);
      audio.onended = audio.onerror = () => {
        stopVisemeAnim();
        tts.analyser = null;
        tts.analyserBuf = null;
        tts.analyserFreqBuf = null;
        URL.revokeObjectURL(src);
        tts.audio = null;
        tts.playing = false;
        if (State.mode === 'speaking') State.mode = 'idle';
        clearViseme();
        ttsTick();
      };
      return audio.play();
    })
    .catch(() => { tts.audio = null; speakLocal(text); });
}

// Sample the cleaned text across the audio length so the mouth moves with real prosody.
function startVisemeAnim(text) {
  stopVisemeAnim();
  let i = 0;
  tts.visemeTimer = setInterval(() => {
    const audio = tts.audio;
    if (!audio || !audio.duration || !isFinite(audio.duration)) { setViseme(text.charAt(i)); i = (i + 3) % text.length; return; }
    const idx = Math.min(text.length - 1, Math.floor((audio.currentTime / audio.duration) * text.length));
    setViseme(text.charAt(idx));
  }, VISEME_STEP_MS);
}

function stopVisemeAnim() {
  if (tts.visemeTimer) { clearInterval(tts.visemeTimer); tts.visemeTimer = null; }
}

// Browser speechSynthesis fallback (generic OS voice, word-boundary visemes).
function speakLocal(text) {
  if (!('speechSynthesis' in window)) { tts.playing = false; if (State.mode === 'speaking') State.mode = 'idle'; ttsTick(); return; }
  const u = new SpeechSynthesisUtterance(text);
  if (tts.voice) u.voice = tts.voice;
  u.rate = LOCAL_RATE; u.pitch = LOCAL_PITCH;
  tts.current = u;
  u.onboundary = (ev) => setViseme(text.charAt(ev.charIndex || 0));
  u.onend = () => {
    tts.playing = false; tts.current = null;
    clearViseme();
    if (State.mode === 'speaking') State.mode = 'idle';
    ttsTick();
  };
  u.onerror = u.onend;
  try { speechSynthesis.speak(u); } catch (_) { tts.playing = false; }
}

function ttsSkip() {
  try { speechSynthesis.cancel(); } catch (_) {}
  if (tts.audio) { try { tts.audio.pause(); } catch (_) {} tts.audio = null; }
  stopVisemeAnim();
  tts.queue.length = 0; tts.playing = false; tts.current = null;
  clearViseme();
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
  if (input.length > 180) State.lean = 0.14;
  const stateBlob = encodeURIComponent(`${State.mood}|${State.mode}|${((performance.now() - State.lastTouch)/1000)|0}|0`);
  const url = `/chat/message?message=${encodeURIComponent(finalText)}&state=${stateBlob}${preEnhanced ? '&pre_enhanced=1' : ''}`;
  evtSrc = new EventSource(url);
  let pending = '';
  evtSrc.onmessage = (ev) => {
    const raw = ev.data || '';
    if (raw === '[DONE]') {
      if (pending.trim()) {
        tts.lastText = pending.trim();
        enqueueSpeech(pending.trim());
      }
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
      const vp = vertGeom.attributes.position.array;
      for (let i = 0; i < VERT_COUNT; i++) {
        const i3 = i * 3;
        const dx = vp[i3], dy = vp[i3+1];
        const d = Math.hypot(dx, dy) || 1;
        vertVel[i3]   = (dx/d) * (0.07 + Math.random() * 0.11);
        vertVel[i3+1] = (dy/d) * (0.07 + Math.random() * 0.11);
        vertVel[i3+2] = (Math.random() - 0.5) * 0.09;
      }
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
    if (v === 'pass') {
      beep(880, 0.06);
      // Consensus snap: all particles rush home simultaneously
      for (let i = 0; i < VERT_COUNT; i++) { vertVel[i*3] *= 0.1; vertVel[i*3+1] *= 0.1; vertVel[i*3+2] *= 0.1; }
    }
    if (v === 'veto') {
      beep(220, 0.10); State.shake = 0.6; dollyZoom(0.8);
      // Shatter on veto
      const vp = vertGeom.attributes.position.array;
      for (let i = 0; i < VERT_COUNT; i++) {
        const i3 = i*3, dx = vp[i3], dy = vp[i3+1], d = Math.hypot(dx, dy) || 1;
        vertVel[i3]   = (dx/d) * (0.05 + Math.random() * 0.09);
        vertVel[i3+1] = (dy/d) * (0.05 + Math.random() * 0.09);
        vertVel[i3+2] = (Math.random() - 0.5) * 0.07;
      }
    }
  });
  evtSrc.addEventListener('council:speech', (ev) => {
    try {
      const { voice, text } = JSON.parse(ev.data || '{}');
      if (voice && text && !tts.playing) playDuo([[voice, text]]);
    } catch (_) {}
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

function playDuo(lines, onDone) {
  if (!lines.length) { onDone?.(); return; }
  const [voice, text] = lines[0];
  const rest = lines.slice(1);
  fetch(`/chat/tts?voice=${encodeURIComponent(voice)}&text=${encodeURIComponent(text)}`)
    .then(r => r.ok ? r.blob() : Promise.reject())
    .then(blob => {
      const src = URL.createObjectURL(blob);
      const audio = new Audio(src);
      if (actx && actx.state !== 'closed') {
        try {
          const msrc = actx.createMediaElementSource(audio);
          const analyser = actx.createAnalyser();
          analyser.fftSize = 256;
          msrc.connect(analyser);
          analyser.connect(actx.destination);
          tts.analyser = analyser;
          tts.analyserBuf = new Uint8Array(analyser.fftSize);
          tts.analyserFreqBuf = new Uint8Array(analyser.frequencyBinCount);
        } catch (_) {}
      }
      startVisemeAnim(text);
      audio.onended = audio.onerror = () => {
        stopVisemeAnim();
        tts.analyser = null; tts.analyserBuf = null; tts.analyserFreqBuf = null;
        URL.revokeObjectURL(src);
        clearViseme();
        playDuo(rest, onDone);
      };
      audio.play().catch(() => { URL.revokeObjectURL(src); playDuo(rest, onDone); });
    })
    .catch(() => playDuo(rest, onDone));
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
  // Scatter particles to flat 2D — spring in frame() coalesces them into 3D face shape
  for (let i = 0; i < VERT_COUNT; i++) {
    vertPositions[i*3]   = (Math.random() - 0.5) * 3.5;
    vertPositions[i*3+1] = (Math.random() - 0.5) * 3.5;
    vertPositions[i*3+2] = 0;
    vertVel[i*3] = vertVel[i*3+1] = vertVel[i*3+2] = 0;
  }
  vertGeom.attributes.position.needsUpdate = true;

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
      setTimeout(() => playDuo(BOOT_DUO), 200);
      if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
  };
  setTimeout(tick, 80);
}
let primerFired = false;
function firePrimer() { if (primerFired) return; primerFired = true; startEverything(); }
primer.addEventListener('pointerdown', firePrimer);
primer.addEventListener('click', firePrimer);
primer.addEventListener('keydown', event => {
  if (event.key !== 'Enter' && event.key !== ' ') return;
  event.preventDefault();
  firePrimer();
});

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
window.MASTERVoice = {
  enqueue: enqueueSpeech,
  skip: ttsSkip,
  toggleMute: ttsToggleMute,
  speak: speakLocal,
  get muted() { return tts.muted; },
  get playing() { return tts.playing; },
  get voice() { return tts.voice; },
  setLastText(text) { tts.lastText = String(text || ""); },
  get lastText() { return tts.lastText || ""; }
};
window._chatSpeakLast = () => {
  const text = tts.lastText || "";
  if (text) enqueueSpeech(text);
};

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
