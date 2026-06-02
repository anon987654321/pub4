"use strict";

// Check WebGL before paying THREE's 1.3MB parse cost
const _wglCv = document.createElement('canvas');
const _hasWebGL = !!(_wglCv.getContext('webgl2') || _wglCv.getContext('webgl') || _wglCv.getContext('experimental-webgl'));

const _dbgEl = document.getElementById('_dbg');
if (_dbgEl) _dbgEl.textContent = _hasWebGL ? 'loading three...' : '2d mode';

// Only import THREE on WebGL-capable devices — saves 10-20s parse on low-end hardware
const THREE = _hasWebGL ? await import('/three.module.js?v=24') : null;

// Minimal Color stub for no-WebGL path
class _Color {
  constructor(r=0,g=0,b=0){this.r=r;this.g=g;this.b=b;}
  clone(){return new _Color(this.r,this.g,this.b);}
  copy(c){this.r=c.r;this.g=c.g;this.b=c.b;return this;}
  lerp(c,t){this.r+=(c.r-this.r)*t;this.g+=(c.g-this.g)*t;this.b+=(c.b-this.b)*t;return this;}
}
const Color = _hasWebGL ? THREE.Color : _Color;

const cv = document.getElementById('face');
const primer = document.getElementById('primer');
const zshBar = document.getElementById('zsh');
const zshIn  = document.getElementById('zin');
const ttsLive = document.getElementById('tts-live');
const uiStatus = document.getElementById('ui-status');
const rootBody = document.body;

const FONT_KEY = 'master:font';
(function initFont() {
  const root = rootBody || document.documentElement;
  const saved = localStorage.getItem(FONT_KEY);
  if (saved === 'mono') root.classList.add('font-mono');
  let t = document.getElementById('font-toggle');
  if (!t) {
    t = document.createElement('span');
    t.id = 'font-toggle';
    t.className = 'font-toggle';
    t.role = 'button';
    t.tabIndex = 0;
    t.setAttribute('aria-label', 'Toggle font');
    t.textContent = 'sys';
    document.body.appendChild(t);
  }
  const update = () => {
    const m = root.classList.contains('font-mono');
    t.textContent = m ? 'mono' : 'sys';
  };
  update();
  const doToggle = () => {
    const m = root.classList.toggle('font-mono');
    localStorage.setItem(FONT_KEY, m ? 'mono' : 'system');
    update();
  };
  t.addEventListener('click', doToggle);
  t.addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      doToggle();
    }
  });
})();

const TINT = {
  // Pure white dithered phosphor pixels — 8-bit monochrome CRT / terminal aesthetic.
  // Shading and expression via Atkinson/Bayer dither patterns, alpha, size, depth, and pulse (no hue tints).
  idle:    new Color(1.00, 1.00, 1.00),
  claude:  new Color(1.00, 1.00, 1.00),
  deepseek:new Color(1.00, 1.00, 1.00),
  gemini:  new Color(1.00, 1.00, 1.00),
  gpt:     new Color(1.00, 1.00, 1.00),
  tense:   new Color(1.00, 1.00, 1.00),
  curious: new Color(1.00, 1.00, 1.00),
  focused: new Color(1.00, 1.00, 1.00),
  weary:   new Color(1.00, 1.00, 1.00),
  pass:    new Color(1.00, 1.00, 1.00),
  veto:    new Color(1.00, 1.00, 1.00),
  unclear: new Color(1.00, 1.00, 1.00)
};

function dayNightTint() {
  // Pure white — time of day no longer affects hue (shading is dither-only in the 8-bit CRT phosphor style).
  return new Color(1.00, 1.00, 1.00);
}

const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;

const State = {
  mode: 'idle', mood: 'idle', model: '', modelName: '',
  lastTouch: performance.now(), confidence: 1.0,
  tiltX: 0, tiltY: 0, mouseX: 0, mouseY: 0,
  viseme: 'neutral', visemeAmp: 0,
  flash: 0, shake: 0, pulse: 0, sttActive: false,
  hidden: document.hidden, reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches,
  coarsePointer: matchMedia('(pointer: coarse)').matches,
  highContrast: new URLSearchParams(window.location.search).get('hc') === '1'
};

rootBody.dataset.highContrast = State.highContrast ? '1' : '';

// Sync State.mode to body[data-mode] and #zsh-status for CSS-driven status visibility.
let _stateMode = 'idle';
Object.defineProperty(State, 'mode', {
  get() { return _stateMode; },
  set(v) {
    _stateMode = v;
    rootBody.dataset.mode = v;
    const s = document.getElementById('zsh-status');
    if (s) s.textContent = (v === 'idle' || v === 'error' || v === 'listening') ? '' : v;
  },
  configurable: true
});

function updateRuntimeProfile() {
  State.hidden = document.hidden;
  rootBody.dataset.runtimeVisible = State.hidden ? 'false' : 'true';
  rootBody.dataset.runtimeProfile = (State.hidden || State.reducedMotion || State.coarsePointer) ? 'battery' : 'full';
  rootBody.dataset.highContrast = State.highContrast ? '1' : '';
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
document.addEventListener('visibilitychange', () => {
  updateRuntimeProfile();
  if (!document.hidden && renderer) requestAnimationFrame(frame);
}, { passive: true });

let faceReadyMarked = false;
function markFaceReady() {
  if (faceReadyMarked) return;
  faceReadyMarked = true;
  rootBody.classList.add('face-ready');
  rootBody.classList.remove('face-loading');
}

let renderer, scene, camera;
if (_hasWebGL && THREE) {
  try {
    renderer = new THREE.WebGLRenderer({ canvas: cv, antialias: false, alpha: false });
    renderer.setClearColor(0x000000, 1);
  } catch (_) {}
  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);
  camera.position.set(0, 0, 4.6);
}
if (_dbgEl) _dbgEl.textContent = renderer ? 'webgl ok' : (_hasWebGL ? 'webgl FAIL' : '2d mode');

let W = 0, H = 0, DPR = 1;
function resize() {
  if (!renderer) return;
  W = window.innerWidth; H = window.innerHeight;
  DPR = Math.min(window.devicePixelRatio || 1, State.coarsePointer ? 1.25 : 2);

  // Low internal render resolution + CSS upscale (topologies.yml + visual_clusters spec).
  // The Three canvas will render at modest internal size; browser + pixelated CSS does the integer scale.
  const internalW = W;
  const internalH = H;

  renderer.setPixelRatio(1); // we control internal size manually
  renderer.setSize(internalW, internalH, false);
  camera.aspect = internalW / internalH;
  camera.updateProjectionMatrix();

  // Ensure the canvas element itself is styled for crisp upscale (already in CSS)
  const cv = renderer.domElement;
  if (cv) cv.style.imageRendering = "pixelated";
}
window.addEventListener('resize', resize, { passive: true });

// Pure-JS icosahedron for the 2D no-WebGL path
function buildHeadPositions2D() {
  const t = (1 + Math.sqrt(5)) / 2;
  const raw = [[-1,t,0],[1,t,0],[-1,-t,0],[1,-t,0],[0,-1,t],[0,1,t],[0,-1,-t],[0,1,-t],[t,0,-1],[t,0,1],[-t,0,-1],[-t,0,1]];
  const verts = raw.map(v => { const l = Math.hypot(v[0],v[1],v[2]); return [v[0]/l,v[1]/l,v[2]/l]; });
  const faces = [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]];
  const cache = {};
  function mid(a, b) {
    const k = Math.min(a,b)+','+Math.max(a,b);
    if (cache[k] !== undefined) return cache[k];
    const v = [(verts[a][0]+verts[b][0])/2,(verts[a][1]+verts[b][1])/2,(verts[a][2]+verts[b][2])/2];
    const l = Math.hypot(v[0],v[1],v[2]);
    verts.push([v[0]/l,v[1]/l,v[2]/l]);
    return (cache[k] = verts.length - 1);
  }
  let cur = faces;
  for (let d = 0; d < 3; d++) {
    const next = [];
    for (const [a,b,c] of cur) { const ab=mid(a,b),bc=mid(b,c),ca=mid(c,a); next.push([a,ab,ca],[b,bc,ab],[c,ca,bc],[ab,bc,ca]); }
    cur = next;
  }
  // Flatten + apply face deformation
  const pos = [];
  for (const [a,b,c] of cur) for (const vi of [a,b,c]) {
    let [x,y,z] = verts[vi];
    y *= 1.22; z *= 0.92;
    const jaw = Math.max(0, -y - 0.2); x *= 1 - jaw * 0.45;
    for (const sx of [-1,1]) { const dx=x-0.32*sx,dy=y-0.22,dz=z-0.78,d2=dx*dx+dy*dy+dz*dz; if(d2<0.10) z-=(0.10-d2)*1.4; }
    const nd2=x*x+(y+0.02)*(y+0.02); if(nd2<0.06&&z>0.6) z+=(0.06-nd2)*1.6;
    const md=Math.hypot(x,(y+0.38)*1.4,(z-0.84)*1.4); if(md<0.22&&z>0.5) z-=(0.22-md)*0.8;
    if(y>0.85) y+=(y-0.85)*0.4;
    pos.push(x,y,z);
  }
  return new Float32Array(pos);
}

// Sample surface points from a flat Float32Array of triangle positions (non-indexed)
function sampleFlatPositions(flatPos, N) {
  const triCount = flatPos.length / 9;
  const areas = new Float32Array(triCount);
  let totalArea = 0;
  for (let t = 0; t < triCount; t++) {
    const b = t * 9;
    const ax=flatPos[b],ay=flatPos[b+1],az=flatPos[b+2];
    const bx=flatPos[b+3]-ax,by=flatPos[b+4]-ay,bz=flatPos[b+5]-az;
    const cx2=flatPos[b+6]-ax,cy2=flatPos[b+7]-ay,cz2=flatPos[b+8]-az;
    const area = 0.5*Math.hypot(by*cz2-bz*cy2, bz*cx2-bx*cz2, bx*cy2-by*cx2);
    areas[t] = area; totalArea += area;
  }
  const cdf = new Float32Array(triCount);
  let cum = 0;
  for (let t = 0; t < triCount; t++) { cum += areas[t]/totalArea; cdf[t] = cum; }
  const home = new Float32Array(N*3), scatter = new Float32Array(N*3), seeds = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const r = Math.random();
    let lo = 0, hi = triCount - 1;
    while (lo < hi) { const m2 = (lo+hi)>>1; if (cdf[m2] < r) lo = m2+1; else hi = m2; }
    const b = lo * 9;
    let r1 = Math.random(), r2 = Math.random();
    if (r1+r2 > 1) { r1=1-r1; r2=1-r2; }
    const r3 = 1-r1-r2;
    home[i*3]   = flatPos[b]*r3 + flatPos[b+3]*r1 + flatPos[b+6]*r2;
    home[i*3+1] = flatPos[b+1]*r3 + flatPos[b+4]*r1 + flatPos[b+7]*r2;
    home[i*3+2] = flatPos[b+2]*r3 + flatPos[b+5]*r1 + flatPos[b+8]*r2;
    scatter[i*3]=home[i*3]+(Math.random()-0.5)*0.18;
    scatter[i*3+1]=home[i*3+1]+(Math.random()-0.5)*0.18;
    scatter[i*3+2]=home[i*3+2]+(Math.random()-0.5)*0.14;
    seeds[i] = Math.random()*6.28318;
  }
  return { home, scatter, seeds };
}

function proceduralFaceTargets() {
  const out = [];
  const push = (x, y, z) => out.push([x, y, z]);
  // Face contour — oval tapering to chin
  for (let i = 0; i < 360; i++) {
    const a = (i / 359) * Math.PI * 2;
    const chinT = Math.max(0, -Math.sin(a));
    const rx = 0.40 - chinT * 0.06;
    push(Math.cos(a) * rx + (Math.random()-0.5)*0.008,
         Math.sin(a) * 0.58 - 0.04 + (Math.random()-0.5)*0.008,
         0.02 - Math.abs(Math.cos(a)) * 0.08);
  }
  // Eyes
  for (const [ex, ey] of [[-0.175, 0.09], [0.175, 0.09]]) {
    for (let i = 0; i < 180; i++) {
      const a = (i / 179) * Math.PI * 2;
      push(ex + Math.cos(a)*0.072 + (Math.random()-0.5)*0.006,
           ey + Math.sin(a)*0.044 + (Math.random()-0.5)*0.006, 0.28);
    }
    for (let i = 0; i < 80; i++) {
      const r = Math.sqrt(Math.random()) * 0.04, a = Math.random() * Math.PI * 2;
      push(ex + Math.cos(a)*r, ey + Math.sin(a)*r*0.7, 0.18);
    }
    for (let i = 0; i < 100; i++) {
      const t = i / 99, a = Math.PI * (0.05 + t * 0.90);
      push(ex + Math.cos(a)*0.088, ey + 0.012 + Math.sin(a)*0.028, 0.24);
    }
    for (let i = 0; i < 80; i++) {
      const t = i / 79, a = Math.PI * (0.08 + t * 0.84);
      push(ex + Math.cos(a)*0.082, ey - Math.sin(a)*0.022, 0.24);
    }
    for (let i = 0; i < 140; i++) {
      const t = i / 139;
      const bx = ex + (t - 0.5) * 0.21;
      const arch = Math.sin(t * Math.PI) * 0.018 + (ex < 0 ? (t-0.5)*0.012 : -(t-0.5)*0.012);
      push(bx + (Math.random()-0.5)*0.008, ey + 0.082 + arch + (Math.random()-0.5)*0.006, 0.20);
    }
  }
  // Nose bridge
  for (let i = 0; i < 120; i++) {
    const t = i / 119;
    push((Math.random()-0.5)*0.028, 0.04 - t*0.22, 0.30 + t*0.15);
  }
  // Nose tip
  for (let i = 0; i < 140; i++) {
    const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random())*0.058;
    push(Math.cos(a)*r, -0.195 + Math.sin(a)*r*0.65, 0.46 + (Math.random()-0.5)*0.02);
  }
  // Nostrils
  for (const sx of [-1, 1]) {
    for (let i = 0; i < 80; i++) {
      const a = Math.random() * Math.PI * 2;
      push(sx*(0.058 + Math.cos(a)*0.032), -0.21 + Math.sin(a)*0.020, 0.38 + Math.random()*0.02);
    }
  }
  // Upper lip — Cupid bow
  for (let i = 0; i < 200; i++) {
    const t = i / 199, a = Math.PI * (0.04 + t * 0.92);
    const bow = Math.sin(t * Math.PI * 2) * 0.014;
    push(Math.cos(a)*0.130, -0.30 + 0.018 + Math.sin(a)*0.026 + bow, 0.30 + (Math.random()-0.5)*0.02);
  }
  // Lower lip
  for (let i = 0; i < 200; i++) {
    const t = i / 199, a = Math.PI * (0.04 + t * 0.92);
    push(Math.cos(a)*0.130, -0.30 - Math.sin(a)*0.040, 0.32 + (Math.random()-0.5)*0.02);
  }
  // Cheeks
  for (const sx of [-1, 1]) {
    for (let i = 0; i < 160; i++) {
      push(sx*(0.22 + Math.random()*0.12), -0.04 + (Math.random()-0.5)*0.20, 0.10 + Math.random()*0.06);
    }
  }
  // Chin
  for (let i = 0; i < 120; i++) {
    const a = Math.PI * (1.08 + (i/119)*0.84);
    push(Math.cos(a)*0.22, -0.45 + Math.sin(a)*0.06, 0.08 + Math.random()*0.04);
  }
  return out;
}
function sampleProceduralFace(N) {
  const targets = proceduralFaceTargets();
  const home = new Float32Array(N * 3), scatter = new Float32Array(N * 3), seeds = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const p = targets[Math.floor((i / N) * targets.length) % targets.length];
    home[i*3] = p[0] + (Math.random() - 0.5) * 0.018;
    home[i*3+1] = p[1] + (Math.random() - 0.5) * 0.018;
    home[i*3+2] = p[2] + (Math.random() - 0.5) * 0.025;
    scatter[i*3] = home[i*3] + (Math.random() - 0.5) * 0.16;
    scatter[i*3+1] = home[i*3+1] + (Math.random() - 0.5) * 0.16;
    scatter[i*3+2] = home[i*3+2] + (Math.random() - 0.5) * 0.10;
    seeds[i] = Math.random() * 6.28318;
  }
  return { home, scatter, seeds };
}

// Load mask image into a 256×256 OffscreenCanvas
async function loadMaskCanvas(url, size = 256) {
  const img = new Image();
  img.crossOrigin = 'anonymous';
  await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
  const cv = new OffscreenCanvas(size, size);
  const ctx = cv.getContext('2d');
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, size, size);
  const scale = Math.min(size / img.width, size / img.height);
  const dw = img.width * scale, dh = img.height * scale;
  ctx.drawImage(img, (size - dw) / 2, (size - dh) / 2, dw, dh);
  return cv;
}

// Sobel edge-weighted sampling: particles concentrate on facial features.
function proceduralFaceDepth(nx, ny) {
  const r2 = (nx*nx)/(0.38*0.38) + (ny*ny)/(0.46*0.46);
  const base = Math.max(0, 1 - r2) * 0.45;
  const nd2 = nx*nx*18 + Math.pow(ny - 0.08, 2)*10;
  const nose = Math.exp(-nd2*5) * 0.42;
  const edL = Math.pow(nx+0.15,2)*14 + Math.pow(ny+0.04,2)*18;
  const edR = Math.pow(nx-0.15,2)*14 + Math.pow(ny+0.04,2)*18;
  const eyes = (Math.exp(-edL*2.2) + Math.exp(-edR*2.2)) * 0.16;
  const bwL = Math.pow(nx+0.15,2)*14 + Math.pow(ny+0.14,2)*26;
  const bwR = Math.pow(nx-0.15,2)*14 + Math.pow(ny+0.14,2)*26;
  const brows = (Math.exp(-bwL*2.2) + Math.exp(-bwR*2.2)) * 0.07;
  const ld = nx*nx*10 + Math.pow(ny-0.23,2)*22;
  const lips = Math.exp(-ld*2.5) * 0.08;
  const ckL = Math.pow(nx+0.25,2)*8 + Math.pow(ny-0.04,2)*14;
  const ckR = Math.pow(nx-0.25,2)*8 + Math.pow(ny-0.04,2)*14;
  const cheeks = (Math.exp(-ckL*2) + Math.exp(-ckR*2)) * 0.05;
  return base + nose - eyes + brows + lips + cheeks - 0.1;
}

function sampleImageDepth(canvas, N) {
  const W = canvas.width, H = canvas.height;
  const { data } = canvas.getContext("2d").getImageData(0, 0, W, H);
  const lum = new Float32Array(W * H);
  for (let i = 0; i < W * H; i++) {
    lum[i] = (data[i*4]*0.299 + data[i*4+1]*0.587 + data[i*4+2]*0.114) / 255;
  }
  const grad = new Float32Array(W * H);
  for (let y = 1; y < H - 1; y++) {
    for (let x = 1; x < W - 1; x++) {
      const idx = y * W + x;
      const gx = -lum[(y-1)*W+(x-1)] - 2*lum[y*W+(x-1)] - lum[(y+1)*W+(x-1)]
                 +lum[(y-1)*W+(x+1)] + 2*lum[y*W+(x+1)] + lum[(y+1)*W+(x+1)];
      const gy = -lum[(y-1)*W+(x-1)] - 2*lum[(y-1)*W+x] - lum[(y-1)*W+(x+1)]
                 +lum[(y+1)*W+(x-1)] + 2*lum[(y+1)*W+x] + lum[(y+1)*W+(x+1)];
      grad[idx] = Math.sqrt(gx*gx + gy*gy);
    }
  }
  const weights = new Float32Array(W * H);
  let total = 0;
  for (let i = 0; i < W * H; i++) {
    const nx = (i % W) / W - 0.5, ny = Math.floor(i / W) / H - 0.5;
    const inEllipse = (nx*nx)/(0.44*0.44) + (ny*ny)/(0.48*0.48) < 1;
    const r = data[i*4], g = data[i*4+1], b = data[i*4+2];
    const bg = r > 210 && g > 200 && b > 190;
    if (!inEllipse || bg) { weights[i] = 0; continue; }
    weights[i] = 0.25 + grad[i] * 5.0;
    total += weights[i];
  }
  const cdf = new Float32Array(W * H);
  let cum = 0;
  for (let i = 0; i < W * H; i++) { cum += weights[i] / total; cdf[i] = cum; }
  const home = new Float32Array(N * 3), scatter = new Float32Array(N * 3), seeds = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const rnd = Math.random();
    let lo = 0, hi = W * H - 1;
    while (lo < hi) { const mid = (lo+hi)>>1; if (cdf[mid] < rnd) lo = mid+1; else hi = mid; }
    const px = (lo % W) + Math.random() - 0.5;
    const py = Math.floor(lo / W) + Math.random() - 0.5;
    const l = lum[lo];
    home[i*3]   = (px / W - 0.5) * 1.18;
    home[i*3+1] = -(py / H - 0.5) * 1.55;
    home[i*3+2] = proceduralFaceDepth(px / W - 0.5, py / H - 0.5);
    scatter[i*3]   = home[i*3] + (Math.random() - 0.5) * 0.16;
    scatter[i*3+1] = home[i*3+1] + (Math.random() - 0.5) * 0.16;
    scatter[i*3+2] = home[i*3+2] + (Math.random() - 0.5) * 0.10;
    seeds[i] = Math.random() * 6.28318;
  }
  return { home, scatter, seeds };
}

const FACE_N = State.coarsePointer ? 10000 : 28000;
const FACE_N_2D = 600;
let faceHome, faceScatter, faceSeeds;
if (_hasWebGL && THREE) {
  try {
    const maskCanvas = await loadMaskCanvas('/face_mask.jpg?v=1');
    ({ home: faceHome, scatter: faceScatter, seeds: faceSeeds } = sampleImageDepth(maskCanvas, FACE_N));
  } catch (_) {
    ({ home: faceHome, scatter: faceScatter, seeds: faceSeeds } = sampleProceduralFace(FACE_N));
  }
} else {
  ({ home: faceHome, scatter: faceScatter, seeds: faceSeeds } = sampleProceduralFace(FACE_N_2D));
}

const VERT_SHADER = `
vec3 mod289v3(vec3 x){return x-floor(x*(1./289.))*289.;}
vec4 mod289v4(vec4 x){return x-floor(x*(1./289.))*289.;}
vec4 permute4(vec4 x){return mod289v4(((x*34.)+1.)*x);}
vec4 taylorInvSqrt4(vec4 r){return 1.79284291400159-0.85373472095314*r;}
float snoise(vec3 v){
  const vec2 C=vec2(1./6.,1./3.);const vec4 D=vec4(0.,.5,1.,2.);
  vec3 i=floor(v+dot(v,C.yyy));vec3 x0=v-i+dot(i,C.xxx);
  vec3 g=step(x0.yzx,x0.xyz);vec3 l=1.-g;
  vec3 i1=min(g.xyz,l.zxy);vec3 i2=max(g.xyz,l.zxy);
  vec3 x1=x0-i1+C.xxx;vec3 x2=x0-i2+C.yyy;vec3 x3=x0-D.yyy;
  i=mod289v3(i);
  vec4 p=permute4(permute4(permute4(i.z+vec4(0.,i1.z,i2.z,1.))+i.y+vec4(0.,i1.y,i2.y,1.))+i.x+vec4(0.,i1.x,i2.x,1.));
  float n_=.142857142857;vec3 ns=n_*D.wyz-D.xzx;
  vec4 j=p-49.*floor(p*ns.z*ns.z);
  vec4 x_=floor(j*ns.z);vec4 y_=floor(j-7.*x_);
  vec4 x=x_*ns.x+ns.yyyy;vec4 y=y_*ns.x+ns.yyyy;vec4 h=1.-abs(x)-abs(y);
  vec4 b0=vec4(x.xy,y.xy);vec4 b1=vec4(x.zw,y.zw);
  vec4 s0=floor(b0)*2.+1.;vec4 s1=floor(b1)*2.+1.;vec4 sh=-step(h,vec4(0.));
  vec4 a0=b0.xzyw+s0.xzyw*sh.xxyy;vec4 a1=b1.xzyw+s1.xzyw*sh.zzww;
  vec3 p0=vec3(a0.xy,h.x);vec3 p1=vec3(a0.zw,h.y);vec3 p2=vec3(a1.xy,h.z);vec3 p3=vec3(a1.zw,h.w);
  vec4 norm=taylorInvSqrt4(vec4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3)));
  p0*=norm.x;p1*=norm.y;p2*=norm.z;p3*=norm.w;
  vec4 m=max(.6-vec4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)),0.);m=m*m;
  return 42.*dot(m*m,vec4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
}
vec3 curlNoise(vec3 p){
  const float e=.07;
  float n1,n2,n3,n4;
  n1=snoise(p+vec3(0,e,0));n2=snoise(p-vec3(0,e,0));
  n3=snoise(p+vec3(0,0,e));n4=snoise(p-vec3(0,0,e));
  float cx=(n1-n2)/(2.*e)-(n3-n4)/(2.*e);
  vec3 q=p+vec3(31.416);
  n1=snoise(q+vec3(0,0,e));n2=snoise(q-vec3(0,0,e));
  n3=snoise(q+vec3(e,0,0));n4=snoise(q-vec3(e,0,0));
  float cy=(n1-n2)/(2.*e)-(n3-n4)/(2.*e);
  vec3 r=p+vec3(17.);
  n1=snoise(r+vec3(e,0,0));n2=snoise(r-vec3(e,0,0));
  n3=snoise(r+vec3(0,e,0));n4=snoise(r-vec3(0,e,0));
  float cz=(n1-n2)/(2.*e)-(n3-n4)/(2.*e);
  return vec3(cx,cy,cz);
}
uniform float uMorph;
uniform float uTime;
uniform float uSize;
uniform vec3 uColor;
uniform float uHc;
uniform float uCurl;
uniform float uJaw;
uniform vec2 uMouse;
uniform float uBass;
attribute vec3 scatter;
attribute float seed;
varying float vAlpha;
varying vec3 vColor;
varying float vFresnel;
varying float vDepth;
void main(){
  float m=smoothstep(0.,1.,uMorph);
  float curlAmp=0.18+uCurl*0.30;
  vec3 noise=curlNoise(position*0.5+uTime*0.1+seed)*(1.-m)*curlAmp;
  float jawRgn=smoothstep(0.0,0.15,-position.y-0.12)*smoothstep(0.0,0.14,0.28-abs(position.x));
  vec3 p=mix(scatter,position,m)+noise+vec3(0.,-uJaw*0.05*jawRgn,0.);
  vec2 diff2d=p.xy-uMouse;
  float dist2d=length(diff2d);
  if(dist2d<0.20&&dist2d>0.001)p.xy+=normalize(diff2d)*(0.20-dist2d)*0.32;
  float radial=length(p.xy);
  p.z+=sin(radial*11.0-uTime*3.8)*uBass*0.05*m;
  vec4 mv=modelViewMatrix*vec4(p,1.);
  float depth=clamp((p.z+0.8)/1.8,0.,1.);
  float sizeJitter=0.80+0.38*fract(sin(seed*17.3)*43758.5);
  gl_PointSize=uSize*(300./-mv.z)*(0.68+depth*0.32)*sizeJitter;
  gl_Position=projectionMatrix*mv;
  float hc=uHc;
  vAlpha=hc>0.5?1.0:mix(0.22,0.3+depth*0.7,m);
  vColor=(hc>0.5?vec3(1.0,1.0,1.0):uColor)*(hc>0.5?1.0:(0.3+depth*0.7));
  vec3 viewDir=normalize(-mv.xyz);
  vec3 flatNorm=normalize(vec3(p.xy*1.8,1.0));
  vec3 vn=normalize(mat3(modelViewMatrix)*flatNorm);
  vFresnel=pow(1.0-abs(dot(viewDir,vn)),2.8);
  vDepth=depth;
}`;

const FRAG_SHADER = `
varying float vAlpha;
varying vec3 vColor;
varying float vFresnel;
varying float vDepth;
uniform float uShake;
uniform float uPulseRing;
void main(){
  vec2 uv=gl_PointCoord-0.5;
  float d=length(uv);
  if(d>0.5)discard;
  float soft=smoothstep(0.5,0.18,d);
  float ring=smoothstep(0.04,0.0,abs(d-0.40))*uPulseRing*0.5;
  vec3 col=vColor+vFresnel*vColor*0.55;
  col.r=min(1.0,col.r+uShake*0.18);
  col.b=max(0.0,col.b-uShake*0.12);
  float alpha=soft*vAlpha+ring;
  gl_FragColor=vec4(col,alpha);
}`;

let faceGeom, faceMat, facePoints;
if (_hasWebGL && THREE) {
  faceGeom = new THREE.BufferGeometry();
  faceGeom.setAttribute('position', new THREE.BufferAttribute(faceHome, 3));
  faceGeom.setAttribute('scatter',  new THREE.BufferAttribute(faceScatter, 3));
  faceGeom.setAttribute('seed',     new THREE.BufferAttribute(faceSeeds, 1));
  faceMat = new THREE.ShaderMaterial({
    vertexShader: VERT_SHADER, fragmentShader: FRAG_SHADER,
    uniforms: {
      uMorph:{value:0}, uTime:{value:0}, uSize:{value:0.08},
      uColor:{value:new Color(1,1,1)}, uHc:{value:0},
      uCurl:{value:0}, uJaw:{value:0}, uMouse:{value:{x:0,y:0}},
      uBass:{value:0}, uShake:{value:0},
      uPulseRing:{value:0}
    },
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending
  });
  facePoints = new THREE.Points(faceGeom, faceMat);
}

let morphCurrent = 0.88, morphTarget = 0.88;
let mouthPool = null, eyePool = null;

const COUNCIL_VOICE = {
  Architect: 'ryan', Skeptic: 'steffan', Pragmatist: 'finn',
  Security: 'osman', User: 'ryan', Mentor: 'yasmin'
};

const BOOT_DUO = [
  ['ryan', 'Welcome. I am Maestro.'],
  ['ryan', 'Ask me anything.']
];


const colorCurrent = TINT.idle.clone();
const colorTarget  = TINT.idle.clone();
function fadeColorTo(c) { colorTarget.copy(c); }
TINT.idle.copy(dayNightTint());
colorCurrent.copy(TINT.idle); colorTarget.copy(TINT.idle);
setInterval(() => { if (!State.mood || State.mood === 'idle') { TINT.idle.copy(dayNightTint()); fadeColorTo(TINT.idle); } }, 60000);

let bloomCtx = null, bloomCv = null;

function dollyZoom(intensity) {
  if (!camera) return;
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

const _photoEl = document.getElementById('photo');
if (_photoEl) _photoEl.addEventListener('change', () => {
  if (_photoEl.files[0]) { morphCurrent = 0; morphTarget = 1.0; }
});


let lastT = performance.now();
let saccadeX = 0, nextSaccade = performance.now() + Math.random() * 6000 + 3000;
let nextBlink = performance.now() + Math.random() * 5000 + 3000;
function doBlink() {
  if (!faceMat) return;
  const orig = faceMat.uniforms.uSize.value;
  let phase = 0;
  const blinkTimer = setInterval(() => {
    phase += 0.18;
    if (phase < 1) {
      faceMat.uniforms.uSize.value = orig * (1 - 0.55 * Math.sin(phase * Math.PI));
    } else {
      faceMat.uniforms.uSize.value = orig;
      clearInterval(blinkTimer);
    }
  }, 14);
}
let nodImpulse = 0;
let glowPoints;
let head3;
if (_hasWebGL && THREE && scene && facePoints) {
  head3 = new THREE.Object3D();
  scene.add(head3);
  head3.add(facePoints);
  const glowMat = new THREE.ShaderMaterial({
    vertexShader: VERT_SHADER, fragmentShader: FRAG_SHADER,
    uniforms: {
      uMorph:{value:0}, uTime:{value:0}, uSize:{value:0.18},
      uColor:{value:new Color(1,1,1)}, uHc:{value:0},
      uCurl:{value:0}, uJaw:{value:0}, uMouse:{value:{x:0,y:0}},
      uBass:{value:0}, uShake:{value:0},
      uPulseRing:{value:0}
    },
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending
  });
  glowPoints = new THREE.Points(faceGeom, glowMat);
  glowPoints.renderOrder = -1;
  head3.add(glowPoints);
}

let _dbgFrames = 0;
function frame(t) {
  _dbgFrames++;
  if (!renderer) {
    lastT = t;
    requestAnimationFrame(frame);
    return;
  }
  if (State.hidden) {
    lastT = t;
    return;
  }

  const dt = Math.min(State.coarsePointer ? 66 : 50, t - lastT); lastT = t;
  const sec = t * 0.001;

  if (tts.playing && tts.analyser && tts.analyserBuf) {
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
  if ((_dbgFrames & 7) === 0) {
    const r = (colorCurrent.r * 255)|0, g = (colorCurrent.g * 255)|0, b = (colorCurrent.b * 255)|0;
    const cr = (255-r)|0, cg = (255-g)|0, cb = (255-b)|0;
    rootBody.style.setProperty('--mood-r', r);
    rootBody.style.setProperty('--mood-g', g);
    rootBody.style.setProperty('--mood-b', b);
    rootBody.style.setProperty('--mood-accent', `rgb(${r},${g},${b})`);
    rootBody.style.setProperty('--mood-complement', `rgb(${cr},${cg},${cb})`);
    rootBody.style.setProperty('--mood-shadow', `rgba(${r},${g},${b},0.12)`);
    rootBody.style.setProperty('--mood-mid', `rgba(${r},${g},${b},0.45)`);
    rootBody.style.setProperty('--mood-hi', `rgba(${r},${g},${b},0.88)`);
    const moodSat = State.mood === 'weary' ? 0.15 : (State.mood === 'tense' ? 1.0 : 0.7);
    rootBody.style.setProperty('--mood-sat', moodSat.toFixed(2));
    if (State.mode === 'error' && !rootBody.dataset.moodCold) {
      rootBody.dataset.moodCold = '1';
      TINT.idle.set(0.35, 0.55, 0.9);
      fadeColorTo(TINT.idle);
      setTimeout(() => { delete rootBody.dataset.moodCold; TINT.idle.set(1,1,1); fadeColorTo(TINT.idle); }, 1800);
    }
  }

  if (head3) {
    if (!State.reducedMotion && t > nextSaccade && State.mode !== 'thinking') {
      saccadeX = (Math.random() - 0.5) * 0.28;
      nextSaccade = t + Math.random() * 6000 + 3000;
    }
    if (!State.reducedMotion && t > nextBlink) {
      doBlink();
      nextBlink = t + Math.random() * 5000 + 2500;
    }
    saccadeX *= 0.93;
    const yaw   = State.mouseX * 0.7 + State.tiltX * 0.5 + Math.sin(sec * 0.2) * 0.05 + saccadeX;
    const pitch = State.mouseY * 0.4 + State.tiltY * 0.4 + Math.sin(sec * 0.27) * 0.03;
    if (camera) {
      camera.position.x += (Math.sin(sec * 0.11) * 0.018 - camera.position.x) * 0.004;
      camera.position.y += (Math.cos(sec * 0.09) * 0.012 - camera.position.y) * 0.004;
    }
    head3.rotation.y += (yaw   - head3.rotation.y) * 0.06;
    head3.rotation.x += (pitch - head3.rotation.x) * 0.06;
    nodImpulse *= 0.87;
    head3.rotation.x += nodImpulse;
    const silenceScale = (State.mode === 'idle' && !tts.playing) ? 0.982 : 1.0;
    const breath = silenceScale * (State.reducedMotion ? 1 : 1 + Math.sin(sec * 1.1) * (0.012 + (1 - State.confidence) * 0.008 + (State.entropy || 0) * 0.005) + State.pulse * 0.08);
    head3.scale.setScalar(breath);
    State.lean = (State.lean || 0) * 0.97;
    if (State.shake > 0.01 && !State.reducedMotion) {
      head3.position.x = (Math.random() - 0.5) * State.shake * 0.18;
      head3.position.y = (Math.random() - 0.5) * State.shake * 0.18;
      head3.position.z = State.lean;
      State.shake *= 0.86;
    } else {
      head3.position.set(0, 0, State.lean);
    }
  }
  State.pulse *= 0.92;

  if (faceMat) {
    const idleS = (t - State.lastTouch) / 1000;
    const confTight = 0.78 + State.confidence * 0.22;
    morphTarget = !primerFired ? 0.88 : (idleS > 90 ? Math.max(0, 1 - (idleS - 90) / 60) : confTight);
    const springK = 0.038, springDamp = 0.72;
    if (!faceMat._morphVel) faceMat._morphVel = 0;
    faceMat._morphVel += (morphTarget - morphCurrent) * springK;
    faceMat._morphVel *= springDamp;
    morphCurrent += faceMat._morphVel;
    faceMat.uniforms.uMorph.value = morphCurrent;
    faceMat.uniforms.uTime.value = t * 0.001;
    faceMat.uniforms.uColor.value.copy(colorCurrent);
    const voiceRMS = State.voiceRMS || 0;
    const whisperScale = tts.playing && voiceRMS < 0.015 ? 0.72 + voiceRMS * 19 : 1.0;
    const shoutBoost   = tts.playing && voiceRMS > 0.35  ? 1.0 + (voiceRMS - 0.35) * 1.2 : 1.0;
    faceMat.uniforms.uSize.value = 0.08 * (0.55 + State.confidence * 0.45 + State.pulse * 0.12) * whisperScale * shoutBoost;
    faceMat.uniforms.uHc.value = State.highContrast ? 1.0 : 0.0;
    const curlTarget = State.mode === 'thinking' ? 1.0 : 0.0;
    faceMat.uniforms.uCurl.value += (curlTarget - faceMat.uniforms.uCurl.value) * 0.025;
    faceMat.uniforms.uJaw.value = voiceRMS * 2.5;
    faceMat.uniforms.uMouse.value = { x: State.mouseX * 1.4, y: -State.mouseY * 1.2 };
    faceMat.uniforms.uBass.value = (State.audioBass || 0) * 0.9 + faceMat.uniforms.uBass.value * 0.1;
    const shakeTarget = State.shake || 0;
    faceMat.uniforms.uShake.value += (shakeTarget - faceMat.uniforms.uShake.value) * 0.18;
    const pulseRingTarget = State.pulse > 0.55 ? (State.pulse - 0.55) * 2.2 : 0;
    faceMat.uniforms.uPulseRing.value += (pulseRingTarget - faceMat.uniforms.uPulseRing.value) * 0.12;
    if (glowPoints) {
      const gm = glowPoints.material;
      Object.assign(gm.uniforms, {
        uMorph: faceMat.uniforms.uMorph, uTime: faceMat.uniforms.uTime,
        uColor: faceMat.uniforms.uColor, uHc: faceMat.uniforms.uHc,
        uCurl: faceMat.uniforms.uCurl, uJaw: faceMat.uniforms.uJaw,
        uMouse: faceMat.uniforms.uMouse, uBass: faceMat.uniforms.uBass,
        uShake: faceMat.uniforms.uShake, uPulseRing: faceMat.uniforms.uPulseRing
      });
      gm.uniforms.uSize.value = faceMat.uniforms.uSize.value * 2.1;
          }
  }

  State.flash *= 0.9;
  renderer.render(scene, camera);
  markFaceReady();

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
      morphCurrent = Math.max(0, morphCurrent - 0.6); morphTarget = 1.0;
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


const VISEME_STEP_MS = 90;
const tts = { queue: [], prefetch: new Map(), muted: false, playing: false, loading: false, cancelToken: 0, current: null, audio: null, visemeTimer: null, serverUnavailable: false, analyser: null, analyserBuf: null, analyserFreqBuf: null };
const TTS_DB_NAME = 'master-tts-v1';
const TTS_STORE = 'blobs';
const TTS_DEFAULT_VOICE = 'ryan';
let ttsDBPromise = null;

function setTTSLoading(loading) {
  tts.loading = !!loading;
  rootBody.dataset.ttsLoading = tts.loading ? 'true' : 'false';
  if (uiStatus && State.mode !== 'speaking') uiStatus.textContent = tts.loading ? 'tts' : 'idle';
}

function announceTTS(text) {
  if (!ttsLive) return;
  ttsLive.textContent = text.toString().slice(0, 500);
}

function ttsURL(text, voice) {
  const qs = new URLSearchParams({ text });
  if (voice) qs.set('voice', voice);
  return `/chat/tts?${qs.toString()}`;
}

async function ttsCacheKey(text, voice) {
  if (!window.crypto || !crypto.subtle || !window.TextEncoder) return null;
  const material = `${voice || TTS_DEFAULT_VOICE}|auto|${text}`;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(material));
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('');
}

function openTTSDB() {
  if (!window.indexedDB) return Promise.resolve(null);
  if (ttsDBPromise) return ttsDBPromise;
  ttsDBPromise = new Promise((resolve) => {
    const req = indexedDB.open(TTS_DB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(TTS_STORE)) db.createObjectStore(TTS_STORE);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => resolve(null);
    req.onblocked = () => resolve(null);
  });
  return ttsDBPromise;
}

async function readCachedTTS(key) {
  const db = await openTTSDB();
  if (!db || !key) return null;
  return new Promise((resolve) => {
    const tx = db.transaction(TTS_STORE, 'readonly');
    const req = tx.objectStore(TTS_STORE).get(key);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => resolve(null);
  });
}

async function writeCachedTTS(key, blob) {
  const db = await openTTSDB();
  if (!db || !key || !blob) return;
  try {
    const tx = db.transaction(TTS_STORE, 'readwrite');
    tx.objectStore(TTS_STORE).put(blob, key);
  } catch (_) {}
}

async function loadTTSBlob(text, voice) {
  const key = await ttsCacheKey(text, voice).catch(() => null);
  const cached = key ? await readCachedTTS(key) : null;
  if (cached) return cached;
  const res = await fetch(ttsURL(text, voice));
  if (!res.ok) throw new Error(res.status);
  const blob = await res.blob();
  writeCachedTTS(key, blob);
  return blob;
}

const VOWEL_VISEME = { a:'A', e:'E', i:'I', o:'O', u:'U' };

function setViseme(ch) {
  const c = (ch || '').toLowerCase();
  State.viseme = VOWEL_VISEME[c] || (('mbpfwv'.indexOf(c) >= 0) ? 'M' : 'E');
  State.visemeAmp = 1.0;
}

function clearViseme() {
  State.viseme = 'neutral';
  State.visemeAmp = 0;
}

function fetchTTS(text) {
  if (tts.serverUnavailable || tts.prefetch.has(text)) return;
  const p = loadTTSBlob(text).catch(() => null);
  tts.prefetch.set(text, p);
}

function enqueueSpeech(text) {
  if (tts.muted) return;
  const clean = text.replace(/```[\s\S]*?```/g, '').replace(/[*_`~]/g, '').trim();
  if (!clean) return;
  announceTTS(clean);
  tts.lastText = clean;
  tts.queue.push(clean);
  nodImpulse += 0.022;
  if (tts.playing && !tts.serverUnavailable) fetchTTS(clean);
  ttsTick();
}

function ttsTick() {
  if (tts.muted || tts.playing) return;
  const text = tts.queue.shift();
  if (!text) return;
  tts.playing = true;
  const token = ++tts.cancelToken;
  setTTSLoading(true);
  State.mode = 'speaking';
  if (tts.serverUnavailable) { tts.playing = false; setTTSLoading(false); ttsTick(); return; }
  const pending = tts.prefetch.get(text) || loadTTSBlob(text);
  tts.prefetch.delete(text);
  if (tts.queue[0]) fetchTTS(tts.queue[0]);
  pending
    .then(blob => {
      if (token !== tts.cancelToken) return null;
      if (!blob) throw new Error('empty');
      const src = URL.createObjectURL(blob);
      const audio = new Audio(src);
      tts.audio = audio;
      if (actx && actx.state !== 'closed') {
        if (actx.state === 'suspended') actx.resume();
        try {
          const msrc = actx.createMediaElementSource(audio);
          const boost = actx.createGain();
          boost.gain.value = 1.8;
          const analyser = actx.createAnalyser();
          analyser.fftSize = 256;
          msrc.connect(boost);
          boost.connect(analyser);
          analyser.connect(actx.destination);
          tts.analyser = analyser;
          tts.analyserBuf = new Uint8Array(analyser.fftSize);
          tts.analyserFreqBuf = new Uint8Array(analyser.frequencyBinCount);
        } catch (_) {}
      }
      audio.onplay = () => {
        setTTSLoading(false); startVisemeAnim(text);
        if (navigator.vibrate) navigator.vibrate([35, 55, 35]);
        rootBody.dataset.ttsWave = 'true';
      };
      audio.onended = audio.onerror = () => {
        setTTSLoading(false);
        stopVisemeAnim();
        rootBody.dataset.ttsWave = '';
        tts.analyser = null; tts.analyserBuf = null; tts.analyserFreqBuf = null;
        URL.revokeObjectURL(src);
        tts.audio = null; tts.playing = false;
        if (State.mode === 'speaking') State.mode = 'idle';
        clearViseme();
        if (ttsLive) ttsLive.textContent = '';
        ttsTick();
      };
      return audio.play();
    })
    .catch(() => {
      tts.audio = null; tts.playing = false; setTTSLoading(false);
      const s = document.getElementById('zsh-status');
      if (s) { s.textContent = 'tts fail'; rootBody.dataset.ttsError = 'true'; setTimeout(() => { rootBody.dataset.ttsError = ''; if (s.textContent === 'tts fail') s.textContent = ''; }, 2500); }
      if (token === tts.cancelToken) ttsTick();
    });
}

// Sample the cleaned text across the audio length so the mouth moves with real prosody.
function startVisemeAnim(text) {
  stopVisemeAnim();
  const words = text.split(/\s+/);
  let lastWordIdx = -1;
  let i = 0;
  tts.visemeTimer = setInterval(() => {
    const audio = tts.audio;
    if (!audio || !audio.duration || !isFinite(audio.duration)) { setViseme(text.charAt(i)); i = (i + 3) % text.length; return; }
    const idx = Math.min(text.length - 1, Math.floor((audio.currentTime / audio.duration) * text.length));
    setViseme(text.charAt(idx));
    // drive closed-caption strip (FA141) on word-boundary proxy
    if (ttsLive) {
      const denom = Math.max(1, text.length);
      const wIdx = Math.min(words.length - 1, Math.floor((idx / denom) * words.length));
      if (wIdx !== lastWordIdx) {
        lastWordIdx = wIdx;
        const from = Math.max(0, wIdx - 2);
        const to = Math.min(words.length, wIdx + 3);
        ttsLive.textContent = words.slice(from, to).join(' ');
      }
    }
  }, VISEME_STEP_MS);
}

function stopVisemeAnim() {
  if (tts.visemeTimer) { clearInterval(tts.visemeTimer); tts.visemeTimer = null; }
}

function ttsSkip() {
  tts.cancelToken++;
  setTTSLoading(false);
  if (tts.audio) { try { tts.audio.pause(); } catch (_) {} tts.audio = null; }
  stopVisemeAnim();
  tts.queue.length = 0; tts.prefetch.clear(); tts.playing = false; tts.current = null;
  clearViseme();
  if (ttsLive) ttsLive.textContent = '';
}
function ttsToggleMute() {
  tts.muted = !tts.muted;
  if (tts.muted) ttsSkip();
  beep(tts.muted ? 220 : 880, 0.05);
}

function cancelStream() {
  if (evtSrc) { try { evtSrc.close(); } catch (_) {} evtSrc = null; }
  window._chatCancel?.();
  ttsSkip();
  State.mode = 'idle';
  State.flash = 0.2;
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
  if (tts.playing) ttsSkip();
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
      morphCurrent = Math.max(0, morphCurrent - 0.7); morphTarget = 1.0;
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
    const live = document.getElementById('mood-live');
    if (live) live.textContent = 'mood: ' + m;
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
      morphTarget = 1.0; morphCurrent = Math.min(1, morphCurrent + 0.3);
    }
    if (v === 'veto') {
      beep(220, 0.10); State.shake = 0.6; dollyZoom(0.8);
      morphCurrent = Math.max(0, morphCurrent - 0.8); morphTarget = 1.0;
    }
  });
  evtSrc.addEventListener('council:speech', (ev) => {
    try {
      const { voice, text, persona } = JSON.parse(ev.data || '{}');
      if (persona) rootBody.dataset.councilPersona = persona;
      if (voice && text && !tts.playing) playDuo([[voice, text]]);
      setTimeout(() => { if (rootBody.dataset.councilPersona === persona) delete rootBody.dataset.councilPersona; }, 8000);
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
  loadTTSBlob(text, voice)
    .then(blob => {
      const src = URL.createObjectURL(blob);
      const audio = new Audio(src);
      if (actx && actx.state !== 'closed') {
        if (actx.state === 'suspended') actx.resume();
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

let visualEventSource = null;
function handleGlobalBusEvent(payload) {
  const data = payload && (payload.data || payload);
  const type = payload && (payload.type || (data && (data.event || data.name)));
  if (!type) return;
  if (type === 'tts:anticipate') {
    window.dispatchEvent(new CustomEvent('tts:anticipate', { detail: data }));
  }
  if (type === 'tts:style:active') {
    window.dispatchEvent(new CustomEvent('master:visual', { detail: { ...data, name: type, raw: data } }));
  }
}

function bindGlobalEventStream() {
  if (!window.EventSource || visualEventSource) return;
  try {
    visualEventSource = new EventSource('/events/stream');
    visualEventSource.onmessage = (ev) => {
      try { handleGlobalBusEvent(JSON.parse(ev.data || '{}')); } catch (_) {}
    };
    visualEventSource.onerror = () => {
      if (visualEventSource && visualEventSource.readyState === EventSource.CLOSED) visualEventSource = null;
    };
  } catch (_) {
    visualEventSource = null;
  }
}

function startEverything() {
  morphCurrent = 0.72; morphTarget = 1.08;
  initAudio();
  bindGlobalEventStream();
  if (actx && actx.state === 'suspended') actx.resume();
  beep(880, 0.06);
  primer.style.transition = 'opacity 160ms ease, transform 160ms ease';
  primer.style.opacity = '0'; primer.style.transform = 'scale(0.93)';
  setTimeout(() => primer.remove(), 200);
  zshBar.classList.add('live');
  const logo = document.querySelector('.top-left-logo');
  if (logo) {
    logo.style.transition = 'none';
    logo.style.transform = 'translateX(3px)';
    setTimeout(() => { logo.style.transition = 'transform 80ms ease'; logo.style.transform = ''; }, 80);
  }
  requestMotionPermission(); acquireWakeLock();
  setTimeout(() => { morphTarget = 1.0; }, 600);
  setTimeout(() => playDuo(BOOT_DUO), 120);
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
}
let primerFired = false;
function firePrimer() { if (primerFired) return; primerFired = true; startEverything(); }
primer.addEventListener('pointerdown', firePrimer);
primer.addEventListener('touchstart', firePrimer, { passive: true });
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

const PLACEHOLDERS = ['ask anything', 'what do you think?', 'challenge me', 'show your work', 'explain simply'];
let _phIdx = 0;
setInterval(() => {
  if (document.activeElement === zshIn || zshIn.value) return;
  _phIdx = (_phIdx + 1) % PLACEHOLDERS.length;
  zshIn.placeholder = PLACEHOLDERS[_phIdx];
}, 8000);

const _charCount = document.getElementById('char-count');
zshIn.addEventListener('input', () => {
  const len = zshIn.value.length;
  if (_charCount) { _charCount.textContent = len > 120 ? len : ''; _charCount.style.opacity = len > 120 ? '0.5' : '0'; }
});

let _swipeStartX = 0, _swipeStartY = 0;
const chatLog = document.getElementById('chat-log');
if (chatLog) {
  chatLog.addEventListener('touchstart', e => { _swipeStartX = e.touches[0].clientX; _swipeStartY = e.touches[0].clientY; }, { passive: true });
  chatLog.addEventListener('touchend', e => {
    const dx = e.changedTouches[0].clientX - _swipeStartX;
    const dy = Math.abs(e.changedTouches[0].clientY - _swipeStartY);
    if (dx > 72 && dy < 40) cancelStream();
  }, { passive: true });
}

const _origHaptic = enqueueSpeech;
window.MASTERVoice && (window.MASTERVoice._hapticPatch = true);

document.getElementById('cancel-btn')?.addEventListener('click', () => cancelStream());

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { e.preventDefault(); cancelStream(); }
  if (e.ctrlKey && e.key === 'm') { e.preventDefault(); ttsToggleMute(); }
});

window.sendMessage = sendMessage;
window.MASTERVoice = {
  enqueue: enqueueSpeech,
  skip: ttsSkip,
  toggleMute: ttsToggleMute,
  speak: (t) => enqueueSpeech(t),
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

if (renderer) {
  if (_dbgEl) {
    const _dbgTimer = setInterval(() => {
      if (!_dbgEl.isConnected) { clearInterval(_dbgTimer); return; }
      _dbgEl.textContent = `webgl ok · f:${_dbgFrames} m:${morphCurrent.toFixed(2)}`;
    }, 500);
    setTimeout(() => { clearInterval(_dbgTimer); _dbgEl.remove(); }, 30000);
  }
  requestAnimationFrame(frame);
} else {
  // 2D canvas fallback — fresh canvas so cv's WebGL attempt doesn't block us
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

    // Auto-fire primer after 1s if user hasn't tapped — gets chat bar up immediately
    setTimeout(() => { if (!primerFired) firePrimer(); }, 1000);

    let lastT2 = 0;
    function frame2(t) {
      if (t - lastT2 < 33) { requestAnimationFrame(frame2); return; }
      lastT2 = t;
      const sec = t * 0.001;
      const mTgt = primerFired ? 1.0 : 0.0;
      morphCurrent += (mTgt - morphCurrent) * 0.06;
      const m = morphCurrent;

      const cosY = Math.cos(State.mouseX * 0.7 + Math.sin(sec * 0.2) * 0.05);
      const sinY = Math.sin(State.mouseX * 0.7 + Math.sin(sec * 0.2) * 0.05);
      const cosX = Math.cos(State.mouseY * 0.4 + Math.sin(sec * 0.27) * 0.03);
      const sinX = Math.sin(State.mouseY * 0.4 + Math.sin(sec * 0.27) * 0.03);
      const f2 = Math.min(cw2, ch2) * 0.5 / Math.tan(38 * Math.PI / 360);
      const camZ = 4.6;

      ctx2.fillStyle = '#000';
      ctx2.fillRect(0, 0, cw2, ch2);
      ctx2.fillStyle = State.highContrast ? '#fff' : 'rgba(255,255,255,0.7)';

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
        ctx2.fillRect(px - sz * 0.5, py - sz * 0.5, sz, sz);
      }

      _dbgFrames++;
      markFaceReady();
      requestAnimationFrame(frame2);
    }
    requestAnimationFrame(frame2);
  })();
}

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
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: 240, height: 180 }
      });
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
          // Fleshed out cam "face tracking" (brightness center as user face proxy,
          // synced from shared minimal-gesture)
          // Drives particle "eye contact" + creative pulse when user faces the UI
          State.mouseX = nx;
          State.mouseY = ny;
          if (Math.abs(nx) < 0.3 && Math.abs(ny) < 0.3) {
            State.pulse = Math.max(State.pulse || 0, 0.5);
          }
        }
      }, 160);
    } catch (_) {}
  }
  if (State.coarsePointer) setTimeout(enableCamTracking, 900);

  // Global hook so Rails apps can call the same minimal + Osman experience
  window.MASTERMinimalUI = {
    enableCam: enableCamTracking,
    revealConsole: () => {
      const z = document.getElementById('zsh');
      if (z) z.classList.add('revealed');
    },
    triggerOsman: (text) => {
      if (window.sendMessage) window.sendMessage(`/voice ${text || 'last'} osman`);
    }
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
    document.addEventListener('keydown', e => {
      if (e.key === '?') { e.preventDefault(); rec.start(); }
    });
    window.startOsmanVoice = () => rec.start();
  }
})();
