"use strict";
const cv = document.getElementById('face');
const ctx = cv.getContext('2d');
let W = 0, H = 0;
const COARSE_DPR = matchMedia('(pointer: coarse)').matches;
let DPR = COARSE_DPR ? 1 : Math.min(window.devicePixelRatio || 1, 2);

// Half-res offscreen canvas — Atkinson-dithered particle layer, blitted 2× to main
let lpxCV = document.createElement('canvas');
let lpxCtx = lpxCV.getContext('2d');
let lpxW = 0, lpxH = 0;

// Oscilloscope XY mini-canvas — 128×128 particle XY plot, corner overlay
const scopeCV  = document.createElement('canvas');
const scopeCtx = scopeCV.getContext('2d');
scopeCV.width = scopeCV.height = 128;
let scopeBuf = new Float32Array(128 * 128);

// Float accumulation buffer — phosphor persistence (never written by dithering)
let fbuf = null, fbufSize = 0;
// Per-frame Atkinson error buffer — zeroed each frame, never persists
let ebuf = null;
let zbuf = null; // zone index per lpxCV pixel — drives ZX attribute colour

// Zone glyph stamps — [dx, dy] offsets in lpxCV (half-res) space
// Suggest geometric character: | for contours, — for brows, □ for eyes, + for crown
const ZONE_STAMP = {
  outlineL:  [[0,0],[0,1]], outlineR:  [[0,0],[0,1]],
  noseRidge: [[0,0],[0,1]],
  browL:     [[0,0],[1,0]], browR:     [[0,0],[1,0]],
  mouth:     [[0,0],[1,0]], chin:      [[0,0],[1,0]],
  eyeL:      [[0,0],[1,0],[0,1],[1,1]], eyeR:   [[0,0],[1,0],[0,1],[1,1]],
  pupilL:    [[0,0],[1,0],[0,1],[1,1]], pupilR: [[0,0],[1,0],[0,1],[1,1]],
  crown:     [[0,0]],
  scarL:     [[0,0],[1,1]], scarR: [[1,0],[0,1]],
  noseFlare: [[0,0],[1,0]],
  tasselL:   [[0,0],[0,1]], tasselR: [[0,0],[0,1]],
};
const _STAMP_DEFAULT = [[0,0]];

// Pixel palette — CSS filter applied at blit time; cycles with P key
// Index 5 = ZX Spectrum attribute mode; index 6 = Bayer ordered dithering
let pixelPal = 0;
const PIXEL_FILTERS = [
  null,
  'sepia(1) hue-rotate(70deg)  saturate(5) brightness(0.85)',
  'sepia(1) hue-rotate(200deg) saturate(4) brightness(0.75)',
  'sepia(1) hue-rotate(340deg) saturate(4) brightness(0.95)',
  'sepia(1) hue-rotate(290deg) saturate(6) brightness(1.05)',
  null, // ZX — zone colours via zbuf
  null, // BAYER — ordered threshold, no CSS filter
];
const PIXEL_PAL_NAMES = ['MONO', 'GB', 'C64', 'AMB', 'NEO', 'ZX', 'BAYER'];
// Bayer 4×4 ordered dithering matrix, normalized 0→1
const BAYER4 = new Float32Array([
   0/16,  8/16,  2/16, 10/16,
  12/16,  4/16, 14/16,  6/16,
   3/16, 11/16,  1/16,  9/16,
  15/16,  7/16, 13/16,  5/16,
]);

// ZX Spectrum attribute colours per zone (Uint32 RGBA little-endian)
// R|(G<<8)|(B<<16)|(0xFF<<24)
const ZX_ZONE_IDX = {
  outlineL:1, outlineR:1, eyeL:2, eyeR:2, pupilL:3, pupilR:3,
  browL:4, browR:4, noseRidge:5, noseFlare:5, mouth:6, chin:7,
  crown:8, scarL:9, scarR:9, tasselL:10, tasselR:10,
  sideL:11, sideR:11,
};
const ZX_PALETTE = [
  0xFFFFFFFF, // 0 default — white
  0xFFFF00FF, // 1 outline — magenta (ZX BRIGHT)
  0xFFFF0000, // 2 eye     — blue    (ZX BRIGHT)
  0xFFFFFFFF, // 3 pupil   — white
  0xFF00FF00, // 4 brow    — green   (ZX BRIGHT)
  0xFFD7D7D7, // 5 nose    — grey    (ZX non-BRIGHT white)
  0xFF0000FF, // 6 mouth   — red     (ZX BRIGHT)
  0xFF00FFFF, // 7 chin    — yellow  (ZX BRIGHT)
  0xFFFFFF00, // 8 crown   — cyan    (ZX BRIGHT)
  0xFF0000FF, // 9 scar    — red     (ZX BRIGHT)
  0xFF00FF00, // 10 tassel — green   (ZX BRIGHT)
  0xFFFF00FF, // 11 side   — magenta (ZX BRIGHT)
];

// Preallocated curl output — avoids GC allocation every frame per particle
const _curl = new Float32Array(2);
// Scratch buffer for ZX 8×8 block vote — avoids per-block allocation
const _zxVotes = new Uint8Array(16);

// Frame counters
let _repulseFrame = 0, _bfSkip = 0, _flashFrame = 0;

// Battery 30fps cap
let _fps30 = false;
if (navigator.getBattery) navigator.getBattery().then(b => {
  const chk = () => { _fps30 = !b.charging && b.level < 0.25; };
  b.addEventListener('chargingchange', chk); b.addEventListener('levelchange', chk); chk();
}).catch(() => {});

// Marquee state
let _marqueeX = 0;

// Frame-rate-independent smoothing — reference is 60 fps (16.667 ms).
// _dtL: per-frame lerp rate r → effective rate over dt ms. Preserves exact rate at 60 fps.
// _dtN: per-frame decay factor k → effective factor over dt ms. Same property.
const _DT_REF = 16.667;
const _dtL = (r, dt) => 1 - Math.pow(1 - r, dt / _DT_REF);
const _dtN = (k, dt) => Math.pow(k, dt / _DT_REF);

let _resizeTimer = 0;
function resize() {
  clearTimeout(_resizeTimer);
  _resizeTimer = setTimeout(_doResize, 180);
}
function _doResize() {
  W = window.innerWidth; H = window.innerHeight;
  DPR = COARSE_DPR ? 1 : Math.min(window.devicePixelRatio || 1, 2);
  cv.width = W * DPR; cv.height = H * DPR;
  cv.style.width = W + 'px'; cv.style.height = H + 'px';
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  lpxW = W >> 1; lpxH = H >> 1;
  lpxCV.width = lpxW; lpxCV.height = lpxH;
  _marqueeX = W;
  computeZones(); assignHomes();
}

  // Face zones — Fibonacci-sphere-projected home anchors per zone
  const Face = {
    zones: {},
    yaw: 0, yawTarget: 0, pitch: 0, pitchTarget: 0,
    blink: 0, blinkPhase: 0,
    gaze: [0, 0], gazeTarget: [0, 0],
    pupil: 1.0, pupilTarget: 1.0,
    brow: 0, browTarget: 0,
    mouth: 'neutral',
    breath: 0,
    blinkAt: 0,
    vortex: 0,
    dispersion: 0, dispersionTarget: 0,
    coronaFlash: 0,
    edgePulse: 0,
    bodyScale: 1.0,
    heartRate: 1.0,
    codespaceRatio: 0, codespaceTarget: 0
  };

  function ring(cx, cy, r, a0, a1, n, zone) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const t = a0 + (a1 - a0) * (n > 1 ? i / (n - 1) : 0);
      out.push({ x: cx + Math.cos(t) * r, y: cy + Math.sin(t) * r * 0.95, zone });
    }
    return out;
  }
  function disc(cx, cy, r, n, zone) {
    const out = [];
    const golden = Math.PI * (3 - Math.sqrt(5));
    for (let i = 0; i < n; i++) {
      const rr = r * Math.sqrt((i + 0.5) / n);
      const a = i * golden;
      out.push({ x: cx + Math.cos(a) * rr, y: cy + Math.sin(a) * rr, zone });
    }
    return out;
  }
  function line(x0, y0, x1, y1, n, zone) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const t = n > 1 ? i / (n - 1) : 0;
      out.push({ x: x0 + (x1 - x0) * t, y: y0 + (y1 - y0) * t, zone });
    }
    return out;
  }
  function mouthArc(cx, cy, w, shape, n) {
    const out = new Array(n);
    for (let i = 0; i < n; i++) {
      const t = n > 1 ? i / (n - 1) : 0;
      const x = cx - w / 2 + w * t;
      let y = cy;
      const u = (t - 0.5) * 2;
      if (shape === 'smile')   y = cy - Math.sin(t * Math.PI) * w * 0.18 + u * u * w * 0.05;
      if (shape === 'frown')   y = cy + Math.sin(t * Math.PI) * w * 0.18 - u * u * w * 0.05;
      if (shape === 'O')       y = cy + Math.sin(t * Math.PI) * w * 0.32;
      if (shape === 'A')       y = cy + Math.sin(t * Math.PI) * w * 0.45;
      if (shape === 'E')       y = cy + Math.sin(t * Math.PI) * w * 0.08;
      if (shape === 'M')       y = cy + Math.sin(t * Math.PI) * w * 0.02;
      if (shape === 'I')       y = cy + Math.sin(t * Math.PI) * w * 0.12;
      if (shape === 'U')       y = cy + Math.sin(t * Math.PI) * w * 0.25;
      out[i] = { x, y, zone: 'mouth' };
    }
    return out;
  }

  // Mask library — auto-rotates between PNG mask traditions
  // Sepik River, Asmat, Baining fire dance, Tolai Tubuan, Malagan.
  // Each builder returns a flat anchor list. Cross-fade handled below.
  const MASKS = ['sepik', 'asmat', 'baining', 'tolai', 'malagan'];
  let maskIdx = 0, maskNextIdx = 0;
  function buildSepik(cx, cy, s) {
    const z = {};
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 60; i++) {
      const t = i / 59, y = cy - s * 1.45 + t * s * 2.9;
      const w = s * (0.65 * Math.sin(t * Math.PI) + 0.15);
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    z.crown = [];
    for (let i = 0; i < 14; i++) {
      const a = -Math.PI * 0.5 + (i - 7) * 0.12;
      const len = s * (0.7 + Math.sin(i * 1.3) * 0.25);
      for (let t = 0; t < 1; t += 0.08) {
        const r = s * 0.8 + t * len;
        z.crown.push({ x: cx + Math.cos(a) * r * 0.6, y: cy - s * 0.7 + Math.sin(a) * r, zone: 'crown' });
      }
    }
    // Sepik: hooked beak ridge — straight down then curves forward like a hornbill
    const nrPts = [];
    for (let i = 0; i < 22; i++) {
      const t = i / 21;
      nrPts.push({ x: cx, y: cy - s * 0.5 + t * s * 0.95, zone: 'noseRidge' });
    }
    for (let i = 0; i < 9; i++) {
      const t = i / 8;
      const a = -Math.PI * 0.5 + t * (Math.PI * 0.55);
      nrPts.push({ x: cx + Math.cos(a) * s * 0.13, y: cy + s * 0.45 + Math.sin(a) * s * 0.13, zone: 'noseRidge' });
    }
    z.noseRidge = nrPts;
    // nostril wings as small arcs rather than a straight bar
    z.noseFlare = ring(cx - s * 0.08, cy + s * 0.52, s * 0.06, Math.PI * 0.5, Math.PI * 1.5, 6, 'noseFlare')
                 .concat(ring(cx + s * 0.08, cy + s * 0.52, s * 0.06, -Math.PI * 0.5, Math.PI * 0.5, 6, 'noseFlare'));
    z.browL = line(cx - s * 0.55, cy - s * 0.4, cx - s * 0.12, cy - s * 0.2, 14, 'browL');
    z.browR = line(cx + s * 0.12, cy - s * 0.2, cx + s * 0.55, cy - s * 0.4, 14, 'browR');
    z.eyeL = ring(cx - s * 0.32, cy - s * 0.1, s * 0.12, 0, Math.PI * 2, 20, 'eyeL')
            .concat(ring(cx - s * 0.32, cy - s * 0.1, s * 0.07, 0, Math.PI * 2, 12, 'eyeL'));
    z.eyeR = ring(cx + s * 0.32, cy - s * 0.1, s * 0.12, 0, Math.PI * 2, 20, 'eyeR')
            .concat(ring(cx + s * 0.32, cy - s * 0.1, s * 0.07, 0, Math.PI * 2, 12, 'eyeR'));
    z.pupilL = disc(cx - s * 0.32, cy - s * 0.1, s * 0.025, 5, 'pupilL');
    z.pupilR = disc(cx + s * 0.32, cy - s * 0.1, s * 0.025, 5, 'pupilR');
    z.scarL = []; z.scarR = [];
    for (let r = 0; r < 3; r++) {
      const y = cy + s * (0.08 + r * 0.13);
      z.scarL = z.scarL.concat(line(cx - s * 0.55, y, cx - s * 0.30, y, 8, 'scarL'));
      z.scarR = z.scarR.concat(line(cx + s * 0.30, y, cx + s * 0.55, y, 8, 'scarR'));
    }
    z.mouth = mouthArc(cx, cy + s * 0.92, s * 0.7, Face.mouth, 30);
    for (let i = 0; i < 7; i++) {
      const tx = cx - s * 0.32 + i * (s * 0.64 / 6);
      z.mouth.push({ x: tx, y: cy + s * 0.88, zone: 'mouth' });
      z.mouth.push({ x: tx, y: cy + s * 0.96, zone: 'mouth' });
    }
    z.chin = line(cx - s * 0.18, cy + s * 1.15, cx, cy + s * 1.40, 8, 'chin')
            .concat(line(cx, cy + s * 1.40, cx + s * 0.18, cy + s * 1.15, 8, 'chin'));
    z.tasselL = []; z.tasselR = [];
    for (let r = 0; r < 6; r++) {
      const y = cy - s * 0.4 + r * s * 0.25;
      z.tasselL.push({ x: cx - s * 0.95, y, zone: 'tasselL' });
      z.tasselR.push({ x: cx + s * 0.95, y, zone: 'tasselR' });
    }
    return z;
  }
  // Asmat — wooden eye lozenges (diamond-carved), hornbill nosepiece, geometric incisions
  function buildAsmat(cx, cy, s) {
    const z = {};
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 60; i++) {
      const t = i / 59, y = cy - s * 1.3 + t * s * 2.6;
      const w = s * (0.55 - Math.abs(t - 0.5) * 0.4);
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    // eye lozenges — diamond (♦) shape, Met collection reference
    function lozenge(ex, ey, hw, hh, zone) {
      const pts = [];
      const n = 16;
      for (let i = 0; i < n; i++) {
        const t = i / n * Math.PI * 2;
        // lozenge: |x/hw| + |y/hh| = 1 parameterised via angle
        const cos = Math.cos(t), sin = Math.sin(t);
        const r = 1 / (Math.abs(cos) / hw + Math.abs(sin) / hh);
        pts.push({ x: ex + cos * r, y: ey + sin * r, zone });
      }
      return pts;
    }
    z.eyeL = lozenge(cx - s * 0.30, cy - s * 0.05, s * 0.18, s * 0.10, 'eyeL');
    z.eyeR = lozenge(cx + s * 0.30, cy - s * 0.05, s * 0.18, s * 0.10, 'eyeR');
    z.pupilL = disc(cx - s * 0.30, cy - s * 0.05, s * 0.04, 6, 'pupilL');
    z.pupilR = disc(cx + s * 0.30, cy - s * 0.05, s * 0.04, 6, 'pupilR');
    z.noseRidge = line(cx, cy - s * 0.3, cx, cy + s * 0.5, 22, 'noseRidge');
    // hooked nose tip
    z.noseRidge = z.noseRidge.concat(line(cx, cy + s * 0.5, cx + s * 0.18, cy + s * 0.45, 6, 'noseRidge'));
    z.mouth = ring(cx, cy + s * 0.85, s * 0.18, 0, Math.PI * 2, 18, 'mouth');
    // geometric forehead chevrons
    z.crown = [];
    for (let r = 0; r < 3; r++) {
      const y = cy - s * (0.7 + r * 0.15);
      z.crown = z.crown.concat(line(cx - s * 0.4, y, cx, y - s * 0.1, 8, 'crown'))
                        .concat(line(cx, y - s * 0.1, cx + s * 0.4, y, 8, 'crown'));
    }
    z.browL = line(cx - s * 0.48, cy - s * 0.22, cx - s * 0.14, cy - s * 0.12, 10, 'browL');
    z.browR = line(cx + s * 0.14, cy - s * 0.12, cx + s * 0.48, cy - s * 0.22, 10, 'browR');
    z.noseFlare = ring(cx - s * 0.06, cy + s * 0.50, s * 0.04, Math.PI * 0.5, Math.PI * 1.5, 5, 'noseFlare')
                 .concat(ring(cx + s * 0.06, cy + s * 0.50, s * 0.04, -Math.PI * 0.5, Math.PI * 0.5, 5, 'noseFlare'));
    z.chin = line(cx - s * 0.14, cy + s * 1.1, cx + s * 0.14, cy + s * 1.1, 8, 'chin');
    z.scarL = []; z.scarR = [];
    for (let r = 0; r < 2; r++) {
      const y = cy + s * (0.12 + r * 0.14);
      z.scarL = z.scarL.concat(line(cx - s * 0.50, y, cx - s * 0.28, y, 6, 'scarL'));
      z.scarR = z.scarR.concat(line(cx + s * 0.28, y, cx + s * 0.50, y, 6, 'scarR'));
    }
    // ear/jaw bones
    z.tasselL = line(cx - s * 0.6, cy + s * 0.3, cx - s * 0.7, cy + s * 0.9, 10, 'tasselL');
    z.tasselR = line(cx + s * 0.6, cy + s * 0.3, cx + s * 0.7, cy + s * 0.9, 10, 'tasselR');
    return z;
  }
  // Baining fire dance — large white-on-black, big round eye-holes, exaggerated mouth
  function buildBaining(cx, cy, s) {
    const z = {};
    // huge round outline
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 70; i++) {
      const a = -Math.PI + i / 70 * Math.PI * 2;
      const r = s * 1.3;
      const p = { x: cx + Math.cos(a) * r * 0.85, y: cy + Math.sin(a) * r, zone: a < 0 ? 'outlineL' : 'outlineR' };
      (a < 0 ? z.outlineL : z.outlineR).push(p);
    }
    // Baining: giant startled round eyes with spiraling pupils (Bowers Museum ref)
    z.eyeL = ring(cx - s * 0.45, cy - s * 0.25, s * 0.30, 0, Math.PI * 2, 32, 'eyeL');
    z.eyeR = ring(cx + s * 0.45, cy - s * 0.25, s * 0.30, 0, Math.PI * 2, 32, 'eyeR');
    // spiral pupils — trace an Archimedean spiral
    const spiralEye = (ex, ey, zone) => {
      const pts = [];
      for (let i = 0; i < 28; i++) {
        const t = i / 27;
        const a = t * Math.PI * 4;
        const r = t * s * 0.20;
        pts.push({ x: ex + Math.cos(a) * r, y: ey + Math.sin(a) * r * 0.8, zone });
      }
      return pts;
    };
    z.pupilL = spiralEye(cx - s * 0.45, cy - s * 0.25, 'pupilL');
    z.pupilR = spiralEye(cx + s * 0.45, cy - s * 0.25, 'pupilR');
    // small broad nose bridge
    z.noseRidge = line(cx, cy + s * 0.05, cx, cy + s * 0.35, 12, 'noseRidge');
    // wide protruding lips — Vungvung reference: large, pronounced
    z.mouth = ring(cx, cy + s * 0.72, s * 0.48, 0, Math.PI, 26, 'mouth');
    z.mouth = z.mouth.concat(ring(cx, cy + s * 0.63, s * 0.40, 0, Math.PI, 18, 'mouth'))
                     .concat(line(cx - s * 0.48, cy + s * 0.72, cx + s * 0.48, cy + s * 0.72, 16, 'mouth'));
    z.browL = line(cx - s * 0.70, cy - s * 0.60, cx - s * 0.14, cy - s * 0.58, 14, 'browL');
    z.browR = line(cx + s * 0.14, cy - s * 0.58, cx + s * 0.70, cy - s * 0.60, 14, 'browR');
    z.noseFlare = ring(cx - s * 0.10, cy + s * 0.38, s * 0.06, Math.PI * 0.5, Math.PI * 1.5, 6, 'noseFlare')
                 .concat(ring(cx + s * 0.10, cy + s * 0.38, s * 0.06, -Math.PI * 0.5, Math.PI * 0.5, 6, 'noseFlare'));
    z.chin = line(cx - s * 0.22, cy + s * 1.08, cx + s * 0.22, cy + s * 1.20, 10, 'chin');
    z.scarL = line(cx - s * 0.68, cy + s * 0.10, cx - s * 0.38, cy + s * 0.10, 8, 'scarL');
    z.scarR = line(cx + s * 0.38, cy + s * 0.10, cx + s * 0.68, cy + s * 0.10, 8, 'scarR');
    z.tasselL = []; z.tasselR = [];
    for (let r = 0; r < 5; r++) {
      z.tasselL.push({ x: cx - s * (0.90 + r * 0.04), y: cy + s * (0.20 + r * 0.18), zone: 'tasselL' });
      z.tasselR.push({ x: cx + s * (0.90 + r * 0.04), y: cy + s * (0.20 + r * 0.18), zone: 'tasselR' });
    }
    // antenna-like crown protrusions
    z.crown = [];
    for (let i = 0; i < 4; i++) {
      const ax = cx + (i - 1.5) * s * 0.3;
      z.crown = z.crown.concat(line(ax, cy - s * 1.3, ax, cy - s * 1.7, 8, 'crown'));
    }
    return z;
  }
  // Tolai Tubuan — conical/triangular, wide round eyes, tassel-heavy
  function buildTolai(cx, cy, s) {
    const z = {};
    // triangular silhouette — wide bottom narrowing to point
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 50; i++) {
      const t = i / 49;
      const y = cy - s * 1.4 + t * s * 2.6;
      const w = s * 0.15 + t * s * 0.7;
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    // wide round eyes
    z.eyeL = ring(cx - s * 0.30, cy + s * 0.05, s * 0.18, 0, Math.PI * 2, 24, 'eyeL');
    z.eyeR = ring(cx + s * 0.30, cy + s * 0.05, s * 0.18, 0, Math.PI * 2, 24, 'eyeR');
    z.pupilL = disc(cx - s * 0.30, cy + s * 0.05, s * 0.06, 8, 'pupilL');
    z.pupilR = disc(cx + s * 0.30, cy + s * 0.05, s * 0.06, 8, 'pupilR');
    z.noseRidge = line(cx, cy + s * 0.25, cx, cy + s * 0.7, 14, 'noseRidge');
    z.mouth = mouthArc(cx, cy + s * 0.95, s * 0.4, 'O', 20);
    z.browL = line(cx - s * 0.52, cy - s * 0.18, cx - s * 0.10, cy - s * 0.10, 12, 'browL');
    z.browR = line(cx + s * 0.10, cy - s * 0.10, cx + s * 0.52, cy - s * 0.18, 12, 'browR');
    z.noseFlare = ring(cx - s * 0.07, cy + s * 0.68, s * 0.05, Math.PI * 0.5, Math.PI * 1.5, 5, 'noseFlare')
                 .concat(ring(cx + s * 0.07, cy + s * 0.68, s * 0.05, -Math.PI * 0.5, Math.PI * 0.5, 5, 'noseFlare'));
    z.chin = line(cx - s * 0.18, cy + s * 1.10, cx + s * 0.18, cy + s * 1.10, 8, 'chin');
    z.scarL = line(cx - s * 0.55, cy + s * 0.25, cx - s * 0.20, cy + s * 0.25, 8, 'scarL');
    z.scarR = line(cx + s * 0.20, cy + s * 0.25, cx + s * 0.55, cy + s * 0.25, 8, 'scarR');
    // crown — single tall point
    z.crown = line(cx, cy - s * 1.4, cx, cy - s * 1.9, 12, 'crown');
    // dense tassels both sides
    z.tasselL = []; z.tasselR = [];
    for (let r = 0; r < 10; r++) {
      const y = cy + s * (0.5 + r * 0.18);
      z.tasselL.push({ x: cx - s * (0.85 - r * 0.02), y, zone: 'tasselL' });
      z.tasselR.push({ x: cx + s * (0.85 - r * 0.02), y, zone: 'tasselR' });
    }
    return z;
  }
  // Malagan — openwork carving, multi-zone, animal-totem layers
  function buildMalagan(cx, cy, s) {
    const z = {};
    z.outlineL = []; z.outlineR = [];
    for (let i = 0; i < 55; i++) {
      const t = i / 54, y = cy - s * 1.2 + t * s * 2.4;
      const w = s * (0.6 - Math.sin(t * Math.PI * 3) * 0.08);
      z.outlineL.push({ x: cx - w, y, zone: 'outlineL' });
      z.outlineR.push({ x: cx + w, y, zone: 'outlineR' });
    }
    // beak-like nose protrusion
    const beakDir = maskIdx % 2 === 0 ? 1 : -1;
    z.noseRidge = line(cx, cy - s * 0.2, cx, cy + s * 0.4, 18, 'noseRidge')
                  .concat(line(cx, cy + s * 0.4, cx + beakDir * s * 0.15, cy + s * 0.55, 6, 'noseRidge'));
    // narrow slit eyes
    z.eyeL = line(cx - s * 0.45, cy - s * 0.1, cx - s * 0.18, cy - s * 0.1, 14, 'eyeL');
    z.eyeR = line(cx + s * 0.18, cy - s * 0.1, cx + s * 0.45, cy - s * 0.1, 14, 'eyeR');
    z.pupilL = disc(cx - s * 0.3, cy - s * 0.1, s * 0.02, 4, 'pupilL');
    z.pupilR = disc(cx + s * 0.3, cy - s * 0.1, s * 0.02, 4, 'pupilR');
    z.mouth = line(cx - s * 0.3, cy + s * 0.7, cx + s * 0.3, cy + s * 0.7, 18, 'mouth');
    // animal-totem stacking above head — bird/fish silhouettes
    z.crown = [];
    for (let i = 0; i < 18; i++) {
      const a = i / 17;
      const y = cy - s * (1.0 + a * 0.8);
      const w = s * (0.5 - a * 0.3);
      z.crown.push({ x: cx - w, y, zone: 'crown' });
      z.crown.push({ x: cx + w, y, zone: 'crown' });
      if (i % 3 === 0) z.crown.push({ x: cx, y, zone: 'crown' });
    }
    z.browL = line(cx - s * 0.45, cy - s * 0.20, cx - s * 0.16, cy - s * 0.14, 10, 'browL');
    z.browR = line(cx + s * 0.16, cy - s * 0.14, cx + s * 0.45, cy - s * 0.20, 10, 'browR');
    z.noseFlare = ring(cx - s * 0.06, cy + s * 0.44, s * 0.04, Math.PI * 0.5, Math.PI * 1.5, 4, 'noseFlare')
                 .concat(ring(cx + s * 0.06, cy + s * 0.44, s * 0.04, -Math.PI * 0.5, Math.PI * 0.5, 4, 'noseFlare'));
    z.chin = line(cx - s * 0.16, cy + s * 0.82, cx + s * 0.16, cy + s * 0.82, 8, 'chin');
    z.tasselL = []; z.tasselR = [];
    for (let r = 0; r < 5; r++) {
      z.tasselL.push({ x: cx - s * 0.70, y: cy + s * (0.10 + r * 0.20), zone: 'tasselL' });
      z.tasselR.push({ x: cx + s * 0.70, y: cy + s * (0.10 + r * 0.20), zone: 'tasselR' });
    }
    // openwork lattice — checkerboard diamond grid (New Ireland carved lattice)
    z.scarL = []; z.scarR = [];
    const owRows = 7, owCols = 6;
    for (let r = 0; r < owRows; r++) {
      for (let c = 0; c < owCols; c++) {
        if ((r + c) % 2 !== 0) continue;
        const gx = cx - s * 0.48 + c * (s * 0.96 / (owCols - 1));
        const gy = cy - s * 0.55 + r * (s * 0.90 / (owRows - 1));
        const ox2 = Math.sin(r * 2.1 + c * 1.7) * s * 0.025;
        const oy2 = Math.cos(r * 1.3 + c * 2.3) * s * 0.018;
        const zone = gx < cx ? 'scarL' : 'scarR';
        (gx < cx ? z.scarL : z.scarR).push({ x: gx + ox2, y: gy + oy2, zone });
      }
    }
    return z;
  }
  function buildMask(name, cx, cy, s) {
    let z;
    if (name === 'asmat') z = buildAsmat(cx, cy, s);
    else if (name === 'baining') z = buildBaining(cx, cy, s);
    else if (name === 'tolai') z = buildTolai(cx, cy, s);
    else if (name === 'malagan') z = buildMalagan(cx, cy, s);
    else z = buildSepik(cx, cy, s);
    return applyZ(z, cx, cy, s);
  }
  // Z — spheroid depth field + zone sculpture displacement.
  // Head modelled as oblate spheroid (w=0.85, h=1.45, d=0.45 in face-radii).
  // Positive z = toward viewer; negative = receding behind face plane.
  // Outline wraps to negative so rotation reveals back-of-head correctly.
  const ZONE_DISP = {
    noseFlare:  0.28, browL:     0.12, browR:     0.12,
    eyeL:      -0.10, eyeR:     -0.10, pupilL:    0.14, pupilR:    0.14,
    outlineL:  -0.38, outlineR: -0.38,
    chin:       0.14, mouth:     0.16, crown:      0.04,
    scarL:      0.06, scarR:     0.06,
    tasselL:   -0.12, tasselR:  -0.12,
  };
  function applyZ(zones, cx, cy, s) {
    for (const [name, list] of Object.entries(zones)) {
      for (let i = 0; i < list.length; i++) {
        const p = list[i];
        // Normalized model coords
        const mx = (p.x - cx) / s;
        const my = (p.y - cy) / s;
        // Spheroid base depth — smooth dome, zero at silhouette edge
        const mxn = mx / 0.85, myn = my / 1.45;
        const base = 0.42 * Math.sqrt(Math.max(0, 1 - mxn*mxn - myn*myn));
        let mz;
        if (name === 'noseRidge') {
          // Bell curve peaking at ~65% down the ridge (nose tip), falling toward bridge and nostrils
          const t = i / Math.max(1, list.length - 1);
          const bell = Math.sin(Math.min(t * 1.55, 1) * Math.PI * 0.5);
          mz = base + 0.10 + bell * bell * 0.46;
        } else {
          mz = base + (ZONE_DISP[name] || 0);
        }
        p.z = mz * s;
      }
    }
    return zones;
  }
  let zonesA = null, zonesB = null;
  let maskPhase = 0, maskTransitioning = false, lastMaskSwitch = performance.now();
  // Side-head anchors — temple/ear band, z=0 (equator plane).
  // Rotation in tickParticles naturally reveals them as yaw increases.
  function buildSideAnchors(cx, cy, s) {
    const L = [], R = [];
    for (let i = 0; i < 32; i++) {
      const t = i / 31;
      const y = cy - s * 0.72 + t * s * 1.44;
      const bulge = Math.sin(t * Math.PI) * s * 0.07;
      L.push({ x: cx - s * 0.88 - bulge, y, z: -0.10 * s, zone: 'sideL' });
      R.push({ x: cx + s * 0.88 + bulge, y, z: -0.10 * s, zone: 'sideR' });
    }
    return { sideL: L, sideR: R };
  }
  function computeZones() {
    const cx = W * 0.5, cy = H * 0.50;
    const s = Math.max(Math.min(W, H) * 0.30, Math.min(W, H * 0.78) * 0.22);
    Face.cx = cx; Face.cy = cy; Face.s = s;
    zonesA = buildMask(MASKS[maskIdx], cx, cy, s);
    zonesB = buildMask(MASKS[maskNextIdx], cx, cy, s);
    const sidesA = buildSideAnchors(cx, cy, s);
    zonesA.sideL = sidesA.sideL; zonesA.sideR = sidesA.sideR;
    const sidesB = buildSideAnchors(cx, cy, s);
    zonesB.sideL = sidesB.sideL; zonesB.sideR = sidesB.sideR;
    Face.zones = zonesA;
  }

  // Particles
  // Mobile budget: 2200 × 12-field × 3D transform per frame OOM'd phones.
  // 600 keeps the silhouette legible without melting the GPU/JIT.
  const COARSE = matchMedia('(pointer: coarse)').matches || Math.min(innerWidth, innerHeight) < 768;
  const N = COARSE ? 600 : 2200;
  const particles = [];
  for (let i = 0; i < N; i++) particles.push({
    x: Math.random() * 600, y: Math.random() * 600,
    vx: 0, vy: 0, px: 0, py: 0,
    hx: 0, hy: 0, hz: 0,
    hx1: 0, hy1: 0, hz1: 0,
    hx2: 0, hy2: 0, hz2: 0,
    ox: Math.sin(i * 7.13) * 0.5, oy: Math.cos(i * 11.7) * 0.5, oz: Math.sin(i * 3.97) * 0.4,
    zone: 'crown', sz: 0,
    mass: 0.7 + Math.random() * 0.6,
    lx: (Math.random() - 0.5) * 2, ly: (Math.random() - 0.5) * 2, lz: 24 + Math.random() * 4
  });
  // Zone particle density weights — high-detail features get proportionally more particles
  const ZONE_DENSITY = {
    pupilL: 5, pupilR: 5, eyeL: 3, eyeR: 3,
    noseRidge: 2, noseFlare: 2, mouth: 2, browL: 2, browR: 2,
  };
  const ZONE_K = {
    pupilL: 0.14, pupilR: 0.14, eyeL: 0.12, eyeR: 0.12,
    browL: 0.10, browR: 0.10, crown: 0.04, tasselL: 0.035, tasselR: 0.035
  };
  function weightedPool(zones) {
    const out = [];
    for (const [name, list] of Object.entries(zones)) {
      const w = ZONE_DENSITY[name] || 1;
      for (let r = 0; r < w; r++) for (let i = 0; i < list.length; i++) out.push(list[i]);
    }
    return out;
  }
  function assignHomes() {
    if (!zonesA) return;
    const A = weightedPool(zonesA);
    const B = zonesB ? weightedPool(zonesB) : A;
    if (!A.length) return;
    for (let i = 0; i < particles.length; i++) {
      const a = A[i % A.length];
      const b = B[i % B.length];
      const p = particles[i];
      p.hx1 = a.x + p.ox; p.hy1 = a.y + p.oy; p.hz1 = (a.z || 0) + p.oz;
      p.hx2 = b.x + p.ox; p.hy2 = b.y + p.oy; p.hz2 = (b.z || 0) + p.oz;
      p.hx = p.hx1; p.hy = p.hy1; p.hz = p.hz1;
      p.zone = a.zone;
    }
  }
  const ZONE_PHASE_LEAD = {
    outlineL: 0, outlineR: 0, browL: 0.22, browR: 0.22,
    eyeL: 0.38, eyeR: 0.38, pupilL: 0.52, pupilR: 0.52, mouth: 0.58, chin: 0.68
  };
  function updateHomeLerp() {
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const lead = ZONE_PHASE_LEAD[p.zone] || 0;
      const ph = lead < 1 ? Math.min(1, Math.max(0, maskPhase - lead) / Math.max(0.01, 1 - lead)) : maskPhase;
      const t = easeInOutCubic(ph);
      p.hx = p.hx1 + (p.hx2 - p.hx1) * t;
      p.hy = p.hy1 + (p.hy2 - p.hy1) * t;
      p.hz = p.hz1 + (p.hz2 - p.hz1) * t;
    }
  }
  function maybeSwitchMask(now, dt) {
    if (maskTransitioning) {
      maskPhase = Math.min(1, maskPhase + dt / 3000);
      updateHomeLerp();
      if (maskPhase >= 1) {
        maskTransitioning = false;
        maskIdx = maskNextIdx;
        zonesA = zonesB;
        for (let i = 0; i < particles.length; i++) {
          const p = particles[i];
          p.hx1 = p.hx2; p.hy1 = p.hy2; p.hz1 = p.hz2;
        }
      }
      return;
    }
    const interval = State.mode === 'idle' ? 90000 : 180000;
    if (now - lastMaskSwitch > interval) triggerMaskSwitch();
  }
  function triggerMaskSwitch() {
    if (maskTransitioning) return;
    lastMaskSwitch = performance.now();
    maskNextIdx = (maskIdx + 1) % MASKS.length;
    zonesB = buildMask(MASKS[maskNextIdx], Face.cx, Face.cy, Face.s);
    const B = weightedPool(zonesB);
    for (let i = 0; i < particles.length; i++) {
      const b = B[i % B.length], p = particles[i];
      p.hx2 = b.x + p.ox; p.hy2 = b.y + p.oy; p.hz2 = (b.z || 0) + p.oz;
    }
    maskPhase = 0; maskTransitioning = true; Face.vortex = 0.45;
  }

  // Palettes — base mono; state events call fadePaletteTo() to overlay
  function timePalette() {
    return { shadow: '0,0,0', midtone: '85,85,85', highlight: '255,255,255', accent: '255,255,255' };
  }
  let palette = timePalette(), sourcePalette = palette, targetPalette = palette, palBlend = 1.0;
  function lerpRGB(a, b, t) {
    const A = a.split(',').map(Number), B = b.split(',').map(Number);
    return `${A[0]+(B[0]-A[0])*t|0},${A[1]+(B[1]-A[1])*t|0},${A[2]+(B[2]-A[2])*t|0}`;
  }
  function lerpPalette(a, b, t) {
    return { shadow: lerpRGB(a.shadow, b.shadow, t), midtone: lerpRGB(a.midtone, b.midtone, t),
             highlight: lerpRGB(a.highlight, b.highlight, t), accent: lerpRGB(a.accent, b.accent, t) };
  }
  const PROVIDER_TINT = {
    claude:   { shadow: '10,0,18',  midtone: '80,60,110', highlight: '230,210,255', accent: '200,160,255' },
    deepseek: { shadow: '0,10,22',  midtone: '40,70,120', highlight: '180,210,255', accent: '100,170,255' },
    gemini:   { shadow: '0,14,10',  midtone: '40,100,80', highlight: '180,255,210', accent: '80,220,160'  },
    gpt:      { shadow: '14,14,0',  midtone: '90,90,50',  highlight: '240,240,180', accent: '220,220,100' }
  };
  const VERDICT_TINT = {
    pass:    { shadow: '0,12,4',   midtone: '40,90,55',  highlight: '180,255,200', accent: '120,255,160' },
    veto:    { shadow: '18,0,0',   midtone: '100,30,30', highlight: '200,80,80',   accent: '255,60,60'   },
    unclear: { shadow: '10,10,0',  midtone: '80,80,40',  highlight: '210,210,140', accent: '200,200,100' }
  };
  function fadePaletteTo(p, ms = 600) {
    sourcePalette = palette; targetPalette = p; palBlend = 0; palStart = performance.now(); palDur = ms;
  }
  let palStart = performance.now(), palDur = 600;

  function tickPalette(now) {
    if (palBlend < 1) {
      const t = Math.min(1, (now - palStart) / palDur);
      const e = easeInOutCubic(t);
      palette = lerpPalette(sourcePalette, targetPalette, e);
      if (t >= 1) { palette = targetPalette; palBlend = 1; }
    }
  }
  const easeInOutCubic = t => t < 0.5 ? 4*t*t*t : 1 - Math.pow(-2*t + 2, 3) / 2;

  // State
  const State = {
    mode: 'idle', // idle|listening|thinking|speaking|ack|error|sleep
    mood: 'idle', model: '', provider: '', modelName: '',
    lastTouch: performance.now(),
    sttActive: false, sttInterim: '',
    confidence: 1.0,
    audioLevel: 0,
    tiltX: 0, tiltY: 0,
    session: Math.floor(Math.random() * 1e9),
    prevBass: 0,
    lorenzMode: false,
    neonBleed: 0,
    comboCount: 0, comboDecay: 0, comboY: 0,
    continueCount: -1, continueTimer: 0
  };

  const MOOD_PALETTE = {
    tense:   { shadow: '18,0,0',   midtone: '100,30,30', highlight: '255,180,160', accent: '255,120,80'  },
    curious: { shadow: '0,10,18',  midtone: '40,80,120', highlight: '180,220,255', accent: '120,200,255' },
    focused: { shadow: '0,8,14',   midtone: '30,60,90',  highlight: '160,200,240', accent: '80,160,220'  },
    weary:   { shadow: '8,8,12',   midtone: '55,55,65',  highlight: '170,170,190', accent: '140,140,160' }
  };

  // Audio (ambient pad + analyser)
  let actx = null, analyser = null, freqData = null, padGain1 = null, padGain2 = null, osc1 = null, osc2 = null;
  const MOOD_FREQ = {
    focused:[110.00, 164.81], curious:[123.47, 196.00], tense:[130.81, 207.65],
    weary:[98.00, 146.83], idle:[110.00, 164.81]
  };
  function initAudio() {
    if (actx) return;
    try {
      actx = new (window.AudioContext || window.webkitAudioContext)();
      analyser = actx.createAnalyser(); analyser.fftSize = 256;
      freqData = new Uint8Array(analyser.frequencyBinCount);
      osc1 = actx.createOscillator(); osc1.type = 'sine'; osc1.frequency.value = 110;
      osc2 = actx.createOscillator(); osc2.type = 'sine'; osc2.frequency.value = 164.81;
      padGain1 = actx.createGain(); padGain1.gain.value = 0.025;
      padGain2 = actx.createGain(); padGain2.gain.value = 0.018;
      osc1.connect(padGain1); padGain1.connect(analyser);
      osc2.connect(padGain2); padGain2.connect(analyser);
      analyser.connect(actx.destination);
      osc1.start(); osc2.start();
    } catch (e) {}
  }
  function moodTone(tag) {
    if (!osc1) return;
    const f = MOOD_FREQ[tag] || MOOD_FREQ.idle;
    const t = actx.currentTime;
    osc1.frequency.linearRampToValueAtTime(f[0], t + 0.8);
    osc2.frequency.linearRampToValueAtTime(f[1], t + 0.8);
  }
  function duck(on) {
    if (!padGain1) return;
    const t1 = on ? 0.005 : 0.025, t2 = on ? 0.003 : 0.018;
    padGain1.gain.linearRampToValueAtTime(t1, actx.currentTime + 0.25);
    padGain2.gain.linearRampToValueAtTime(t2, actx.currentTime + 0.25);
  }
  function sampleAudio() {
    if (!analyser) return 0;
    analyser.getByteFrequencyData(freqData);
    let sum = 0;
    for (let i = 0; i < freqData.length; i++) sum += freqData[i];
    State.audioLevel = sum / (freqData.length * 255);
    // Beat-sync blink: sharp bass spike triggers blink within one frame
    const bass3 = (freqData[1] + freqData[2] + freqData[3]) / (3 * 255);
    if (bass3 > 0.75 && bass3 - State.prevBass > 0.2) Face.blinkAt = performance.now();
    State.prevBass = bass3;
    return State.audioLevel;
  }

  // TTS — server-side edge-tts via /chat/tts
  // fetch MP3 → decodeAudioData → AudioBufferSourceNode through the
  // existing analyser so particle reactivity works identically.
  const tts = { muted: false, queue: [], model: '', playing: false, currentSrc: null };
  const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;

  function unlockTTS() {
    if (actx && actx.state === 'suspended') actx.resume();
  }

  function enqueueSpeech(text) {
    if (tts.muted) return;
    const clean = text.replace(/```[\s\S]*?```/g, '').replace(/[*_`~]/g, '').trim();
    if (!clean) return;
    tts.queue.push(clean);
    // combo counter + neon bleed on each sentence burst
    State.comboCount++;
    State.comboDecay = 2800;
    State.comboY = Face.cy - Face.s * 0.5 - State.comboCount * 8;
    State.neonBleed = 1.0;
    ttsTick();
  }

  function ttsTick() {
    if (tts.muted || tts.playing) return;
    const text = tts.queue.shift();
    if (text) playServerTTS(text);
  }

  async function playServerTTS(text) {
    tts.playing = true;
    duck(true); State.mode = 'speaking';
    try {
      const body = new URLSearchParams({ text, voice: 'osman', style: 'auto' });
      const resp = await fetch('/chat/tts', { method: 'POST', body });
      if (!resp.ok) throw new Error(resp.status);
      const arrayBuf = await resp.arrayBuffer();
      if (!actx) initAudio();
      const audioBuf = await actx.decodeAudioData(arrayBuf);
      const src = actx.createBufferSource();
      src.buffer = audioBuf;
      src.connect(analyser);
      tts.currentSrc = src;
      const CHARS_PER_SEC = 13;
      let elapsed = 0;
      const ti = setInterval(() => { elapsed += 0.08; driveViseme(text, Math.floor(elapsed * CHARS_PER_SEC)); }, 80);
      src.onended = () => {
        clearInterval(ti);
        tts.playing = false; tts.currentSrc = null;
        duck(false); setMouth('neutral');
        if (State.mode === 'speaking') State.mode = 'idle';
        ttsTick();
      };
      src.start();
    } catch (_e) {
      tts.playing = false; tts.currentSrc = null;
      duck(false);
      if (State.mode === 'speaking') State.mode = 'idle';
      ttsTick();
    }
  }

  function ttsSkip() {
    if (tts.currentSrc) { try { tts.currentSrc.stop(); } catch (_e) {} tts.currentSrc = null; }
    tts.queue.length = 0; tts.playing = false;
    duck(false); setMouth('neutral');
  }

  function ttsToggleMute() {
    tts.muted = !tts.muted;
    if (tts.muted) ttsSkip();
    beep(tts.muted ? 220 : 880, 0.05);
    FX.errorFlash = tts.muted ? 1.2 : 0.5;
  }
  function driveViseme(text, idx) {
    const c = (text[idx] || '').toLowerCase();
    if ('aeiou'.indexOf(c) >= 0) setMouth(c.toUpperCase());
    else if ('mbpfwv'.indexOf(c) >= 0) setMouth('M');
    else if (c === ' ' || c === '.') setMouth('neutral');
    else setMouth('E');
  }
  function setMouth(shape) {
    if (Face.mouth === shape) return;
    Face.mouth = shape;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    let m = mouthArc(cx, cy + s * 0.92, s * 0.7, shape, 30);
    // teeth tick marks (mask signature)
    for (let i = 0; i < 7; i++) {
      const tx = cx - s * 0.32 + i * (s * 0.64 / 6);
      m.push({ x: tx, y: cy + s * 0.88, zone: 'mouth' });
      m.push({ x: tx, y: cy + s * 0.96, zone: 'mouth' });
    }
    Face.zones.mouth = m;
    // Update only mouth-zone particles — preserve hx2/hy2/hz2 for active mask transitions
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      if (p.zone !== 'mouth') continue;
      const a = m[i % m.length];
      p.hx1 = a.x + p.ox; p.hy1 = a.y + p.oy; p.hz1 = (a.z || 0) + p.oz;
      p.hx = p.hx1; p.hy = p.hy1; p.hz = p.hz1;
    }
  }

  // STT (long-press to talk)
  let recognition = null;
  if ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window) {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    recognition = new SR();
    recognition.continuous = false; recognition.interimResults = true;
    recognition.onresult = (e) => {
      let interim = '', final = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        (r.isFinal ? final += r[0].transcript : interim += r[0].transcript);
      }
      State.sttInterim = interim;
      if (final.trim()) { State.sttInterim = ''; State.sttActive = false; sendMessage(final.trim()); }
    };
    recognition.onend = () => { State.sttActive = false; State.sttInterim = ''; };
    recognition.onerror = () => { State.sttActive = false; };
  }
  function startSTT() {
    if (!recognition || State.sttActive) return;
    try { recognition.start(); State.sttActive = true; State.mode = 'listening'; Face.pupilTarget = 1.4; } catch (e) {}
  }
  function stopSTT() {
    if (!recognition || !State.sttActive) return;
    try { recognition.stop(); } catch (e) {}
    Face.pupilTarget = 1.0;
  }

  // SSE chat — raw text chunks, named events for state
  let evtSrc = null;
  async function sendMessage(text) {
    if (evtSrc) { try { evtSrc.close(); } catch (e) {} }
    ttsSkip();
    const token = new URLSearchParams(window.location.search).get('token') || '';

    // Enhance gate: fetch rewrite, show dim y/n confirm, resolve to chosen message.
    let finalText = text;
    let preEnhanced = false;
    try {
      const r = await fetch(`/chat/enhance?token=${encodeURIComponent(token)}&message=${encodeURIComponent(text)}`);
      const data = await r.json();
      if (data.changed && data.enhanced && data.enhanced !== text) {
        const chosen = await (window._chatConfirmEnhance?.(text, data.enhanced) ?? Promise.resolve(text));
        preEnhanced = chosen === data.enhanced;
        finalText = chosen;
      }
    } catch (_) {}

    State.mode = 'thinking';
    Face.dispersionTarget = 0.35;
    Face.browTarget = 0.4;
    const stateBlob = encodeURIComponent(`${State.mood}|${State.mode}|${((performance.now() - State.lastTouch)/1000)|0}|${palIdx}`);
    const url = `/chat/message?token=${encodeURIComponent(token)}&message=${encodeURIComponent(finalText)}&state=${stateBlob}${preEnhanced ? '&pre_enhanced=1' : ''}`;
    evtSrc = new EventSource(url);
    let pending = '';
    evtSrc.onmessage = (ev) => {
      const raw = ev.data || '';
      if (raw === '[DONE]') {
        if (pending.trim()) enqueueSpeech(pending.trim());
        pending = '';
        State.mode = 'idle'; Face.browTarget = 0; Face.dispersionTarget = 0;
        if (navigator.vibrate) navigator.vibrate([80]);
        try { evtSrc.close(); } catch (e) {}
        window._chatOnDone?.();
        return;
      }
      if (raw.startsWith('ERROR:')) { Face.coronaFlash = 1.0; State.mode = 'error'; fadePaletteTo(VERDICT_TINT.veto); triggerSweat(); triggerChibi(); window._chatOnError?.(); return; }
      const chunk = raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
      window._chatOnChunk?.(chunk);
      pending += chunk;
      Face.dispersionTarget = 0;
      let m;
      while ((m = pending.match(SENT_BREAK))) {
        const cut = m.index + m[0].length;
        const sent = pending.slice(0, cut).trim();
        pending = pending.slice(cut);
        if (sent) {
          enqueueSpeech(sent);
          Face.dispersionTarget = Math.min(0.06, Face.dispersionTarget + 0.04);
          setTimeout(() => { if (Face.dispersionTarget > 0) Face.dispersionTarget = Math.max(0, Face.dispersionTarget - 0.04); }, 250);
        }
      }
    };
    evtSrc.addEventListener('tool', (ev) => {
      try { JSON.parse(ev.data); datamosh(); Face.dispersionTarget = 0.2; triggerShockEyes(); } catch (e) {}
    });
    evtSrc.addEventListener('mood', (ev) => {
      const m = (ev.data || '').trim();
      if (!m) return;
      State.mood = m; moodTone(m);
      if (MOOD_PALETTE[m]) fadePaletteTo(MOOD_PALETTE[m]);
    });
    evtSrc.addEventListener('model', (ev) => {
      const m = (ev.data || '').trim();
      if (!m) return;
      tts.model = m; State.modelName = m.split('/').pop(); applyProviderTint(m);
    });
    evtSrc.addEventListener('verdict', (ev) => {
      const v = (ev.data || '').trim();
      fadePaletteTo(VERDICT_TINT[v] || timePalette());
      pulseEdge();
      if (v === 'pass') { triggerBlush(); exprRimshot(); beep(880, 0.06); State.mode = 'ack'; setTimeout(() => { if (State.mode === 'ack') State.mode = 'idle'; }, 2000); }
      if (v === 'veto') { triggerVein(); exprGuard(); beep(220, 0.10); }
    });
    evtSrc.addEventListener('confidence', (ev) => {
      const c = parseFloat(ev.data); if (isNaN(c)) return;
      State.confidence = c; Face.browTarget = 1 - c; Face.dispersionTarget = Math.max(0, (1 - c) * 0.4);
    });
    evtSrc.addEventListener('dmesg', (ev) => {
      try { window._chatOnDmesg?.(JSON.parse(ev.data)); } catch (_) {}
    });
    evtSrc.onerror = () => {
      beep(110, 0.18); FX.errorFlash = 2.0;
      State.mode = 'error'; triggerSweat();
      try { evtSrc.close(); } catch (e) {}
    };
  }

  // periodic state ping (closed-loop canvas → MASTER)
  setInterval(() => {
    if (document.hidden) return;
    const idleS = ((performance.now() - State.lastTouch) / 1000) | 0;
    const body = new URLSearchParams({
      mood: State.mood, mode: State.mode, idle: String(idleS),
      palette: String(palIdx), confidence: State.confidence.toFixed(2),
      tilt_x: State.tiltX.toFixed(2), tilt_y: State.tiltY.toFixed(2)
    });
    try { fetch('/canvas/state', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body, keepalive: true }); } catch (e) {}
  }, 8000);
  function applyProviderTint(model) {
    const m = (model || '').toLowerCase();
    const key = Object.keys(PROVIDER_TINT).find(k => m.includes(k));
    if (key) fadePaletteTo(PROVIDER_TINT[key]);
  }
  function pulseEdge() { Face.edgePulse = 1.0; }

  // Gesture detection
  const Gesture = {
    down: false, x0: 0, y0: 0, t0: 0, x1: 0, y1: 0, longTimer: null,
    pinchDist0: 0, rotA0: 0, lastTap: 0, twoPtr: false
  };
  function pointerStart(e) {
    State.lastTouch = performance.now();
    Gesture.down = true;
    const p = pointerXY(e);
    Gesture.x0 = p.x; Gesture.y0 = p.y; Gesture.x1 = p.x; Gesture.y1 = p.y; Gesture.t0 = performance.now();
    Gesture.longTimer = setTimeout(() => { if (Gesture.down && dist(Gesture.x0, Gesture.y0, Gesture.x1, Gesture.y1) < 12) startSTT(); }, 420);
    Face.gazeTarget = [(p.x - W * 0.5) / W, (p.y - H * 0.5) / H];
    rippleAt(p.x, p.y);
  }
  function rippleAt(x, y, amp = 1.0) {
    const R2 = Face.s * Face.s * 0.36;
    for (let i = 0; i < particles.length; i++) {
      const pp = particles[i];
      const dx = pp.x - x, dy = pp.y - y, d2 = dx*dx + dy*dy;
      if (d2 < R2 && d2 > 1) {
        const f = (1 - d2 / R2) * 3.5 * amp;
        const inv = 1 / Math.sqrt(d2);
        pp.vx += dx * inv * f;
        pp.vy += dy * inv * f;
      }
    }
    if (amp >= 1.0) setTimeout(() => rippleAt(x, y, 0.3), 80);
  }
  function curlAt(x, y, t) {
    const k = 0.012, k2 = 0.018, k3 = 0.007;
    _curl[0] = Math.sin(y*k + t*0.0007) - Math.cos(x*k2 - t*0.0011) + Math.sin(x*k3 + y*k3 + t*0.0005) * 0.4;
    _curl[1] = -Math.sin(x*k + t*0.0009) + Math.cos(y*k2 + t*0.0013) + Math.cos(y*k3 - x*k3 + t*0.0006) * 0.4;
    return _curl;
  }
  function pointerMove(e) {
    if (!Gesture.down) return;
    const p = pointerXY(e);
    const movedFar = dist(Gesture.x1, Gesture.y1, p.x, p.y);
    Gesture.x1 = p.x; Gesture.y1 = p.y;
    if (dist(Gesture.x0, Gesture.y0, p.x, p.y) > 14 && Gesture.longTimer) { clearTimeout(Gesture.longTimer); Gesture.longTimer = null; }
    Face.gazeTarget = [(p.x - W * 0.5) / W, (p.y - H * 0.5) / H];
    if (movedFar > 2) dragDisplace(p.x, p.y, movedFar);
    if (e.touches && e.touches.length === 2) handlePinch(e);
  }
  function dragDisplace(x, y, vel) {
    const R2 = Face.s * Face.s * 0.18;
    const k = Math.min(1.2, vel * 0.08);
    for (let i = 0; i < particles.length; i++) {
      const pp = particles[i];
      const dx = pp.x - x, dy = pp.y - y, d2 = dx*dx + dy*dy;
      if (d2 < R2 && d2 > 1) {
        const f = (1 - d2 / R2) * k;
        const inv = 1 / Math.sqrt(d2);
        pp.vx += dx * inv * f;
        pp.vy += dy * inv * f;
      }
    }
  }
  function pointerEnd(e) {
    if (!Gesture.down) return;
    Gesture.down = false;
    if (Gesture.longTimer) { clearTimeout(Gesture.longTimer); Gesture.longTimer = null; }
    if (State.sttActive) { stopSTT(); return; }
    const dx = Gesture.x1 - Gesture.x0, dy = Gesture.y1 - Gesture.y0;
    const d = Math.hypot(dx, dy), dt = performance.now() - Gesture.t0;
    if (d < 14 && dt < 240) {
      const now = performance.now();
      if (now - Gesture.lastTap < 320) { ttsToggleMute(); Gesture.lastTap = 0; return; }
      Gesture.lastTap = now;
      if (tts.playing || tts.queue.length) ttsSkip();
      return;
    }
    if (d > 60 && dt < 600) handleSwipe(dx, dy);
  }
  function pointerXY(e) {
    if (e.touches && e.touches[0]) return { x: e.touches[0].clientX, y: e.touches[0].clientY };
    return { x: e.clientX, y: e.clientY };
  }
  function dist(x1,y1,x2,y2) { return Math.hypot(x2-x1, y2-y1); }
  function handleSwipe(dx, dy) {
    const ax = Math.abs(dx), ay = Math.abs(dy);
    if (ay > ax) {
      if (dy < 0) { sendSlash('/undo');    nod(-1); }
      else        { sendSlash('/redo');    nod(+1); }
    } else {
      if (dx < 0) { sendSlash('/focus');   shake(-1); }
      else        { sendSlash('/history'); shake(+1); }
    }
  }
  function handlePinch(e) {
    if (e.touches.length !== 2) return;
    const t0 = e.touches[0], t1 = e.touches[1];
    const d = Math.hypot(t1.clientX - t0.clientX, t1.clientY - t0.clientY);
    if (!Gesture.twoPtr) { Gesture.twoPtr = true; Gesture.pinchDist0 = d; Gesture.rotA0 = Math.atan2(t1.clientY - t0.clientY, t1.clientX - t0.clientX); return; }
    const ratio = d / Gesture.pinchDist0;
    if (ratio < 0.55) { State.mode = 'sleep'; Face.dispersionTarget = -1.0; }
    else if (ratio > 1.6) { State.mode = 'idle'; Face.dispersionTarget = 0; }
    const a = Math.atan2(t1.clientY - t0.clientY, t1.clientX - t0.clientX);
    const da = a - Gesture.rotA0;
    if (Math.abs(da) > 0.4) cyclePalette(da > 0 ? 1 : -1);
  }
  function nod(dir) { Face.pitchTarget = dir * 0.28; setTimeout(() => Face.pitchTarget = 0, 380); }
  function shake(dir) { Face.yawTarget = dir * 0.32; setTimeout(() => Face.yawTarget = -Face.yawTarget, 180); setTimeout(() => Face.yawTarget = 0, 380); }
  function sendSlash(cmd) { try { fetch(`/chat/message?message=${encodeURIComponent(cmd)}`, { method: 'GET' }); } catch (e) {} }

  // P-key palette cycle (mono → provider tints)
  const CYCLE_PALETTES = [timePalette(),
    PROVIDER_TINT.claude, PROVIDER_TINT.deepseek, PROVIDER_TINT.gemini, PROVIDER_TINT.gpt];
  let palIdx = 0;
  function cyclePalette(dir) {
    palIdx = (palIdx + dir + CYCLE_PALETTES.length) % CYCLE_PALETTES.length;
    fadePaletteTo(CYCLE_PALETTES[palIdx], 800);
  }

  // shake to reset
  let lastShake = 0, lastAccel = [0,0,0];
  if (window.DeviceMotionEvent) {
    window.addEventListener('devicemotion', (e) => {
      const a = e.accelerationIncludingGravity || e.acceleration;
      if (!a) return;
      const dx = a.x - lastAccel[0], dy = a.y - lastAccel[1], dz = a.z - lastAccel[2];
      const m = Math.hypot(dx, dy, dz);
      lastAccel = [a.x, a.y, a.z];
      const now = performance.now();
      if (m > 24 && now - lastShake > 800) { lastShake = now; vortex(); ttsSkip(); State.mode = 'idle'; Face.dispersionTarget = 0; }
    });
  }
  function vortex() { Face.vortex = 1.0; Face.dispersionTarget = 0.6; setTimeout(() => Face.dispersionTarget = 0, 700); }

  // tilt — iOS requires explicit permission since Safari 13
  function bindDeviceOrientation() {
    window.addEventListener('deviceorientation', (e) => {
      if (e.gamma != null) State.tiltX = e.gamma / 90;
      if (e.beta  != null) State.tiltY = (e.beta - 45) / 90;
    });
  }
  async function requestMotionPermission() {
    if (typeof DeviceOrientationEvent !== 'undefined' &&
        typeof DeviceOrientationEvent.requestPermission === 'function') {
      try { const r = await DeviceOrientationEvent.requestPermission(); if (r === 'granted') bindDeviceOrientation(); }
      catch (_e) {}
    } else if (window.DeviceOrientationEvent) {
      bindDeviceOrientation();
    }
  }

  // VAD — energy-based AudioWorklet, no ONNX dependency
  async function initVAD() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
      if (!actx) initAudio();
      await actx.audioWorklet.addModule('/vad-processor.js');
      const src = actx.createMediaStreamSource(stream);
      const node = new AudioWorkletNode(actx, 'vad-processor');
      src.connect(node);
      node.port.onmessage = ({ data }) => {
        if (data.type === 'speech_start') { State.mode = 'listening'; Face.browTarget = 0.3; }
        if (data.type === 'speech_end')   { State.mode = 'idle';      Face.browTarget = 0; }
      };
    } catch (_e) {}
  }

  // Screen Wake Lock — keep display on during sessions
  let wakeLock = null;
  async function acquireWakeLock() {
    if (!('wakeLock' in navigator)) return;
    async function _request() {
      try {
        wakeLock = await navigator.wakeLock.request('screen');
        wakeLock.addEventListener('release', () => { wakeLock = null; });
      } catch (_e) {}
    }
    await _request();
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && !wakeLock) _request();
    });
  }

  // Square-wave beep — 8-bit state feedback
  function beep(freq = 440, dur = 0.07) {
    if (!actx) return;
    const osc = actx.createOscillator(), g = actx.createGain();
    osc.type = 'square'; osc.frequency.value = freq;
    g.gain.setValueAtTime(0.10, actx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001, actx.currentTime + dur);
    osc.connect(g); g.connect(actx.destination);
    osc.start(); osc.stop(actx.currentTime + dur);
  }

  // Boids neighbor flock (light, only when idle long)
  function flock() {
    const NP = particles.length;
    const strength = 0.010;
    for (let i = 0; i < NP; i += 6) {
      const p = particles[i], q = particles[(i + 137) % NP];
      // Alignment: match neighbor velocity
      p.vx += (q.vx - p.vx) * strength;
      p.vy += (q.vy - p.vy) * strength;
      // Separation: push if overlapping
      const rdx = p.x - q.x, rdy = p.y - q.y, d2 = rdx*rdx + rdy*rdy;
      if (d2 < 9 && d2 > 0.01) { const f = 0.04 / d2; p.vx += rdx * f; p.vy += rdy * f; }
    }
  }

  // Aesthetic effects (Warp / Low End Theory / Flamagra)
  const FX = {
    cutBlack: 0, // 1-frame canvas clear on transient
    datamosh: 0, datamoshFrames: 0, // velocity-hold smear on tool event
    // Manga manpu (漫符)
    sweat: 0, // embarrassment/error — teardrop from temple
    vein: 0, // anger/reject — pulsing cross on forehead
    blush: 0, // warmth/ack/pass — rose ovals on cheeks
    noseBubbleR: 0, // sleep — growing circle from nose tip, resets on pop
    speedLines: 0, // thinking — radial streaks from face edge
    tears: 0, // sleep — cascading streams from eye centers
    shockEyes: 0, // surprise/tool — rings expand, pupils contract
    chibi: 0, // error — brief vertical squash of whole face
    errorFlash: 0 // XOR canvas flash — error / mute toggle
  };
  function datamosh() { FX.datamosh = 1.0; FX.datamoshFrames = 6; }
  function cutBlack() { FX.cutBlack = 1.0; }
  function triggerSweat()   { FX.sweat     = 1.0; }
  function triggerVein()    { FX.vein      = 1.0; }
  function triggerBlush()   { FX.blush     = 1.0; }
  function triggerShockEyes() { FX.shockEyes = 1.0; }
  function triggerChibi()   { FX.chibi     = 1.0; }

  // Combat and performance expression vocabulary
  // MMA guard: brow furrow + gaze lock (Muay Thai, Silat, UFC awareness posture)
  function exprGuard() {
    Face.browTarget = 0.88; Face.gazeTarget = [0, 0];
    setTimeout(() => { Face.browTarget = 0; }, 2400);
  }
  // Pre-fight stare: pupils contract, blink suppressed 3s
  function exprPreStare() {
    Face.pupilTarget = 0.52; Face.blinkPhase = -3.0;
    setTimeout(() => { Face.pupilTarget = 1.0; }, 3000);
  }
  // Muay Thai ram muay / Silat bunga: serene brow lift + slow head sway
  function exprRamMuay() {
    Face.browTarget = -0.58; Face.yawTarget = (Math.random() > 0.5 ? 1 : -1) * 0.09;
    setTimeout(() => { Face.browTarget = 0; Face.yawTarget = 0; }, 2800);
  }
  // Silat aura: dreamy gaze drift + breath-pitch sway
  function exprSilat() {
    Face.gazeTarget = [(Math.random() - 0.5) * 0.32, (Math.random() - 0.5) * 0.18];
    Face.pitchTarget = (Math.random() - 0.5) * 0.11;
    setTimeout(() => { Face.gazeTarget = [0, 0]; Face.pitchTarget = 0; }, 3600);
  }
  // Standup comedy punchline: held beat → blush + chibi pop
  function exprPunchline() {
    setTimeout(() => { triggerBlush(); triggerChibi(); }, 380);
  }
  // Rimshot: high brow flash + shock eyes
  function exprRimshot() {
    Face.browTarget = -0.92; triggerShockEyes();
    setTimeout(() => { Face.browTarget = 0; }, 1100);
  }
  // Slam/spoken-word emotional peak: blush + speed lines
  function exprSpokenWord() {
    triggerBlush(); FX.speedLines = Math.min(1, FX.speedLines + 0.72);
  }
  // Curious head-tilt: slight yaw + brow lift (universal)
  function exprCurious() {
    Face.yawTarget = (Math.random() > 0.5 ? 1 : -1) * 0.13;
    Face.browTarget = -0.42;
    setTimeout(() => { Face.yawTarget = 0; Face.browTarget = 0; }, 2000);
  }

  const Expr = { lastFire: 0, recent: [] };
  function tickPersonalityExpressions(now) {
    const mean = { speaking: 6000, thinking: 9000, idle: 22000, listening: 7000, error: 4000 }[State.mode] || 14000;
    if (now - Expr.lastFire < mean * (0.6 + Math.random() * 0.8)) return;
    Expr.lastFire = now;
    const pools = {
      thinking:  [exprGuard, exprPreStare, exprSilat, exprCurious, exprGuard],
      speaking:  [exprRimshot, exprPunchline, exprRamMuay, exprSpokenWord, exprCurious],
      idle:      [exprSilat, exprRamMuay, exprCurious],
      listening: [exprGuard, exprCurious, exprPreStare],
      error:     [exprGuard, exprPreStare]
    };
    const pool = pools[State.mode] || pools.idle;
    // Fatigue: deprioritise expressions fired in the last 4 turns
    const fresh = pool.filter(fn => Expr.recent.filter(f => f === fn).length < 2);
    const chosen = (fresh.length ? fresh : pool)[Math.floor(Math.random() * (fresh.length || pool.length))];
    chosen();
    Expr.recent.push(chosen);
    if (Expr.recent.length > 4) Expr.recent.shift();
  }

  function tickFX(dt) {
    if (analyser && freqData) {
      const bass = (freqData[1] + freqData[2] + freqData[3]) / (3 * 255);
      if (bass > 0.85) cutBlack();
    }
    FX.cutBlack *= 0.4;
    if (FX.datamoshFrames > 0) FX.datamoshFrames--; else FX.datamosh *= 0.85;
    // Manga manpu ticks
    State.neonBleed *= 0.88;
    // combo decay
    if (State.comboDecay > 0) { State.comboDecay -= dt; if (State.comboDecay <= 0) { State.comboCount = 0; State.comboDecay = 0; } }
    // CONTINUE? countdown during sleep — reaches 0 then wakes
    if (State.mode === 'sleep') {
      if (State.continueCount < 0) { State.continueCount = 9; State.continueTimer = performance.now(); }
      else if (performance.now() - State.continueTimer > 1000) {
        State.continueTimer = performance.now();
        State.continueCount--;
        if (State.continueCount < 0) { State.mode = 'idle'; Face.dispersionTarget = 0; State.continueCount = -1; }
      }
    } else { State.continueCount = -1; }
    FX.sweat      *= 0.983;
    FX.vein        = State.mode === 'error' ? Math.min(1, FX.vein + 0.07) : FX.vein * 0.94;
    FX.blush       = State.mode === 'ack'   ? Math.min(1, FX.blush + 0.06) : FX.blush * 0.97;
    FX.tears       = State.mode === 'sleep' ? Math.min(1, FX.tears + 0.04) : FX.tears * 0.91;
    FX.speedLines  = State.mode === 'thinking' ? Math.min(1, FX.speedLines + 0.06) : FX.speedLines * 0.87;
    FX.shockEyes  *= 0.91;
    FX.chibi      *= 0.86;
    FX.errorFlash *= 0.72;
    // nose bubble: grows during extended idle/sleep, pops and resets
    const longIdle = (performance.now() - State.lastTouch) > 55000;
    if ((State.mode === 'sleep' || longIdle) && State.mode !== 'error') {
      FX.noseBubbleR += dt * 0.012;
      if (FX.noseBubbleR > Face.s * 0.28) FX.noseBubbleR = 0;
    } else {
      FX.noseBubbleR *= 0.88;
    }
  }
  function drawCutBlack() {
    if (FX.cutBlack < 0.5) return;
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, W, H);
  }
  function drawCatalogGhost() {
    ctx.font = '8px "Silkscreen",ui-monospace,monospace';
    ctx.fillStyle = 'rgba(255,255,255,0.08)';
    if (State.modelName) ctx.fillText(State.modelName, 8, H - 48);
    ctx.fillText(`${State.session.toString(36).toUpperCase()}`, 8, H - 40);
    // Idle marquee — DMESG phrases scroll right→left across top
    if (State.mode === 'idle' && lpxW) {
      const txt = DMESG_PHRASES.join('  //  ');
      ctx.fillStyle = 'rgba(255,255,255,0.12)';
      ctx.fillText(txt, _marqueeX, 14);
      _marqueeX -= 1;
      if (_marqueeX < -(ctx.measureText(txt).width)) _marqueeX = W;
    }
  }

  // Whisper voice (low-volume asides)
  function whisper(text) {
    if (tts.muted || !text) return;
    tts.queue.push(text); ttsTick();
  }
  // Boot phrases — whispered at startup
  const DMESG_PHRASES = [
    'Master booting', 'Soul loaded', 'Constitution online', 'Tools registered',
    'Pipeline armed', 'Council convened', 'Ready'
  ];

  // Render loop
  let lastT = performance.now(), _frameSkip = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(50, now - lastT); lastT = now;
    if (State.mode === 'sleep' && dt < 20 && (++_frameSkip % 2 === 0)) return;
    if (_fps30 && (++_bfSkip & 1)) return;
    tickPalette(now);

    // Smooth state lerps — dt-scaled so 30 fps feels identical to 60 fps.
    Face.yaw     += (Face.yawTarget - Face.yaw) * _dtL(0.12, dt);
    Face.pitch   += (Face.pitchTarget - Face.pitch) * _dtL(0.12, dt);
    Face.pupil   += (Face.pupilTarget - Face.pupil) * _dtL(0.10, dt);
    Face.brow    += (Face.browTarget - Face.brow) * _dtL(0.08, dt);
    Face.dispersion += (Face.dispersionTarget - Face.dispersion) * _dtL(0.06, dt);
    // Saccadic profile: ballistic when far (>0.12), slow settle when close.
    const gazeDist = Math.hypot(Face.gazeTarget[0] - Face.gaze[0], Face.gazeTarget[1] - Face.gaze[1]);
    const gazeRate = gazeDist > 0.12 ? 0.30 : 0.08;
    const gazeK = _dtL(gazeRate, dt);
    Face.gaze[0] += (Face.gazeTarget[0] - Face.gaze[0]) * gazeK;
    Face.gaze[1] += (Face.gazeTarget[1] - Face.gaze[1]) * gazeK;
    tickMicrosaccades(dt);
    Face.breath  += dt * 0.001;
    Face.heartRate = 1.0 + (State.mode === 'thinking' ? 0.6 : 0) + (State.mode === 'error' ? 1.2 : 0);
    Face.bodyScale = 1.0 + Math.sin(Face.breath * Math.PI * 2 * Face.heartRate) * 0.012;
    Face.dispersionTarget += Math.sin(Face.breath * Math.PI * 2 * Face.heartRate) * 0.012;
    Face.coronaFlash    *= _dtN(0.94, dt);
    Face.edgePulse      *= _dtN(0.96, dt);
    Face.vortex         *= _dtN(0.93, dt);
    Face.codespaceRatio += (Face.codespaceTarget - Face.codespaceRatio) * _dtL(0.03, dt);

    // blink scheduler — cosine envelope, low confidence blinks more often
    Face.blinkPhase += dt * 0.001;
    const baseInt = State.mode === 'thinking' ? 0.9 : (State.mode === 'idle' ? 5.0 : 3.0);
    const interval = baseInt * (0.4 + State.confidence * 0.6);
    if (Face.blinkPhase > interval) { Face.blinkAt = now; Face.blinkPhase = 0; }
    const blinkAge = now - Face.blinkAt;
    Face.blink = blinkAge < 140 ? Math.sin(blinkAge / 140 * Math.PI) : 0;

    const idleMs = now - State.lastTouch;

    sampleAudio();
    if (State.mode === 'idle') flock();
    tickFX(dt);
    tickPersonalityExpressions(now);
    maybeSwitchMask(now, dt);
    maybeLookAway(now);
    tickParticles(dt, now);

    // bg — clear main canvas; particle layer has its own phosphor persistence
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, W, H);

    drawSpeedLines();
    drawParticles(now);

    // Mask wipe: column sweep, alternating direction each transition
    if (maskTransitioning) {
      const leftward = maskNextIdx % 2 === 0;
      const wipeX = leftward ? ((1 - maskPhase) * W) | 0 : (maskPhase * W) | 0;
      ctx.fillStyle = '#000';
      if (leftward) ctx.fillRect(wipeX, 0, W - wipeX, H);
      else ctx.fillRect(0, 0, wipeX, H);
    }
    drawEdgePulse();
    drawThinkingOrbit(now);
    drawCorona();
    drawVortex();
    drawCatalogGhost();
    drawCutBlack();
    drawBlush();
    drawTears();
    drawSweat();
    drawVein();
    drawNoseBubble();
    drawOscilloscope();
    drawCombo();
    drawContinue();
    drawHUD();
  }

  function tickParticles(dt, now) {
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const yaw = Face.yaw + State.tiltX * 0.45 + Math.sin(now * 0.00022) * 0.14;
    const pitch = Face.pitch + State.tiltY * 0.30 + Math.sin(now * 0.00015) * 0.08;
    const roll = Math.sin(now * 0.00011) * 0.022;
    const cosY = Math.cos(yaw), sinY = Math.sin(yaw);
    const cosP = Math.cos(pitch), sinP = Math.sin(pitch);
    const disp = Face.dispersion;
    const scale = Face.bodyScale;
    const blinkClose = Face.blink > 0.3 ? 1 : 0;
    // orbicularis oculi: smile squints the lower lid, narrowing the eye opening
    const squint = Face.mouth === 'smile' ? 0.22 : 0;
    const breathPhase = Math.sin(Face.breath * Math.PI * 2 * Face.heartRate);
    const gazeX = (Face.gaze[0] + gazeJitter[0]) * s * 0.09;
    const gazeY = (Face.gaze[1] + gazeJitter[1]) * s * 0.06;
    const pupilK = Face.pupil;
    const browDrop = Face.brow * s * 0.06;
    const audioPunch = State.audioLevel;
    const NP = particles.length;
    const doRepulse = ((++_repulseFrame & 0xFFFF) % 3 === 0);

    for (let i = 0; i < NP; i++) {
      const p = particles[i];

      // Blink skip — eyes fully closed, skip spring entirely
      if (blinkClose === 1 && (p.zone === 'eyeL' || p.zone === 'eyeR' || p.zone === 'pupilL' || p.zone === 'pupilR')) {
        p.vx *= 0.72; p.vy *= 0.72;
        p.px = p.x; p.py = p.y; p.x += p.vx; p.y += p.vy;
        continue;
      }

      let tx = p.hx, ty = p.hy, tz = p.hz;
      if (p.zone === 'pupilL' || p.zone === 'pupilR') {
        const ex = (p.zone === 'pupilL') ? cx - s * 0.32 : cx + s * 0.32;
        const ey = cy - s * 0.10;
        tx = ex + (p.hx - ex) * pupilK + gazeX;
        ty = ey + (p.hy - ey) * pupilK + gazeY;
      }
      if (p.zone === 'eyeL' || p.zone === 'eyeR') {
        const ey = cy - s * 0.10;
        ty = ey + (p.hy - ey) * (1 - blinkClose * 0.95 - squint * 0.28);
      }
      if (p.zone === 'browL' || p.zone === 'browR') ty = p.hy + browDrop;
      if (p.zone === 'scarL' || p.zone === 'scarR') {
        tx = p.hx + (Math.random() - 0.5) * audioPunch * s * 0.06;
      }
      if (p.zone === 'noseFlare') {
        ty = p.hy + breathPhase * s * 0.014; // nostril flares on inhale
        tx = p.hx + breathPhase * (p.hx > cx ? 1 : -1) * s * 0.008;
      }
      if (p.zone === 'tasselL' || p.zone === 'tasselR') {
        tx = p.hx + State.tiltX * s * 0.08;
        ty = p.hy + Math.sin(now * 0.002 + p.hy * 0.05) * s * 0.02;
      }
      if (p.zone === 'crown') {
        tx = p.hx + Math.sin(now * 0.001 + p.hx * 0.02) * s * 0.02 * (1 + Face.dispersion);
        ty = p.hy + breathPhase * (p.hx - cx) * 0.008;
      }
      // Manga: shock eyes — ring expands, pupils contract (before 3D so it respects rotation)
      if (FX.shockEyes > 0.01) {
        if (p.zone === 'eyeL' || p.zone === 'eyeR') {
          const ex = (p.zone === 'eyeL') ? cx - s * 0.32 : cx + s * 0.32;
          const ey2 = cy - s * 0.10;
          tx = ex + (tx - ex) * (1 + FX.shockEyes * 0.50);
          ty = ey2 + (ty - ey2) * (1 + FX.shockEyes * 0.50);
        } else if (p.zone === 'pupilL' || p.zone === 'pupilR') {
          const ex = (p.zone === 'pupilL') ? cx - s * 0.32 : cx + s * 0.32;
          const ey2 = cy - s * 0.10;
          tx = ex + (tx - ex) * (1 - FX.shockEyes * 0.70);
          ty = ey2 + (ty - ey2) * (1 - FX.shockEyes * 0.70);
        }
      }
      // Manga: chibi collapse — brief vertical squash, slight horizontal spread
      if (FX.chibi > 0.01) {
        ty = cy + (ty - cy) * (1 - FX.chibi * 0.52);
        tx = cx + (tx - cx) * (1 + FX.chibi * 0.18);
      }
      // 3D transform around centroid: scale → roll → yaw → pitch
      let dx = (tx - cx) * scale, dy = (ty - cy) * scale, dz = tz * scale;
      const cosRoll = Math.cos(roll), sinRoll = Math.sin(roll);
      const xR = dx * cosRoll - dy * sinRoll;
      const yR = dx * sinRoll + dy * cosRoll;
      dx = xR; dy = yR;
      const xY = dx * cosY + dz * sinY;
      const zY = -dx * sinY + dz * cosY;
      dx = xY; dz = zY;
      const yP = dy * cosP - dz * sinP;
      dy = yP;
      p.sz = dz; // eye-space z — drives depth-layered rendering
      const _fov = s * 1.8;
      const _ps = _fov / Math.max(1, _fov - dz);
      tx = cx + dx * _ps;
      ty = cy + dy * _ps;
      if (disp > 0) {
        const [cu, cv] = curlAt(p.x, p.y, now);
        tx += cu * s * disp * 0.08;
        ty += cv * s * disp * 0.05;
        // Vorticity confinement — reuse cached curl; avoid double curlAt call
        if (disp > 0.1) { p.vx += cu * 0.15 * disp; p.vy += cv * 0.10 * disp; }
      } else if (disp < 0) {
        const k = -disp;
        tx = cx * k + tx * (1 - k);
        ty = cy * k + ty * (1 - k);
      }
      if (Face.vortex > 0.01) {
        const vdx = p.x - cx, vdy = p.y - cy;
        const va = Math.atan2(vdy, vdx) + Face.vortex * 0.25;
        const vr = Math.hypot(vdx, vdy) * (1 + Face.vortex * 0.02);
        tx = cx + Math.cos(va) * vr;
        ty = cy + Math.sin(va) * vr;
      }
      // Architecture #15: codebase topology — disperse face into orbital ring.
      if (Face.codespaceRatio > 0.01) {
        const phi = (i / NP) * Math.PI * 2;
        const orbitR = Math.min(W, H) * 0.38;
        const ox = cx + Math.cos(phi) * orbitR;
        const oy = cy + Math.sin(phi) * orbitR * 0.55;
        tx += (ox - tx) * Face.codespaceRatio;
        ty += (oy - ty) * Face.codespaceRatio;
      }
      if (State.mode === 'sleep') {
        p.vx += (Math.random() - 0.5) * 0.03;
        p.vy += (Math.random() - 0.5) * 0.02;
        p.vx += (tx - p.x) * 0.003;
        p.vy += (ty - p.y) * 0.003;
      }
      // Velocity early exit — particle at rest and on target
      const v2 = p.vx*p.vx + p.vy*p.vy;
      const d2h = (tx - p.x)*(tx - p.x) + (ty - p.y)*(ty - p.y);
      if (v2 < 0.0004 && d2h < 0.25) { p.px = p.x; p.py = p.y; continue; }

      // Datamosh: freeze spring while frames remain — particles coast on current velocity
      if (FX.datamoshFrames > 0) {
        p.vx *= 0.97; p.vy *= 0.97;
        p.px = p.x; p.py = p.y; p.x += p.vx; p.y += p.vy;
        continue;
      }

      // Variable spring stiffness by zone; mass-scaled acceleration
      const k = ZONE_K[p.zone] || 0.08;
      const ax = (tx - p.x) * k / p.mass;
      const ay = (ty - p.y) * k / p.mass;
      p.vx += ax; p.vy += ay;
      // Underdamped far, overdamped near target — smooth ramp avoids visible discontinuity
      // at the 0.72→0.91 threshold as a particle crosses d2h = 4.
      const dampT = Math.min(1, d2h * 0.25);
      const damp = 0.72 + 0.19 * (dampT * dampT * (3 - 2 * dampT));
      p.vx *= damp; p.vy *= damp;
      // Lorenz attractor — advance per-particle butterfly orbit, blend into velocity
      if (State.lorenzMode) {
        const ldt = dt * 0.0004;
        const sigma = 10, rho = 28, beta = 2.667;
        const dlx = sigma * (p.ly - p.lx) * ldt;
        const dly = (p.lx * (rho - p.lz) - p.ly) * ldt;
        const dlz = (p.lx * p.ly - beta * p.lz) * ldt;
        p.lx += dlx; p.ly += dly; p.lz += dlz;
        // Map Lorenz X/Y into particle velocity nudge (scaled to face size)
        p.vx += p.lx * s * 4e-6;
        p.vy += p.ly * s * 4e-6;
      }
      // Velocity ceiling
      const vv = p.vx*p.vx + p.vy*p.vy;
      if (vv > 1.96) { const kv = 1.4 / Math.sqrt(vv); p.vx *= kv; p.vy *= kv; }
      // Sub-pixel repulsion — amortized every 3rd frame
      if (doRepulse) for (let kk = 0; kk < 3; kk++) {
        const j = (i + 137 + kk * 181) % NP;
        const q = particles[j];
        const rdx = p.x - q.x, rdy = p.y - q.y;
        const d2 = rdx*rdx + rdy*rdy;
        if (d2 < 2.25 && d2 > 0.01) { const f = 0.05 / d2; p.vx += rdx * f; p.vy += rdy * f; }
      }
      p.px = p.x; p.py = p.y;
      p.x += p.vx; p.y += p.vy;
    }
  }

  function drawParticles(now) {
    if (!lpxW || !lpxH) return;

    // Reallocate float + zone buffers on first call or after resize
    const sz = lpxW * lpxH;
    if (!fbuf || fbufSize !== sz) { fbuf = new Float32Array(sz); ebuf = new Float32Array(sz); fbufSize = sz; zbuf = new Uint8Array(sz); }
    else ebuf.fill(0);

    // Phosphor decay — persistent frame energy with hard floor drain to black
    for (let j = 0; j < sz; j++) fbuf[j] = Math.max(0, fbuf[j] * 0.80 - 0.004);

    // Shading constants — key light in world space
    const LX = -0.30, LY = -0.50, LZ = 0.81;
    const HX = -0.155, HY = -0.258, HZ = 0.953;
    const A2 = 0.7225, B2 = 2.1025, C2 = 0.1764;
    const s = Face.s, fcx = Face.cx, fcy = Face.cy;
    // Current yaw/pitch for rotating normals into world space
    const _yaw = Face.yaw + State.tiltX * 0.45 + Math.sin(now * 0.00022) * 0.14;
    const _pit = Face.pitch + State.tiltY * 0.30;
    const _cosY = Math.cos(_yaw), _sinY = Math.sin(_yaw);
    const _cosP = Math.cos(_pit), _sinP = Math.sin(_pit);
    // DoF focal plane at eye/bridge plane; wide sigma keeps nose+outline visible
    const focalZ = s * 0.32;
    const sigma2 = (s * 0.60) * (s * 0.60) * 2;

    // Accumulate particle contributions — glyph stamp per zone
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const px = (p.x * 0.5) | 0, py = (p.y * 0.5) | 0;
      if (px < 0 || px >= lpxW || py < 0 || py >= lpxH) continue;
      const sz_ = p.sz || 0;
      // Soft z-fade — particles behind the head dim over [-0.40 s, -0.20 s] instead of popping.
      const _zFar = -s * 0.40, _zNear = -s * 0.20;
      if (sz_ < _zFar) continue;
      const zFade = sz_ < _zNear ? (sz_ - _zFar) / (_zNear - _zFar) : 1;

      // Spheroid normal — computed from un-displaced base, not displaced hz
      const mx = (p.hx - fcx) / s, my = (p.hy - fcy) / s;
      const mxn = mx / 0.85, myn = my / 1.45;
      const mzBase = 0.42 * Math.sqrt(Math.max(0, 1 - mxn*mxn - myn*myn));
      const nx = mx / A2, ny = my / B2, nz = mzBase / C2;
      const nlen = Math.sqrt(nx*nx + ny*ny + nz*nz) || 1;
      let nnx = nx/nlen, nny = ny/nlen, nnz = nz/nlen;
      // Rotate normal by yaw then pitch into world space so shading follows head turn
      const nx2 = nnx * _cosY + nnz * _sinY;
      const nz2 = -nnx * _sinY + nnz * _cosY;
      nnx = nx2; nnz = nz2;
      const ny2 = nny * _cosP - nnz * _sinP;
      nny = ny2;

      // Lambert diffuse + ambient
      const NdotL = Math.max(0, LX*nnx + LY*nny + LZ*nnz);
      const shade  = 0.15 + 0.85 * NdotL;

      // Gaussian DoF — focal plane at eye/bridge
      const dz = sz_ - focalZ;
      const focus = Math.exp(-(dz * dz) / sigma2);
      let bright = (2 + 14 * focus) * shade;

      const zone = p.zone;

      // Blinn-Phong specular — nose/brow ceramic; cornea; wet lips
      if (zone === 'noseRidge' || zone === 'noseFlare' || zone === 'browL' || zone === 'browR') {
        const NdotH = Math.max(0, HX*nnx + HY*nny + HZ*nnz);
        const h2 = NdotH*NdotH, h4 = h2*h2, h8 = h4*h4, h16 = h8*h8;
        bright += h16 * h8 * h4 * 10; // h^28
      }
      if (zone === 'pupilL' || zone === 'pupilR') {
        const NdotH = Math.max(0, HX*nnx + HY*nny + HZ*nnz);
        const h2 = NdotH*NdotH, h4 = h2*h2, h8 = h4*h4;
        bright += h8 * h4 * h2 * 8; // h^14
      }
      if (zone === 'mouth') {
        const NdotH = Math.max(0, HX*nnx + HY*nny + HZ*nnz);
        const h2 = NdotH*NdotH, h4 = h2*h2;
        bright += h4 * h2 * 6; // h^6
      }

      // Rim lighting — silhouette halo
      if (zone === 'outlineL' || zone === 'outlineR') {
        const NdotV = Math.abs(nnz);
        bright += (1 - NdotV) * (1 - NdotV) * 9;
      }

      const val = Math.min(bright, 24) / 24 * zFade; // raised ceiling for specular headroom

      // Zone-specific glyph stamp — clamped add prevents specular blowout
      const zoneCol = ZX_ZONE_IDX[zone] || 0;
      const stamp = ZONE_STAMP[zone] || _STAMP_DEFAULT;
      for (let k = 0; k < stamp.length; k++) {
        const gx = px + stamp[k][0], gy = py + stamp[k][1];
        if (gx >= 0 && gx < lpxW && gy >= 0 && gy < lpxH) {
          const idx = gy * lpxW + gx;
          fbuf[idx] = Math.min(1, fbuf[idx] + val);
          zbuf[idx] = zoneCol;
        }
      }
    }

    const imgd = lpxCtx.getImageData(0, 0, lpxW, lpxH);
    const buf  = new Uint32Array(imgd.data.buffer);
    buf.fill(0xFF000000);
    if (pixelPal === 6) {
      // Bayer ordered dithering — threshold matrix, no error propagation, no temporal crawl
      for (let y = 0; y < lpxH; y++) {
        for (let x = 0; x < lpxW; x++) {
          const idx = y * lpxW + x;
          if (fbuf[idx] > BAYER4[(y & 3) * 4 + (x & 3)]) buf[idx] = 0xFFFFFFFF;
        }
      }
    } else {
      // Atkinson dithering — errors go to ebuf only; fbuf (phosphor) never touched
      for (let y = 0; y < lpxH; y++) {
        for (let x = 0; x < lpxW; x++) {
          const idx = y * lpxW + x;
          const v   = Math.min(1, Math.max(0, fbuf[idx] + ebuf[idx]));
          const out = v >= 0.5 ? 1 : 0;
          if (out) buf[idx] = pixelPal === 5 ? (ZX_PALETTE[zbuf[idx]] || 0xFFFFFFFF) : 0xFFFFFFFF;
          const err = (v - out) * 0.125;
          if (err === 0) continue;
          if (x+1 < lpxW) ebuf[idx+1]       += err;
          if (x+2 < lpxW) ebuf[idx+2]       += err;
          if (y+1 < lpxH) {
            if (x > 0)    ebuf[idx+lpxW-1]  += err;
                          ebuf[idx+lpxW]    += err;
            if (x+1<lpxW) ebuf[idx+lpxW+1] += err;
          }
          if (y+2 < lpxH) ebuf[idx+lpxW*2] += err;
        }
      }
    }

    // True ZX 8×8 attribute blocks — dominant zone per 8×8 cell overwrites all pixels in that cell
    if (pixelPal === 5) {
      const BLK = 8, NZ = _zxVotes.length;
      for (let by = 0; by < lpxH; by += BLK) {
        for (let bx = 0; bx < lpxW; bx += BLK) {
          _zxVotes.fill(0);
          for (let dy = 0; dy < BLK && by + dy < lpxH; dy++) {
            for (let dx = 0; dx < BLK && bx + dx < lpxW; dx++) {
              const z = zbuf[(by + dy) * lpxW + (bx + dx)];
              if (z < NZ) _zxVotes[z]++;
            }
          }
          let best = 0, bestV = 0;
          for (let z = 0; z < NZ; z++) { if (_zxVotes[z] > bestV) { bestV = _zxVotes[z]; best = z; } }
          if (best === 0) continue;
          const col = ZX_PALETTE[best];
          for (let dy = 0; dy < BLK && by + dy < lpxH; dy++) {
            for (let dx = 0; dx < BLK && bx + dx < lpxW; dx++) {
              const idx = (by + dy) * lpxW + (bx + dx);
              if (buf[idx] !== 0xFF000000) buf[idx] = col;
            }
          }
        }
      }
    }

    // Error / mute XOR flash
    if (FX.errorFlash > 0.6 && (++_flashFrame & 1)) buf.fill(0xFFFFFFFF);

    lpxCtx.putImageData(imgd, 0, 0);
    ctx.imageSmoothingEnabled = false;
    const _flt = PIXEL_FILTERS[pixelPal];
    // Neon bleed — hue-rotate + slight scale-bloom on sentence burst
    const nb = State.neonBleed;
    const neonFlt = nb > 0.05
      ? `hue-rotate(${(nb * 180) | 0}deg) saturate(${(1 + nb * 4).toFixed(2)})`
      : null;
    const combinedFlt = _flt && neonFlt ? `${_flt} ${neonFlt}` : (_flt || neonFlt);
    if (combinedFlt) ctx.filter = combinedFlt;
    if (nb > 0.05) {
      const bloom = 1 + nb * 0.006;
      const ox = W * (1 - bloom) * 0.5, oy = H * (1 - bloom) * 0.5;
      ctx.drawImage(lpxCV, ox, oy, W * bloom, H * bloom);
    } else {
      ctx.drawImage(lpxCV, 0, 0, W, H);
    }
    if (combinedFlt) ctx.filter = 'none';
  }


  // Oscilloscope XY mini-canvas — particle positions plotted as stereo XY scope
  // L=X, R=Y; the face shape emerges as a Lissajous figure in the bottom-right corner.
  function drawOscilloscope() {
    if (State.mode !== 'thinking' && State.mode !== 'speaking') return;
    const SZ = 128, fcx = Face.cx, fcy = Face.cy, fs = Face.s;
    const scale = 52 / fs;
    const maxZ = fs * 0.8;
    // Phosphor decay
    for (let j = 0; j < SZ * SZ; j++) scopeBuf[j] = Math.max(0, scopeBuf[j] * 0.78 - 0.005);
    // Accumulate — nearer particles (sz > 0) contribute more brightness
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const sx = ((p.x - fcx) * scale + SZ * 0.5) | 0;
      const sy = ((p.y - fcy) * scale + SZ * 0.5) | 0;
      if (sx >= 0 && sx < SZ && sy >= 0 && sy < SZ) {
        const depth = 0.18 + 0.52 * Math.max(0, Math.min(1, (p.sz + maxZ) / (maxZ * 2)));
        scopeBuf[sy * SZ + sx] = Math.min(1, scopeBuf[sy * SZ + sx] + depth);
      }
    }
    // Parse palette accent RGB for tinted phosphor
    const acc = (palette.accent || '255,255,255').split(',').map(Number);
    const aR = acc[0], aG = acc[1], aB = acc[2];
    // Render to scopeCV
    const imgd = scopeCtx.getImageData(0, 0, SZ, SZ);
    const sbuf = new Uint32Array(imgd.data.buffer);
    for (let j = 0; j < SZ * SZ; j++) {
      const v = scopeBuf[j];
      if (v <= 0) { sbuf[j] = 0xFF000000; continue; }
      const vi = Math.min(255, v * 255) | 0;
      sbuf[j] = 0xFF000000 | ((aB * vi / 255) & 0xFF) << 16 | ((aG * vi / 255) & 0xFF) << 8 | ((aR * vi / 255) & 0xFF);
    }
    // Frequency bar graph — 4px tall strip at bottom of scope canvas
    if (freqData) {
      const bars = 32, barH = 4;
      for (let b = 0; b < bars; b++) {
        const fi = (b / bars * freqData.length) | 0;
        const fv = (freqData[fi] / 255 * barH) | 0;
        const bx = (b / bars * SZ) | 0;
        const bw = Math.max(1, (SZ / bars - 1) | 0);
        for (let dy = 0; dy < fv; dy++) {
          const idx = (SZ - 1 - dy) * SZ + bx;
          for (let dx = 0; dx < bw; dx++) sbuf[idx + dx] = 0xFFFFFFFF;
        }
      }
    }
    scopeCtx.putImageData(imgd, 0, 0);
    // Blit to main canvas — bottom-right corner
    ctx.save();
    ctx.imageSmoothingEnabled = false;
    ctx.globalAlpha = 0.72;
    ctx.drawImage(scopeCV, W - 136, H - SZ - 40, SZ, SZ);
    ctx.restore();
  }
  function drawEdgePulse() {
    if (Face.edgePulse < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s, a = Face.edgePulse;
    ctx.fillStyle = '#fff'; ctx.globalAlpha = a;
    for (let i = 0; i < 52; i++) {
      const ang = (i / 52) * Math.PI * 2;
      const r = s * (1.11 + (i % 3 === 0 ? 0.07 : 0));
      ctx.fillRect((cx + Math.cos(ang) * r) | 0, (cy + Math.sin(ang) * r * 0.84) | 0, 1, 1);
    }
    ctx.globalAlpha = 1;
  }
  function drawCorona() {
    if (Face.coronaFlash < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s, v = Face.coronaFlash;
    const t = performance.now() * 0.001;
    ctx.fillStyle = '#fff';
    for (let i = 0; i < 18; i++) {
      const ang = (i / 18) * Math.PI * 2 + t * (i & 1 ? 0.4 : -0.4);
      const r0 = s * 1.14, r1 = s * (1.24 + (i % 3 === 0 ? 0.16 : 0.04));
      ctx.globalAlpha = v * (i % 3 === 0 ? 0.9 : 0.45);
      for (let r = r0; r <= r1; r += 2.5) {
        ctx.fillRect((cx + Math.cos(ang) * r) | 0, (cy + Math.sin(ang) * r * 0.84) | 0, 1, 1);
      }
    }
    ctx.globalAlpha = 1;
  }
  function drawThinkingOrbit(now) {
    if (State.mode !== 'thinking') return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const ang = now * 0.0023;
    const rx = s * 1.35, ry = s * 1.0;
    ctx.fillStyle = '#fff';
    for (let t = 8; t >= 0; t--) {
      const a2 = ang - t * 0.10;
      ctx.globalAlpha = (1 - t / 9) * 0.92;
      ctx.fillRect((cx + Math.cos(a2) * rx) | 0, (cy + Math.sin(a2) * ry) | 0, t === 0 ? 2 : 1, t === 0 ? 2 : 1);
    }
    ctx.globalAlpha = 1;
  }

  // Microsaccades — biological eye tremor during fixation
  // Real fixation includes ~3-5 microsaccades/second + drift; amplitude ~0.1-0.3°.
  // Modelled as random impulse + exponential decay offset over the intended gaze.
  const gazeJitter = [0, 0];
  function tickMicrosaccades(dt) {
    if (State.mode === 'sleep') return;
    const amp = State.mode === 'thinking' ? 0.038 : (State.mode === 'idle' ? 0.012 : 0.024);
    if (Math.random() < dt * 0.0035) {
      gazeJitter[0] = (Math.random() - 0.5) * amp;
      gazeJitter[1] = (Math.random() - 0.5) * amp * 0.45;
    }
    gazeJitter[0] *= 0.87;
    gazeJitter[1] *= 0.87;
  }

  // Look-aways — periodic gaze averts to break the stare
  let nextLookAway = performance.now() + 12000 + Math.random() * 6000;
  let lookAwayUntil = 0;
  function maybeLookAway(now) {
    if (State.mode !== 'idle' || tts.playing) return;
    if (now > lookAwayUntil) {
      if (lookAwayUntil > 0) {
        // look-away period just ended — return to center, schedule next
        Face.gazeTarget = [0, 0];
        nextLookAway = now + 12000 + Math.random() * 8000;
        lookAwayUntil = 0;
      } else if (now > nextLookAway) {
        // fire look-away
        Face.gazeTarget = [(Math.random() - 0.5) * 0.6, (Math.random() - 0.5) * 0.3];
        lookAwayUntil = now + 900 + Math.random() * 700;
      }
    }
  }

  function drawVortex() {
    if (Face.vortex < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s, v = Face.vortex;
    const t0 = performance.now() * 0.0018;
    ctx.fillStyle = '#fff';
    for (let arm = 0; arm < 3; arm++) {
      const off = (arm / 3) * Math.PI * 2;
      for (let j = 0; j <= 38; j++) {
        const f = j / 38;
        const ang = off + f * Math.PI * 3.6 + t0;
        const r = s * 0.14 + f * s * 0.96;
        ctx.globalAlpha = v * f * 0.65;
        ctx.fillRect((cx + Math.cos(ang) * r) | 0, (cy + Math.sin(ang) * r * 0.82) | 0, 1, 1);
      }
    }
    ctx.globalAlpha = 1;
  }

  function drawSweat() {
    if (FX.sweat < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s, a = FX.sweat;
    const bx = cx + s * 0.72, by = cy - s * 0.22 + (1 - a) * s * 0.20;
    const r = s * 0.055;
    ctx.fillStyle = `rgb(${palette.accent})`; ctx.globalAlpha = Math.min(1, a * 1.1);
    for (let i = 0; i < 18; i++) {
      const ang = (i / 18) * Math.PI;
      ctx.fillRect((bx + Math.cos(ang) * r) | 0, (by - Math.sin(ang) * r) | 0, 1, 1);
    }
    for (let j = 0; j <= 7; j++) {
      const f = j / 7, w = (r * (1 - f) * 0.65) | 0;
      ctx.fillRect((bx - w) | 0, (by + r + f * r * 1.4) | 0, Math.max(1, w * 2), 1);
    }
    ctx.globalAlpha = 1;
  }
  function drawVein() {
    if (FX.vein < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const pulse = 0.82 + Math.sin(performance.now() * 0.018) * 0.18;
    const bx = cx + s * 0.28, by = cy - s * 0.60;
    const r = s * 0.085 * pulse;
    ctx.fillStyle = `rgb(${palette.accent})`; ctx.globalAlpha = FX.vein;
    for (let arm = 0; arm < 4; arm++) {
      const ang = (arm / 4) * Math.PI * 2, perp = ang + Math.PI / 2;
      for (let j = 0; j <= 10; j++) {
        const f = j / 10;
        const ax = bx + Math.cos(ang) * r * f, ay = by + Math.sin(ang) * r * f;
        const bulge = Math.sin(f * Math.PI) * r * 0.34;
        ctx.fillRect((ax + Math.cos(perp) * bulge) | 0, (ay + Math.sin(perp) * bulge) | 0, 1, 1);
        ctx.fillRect((ax - Math.cos(perp) * bulge) | 0, (ay - Math.sin(perp) * bulge) | 0, 1, 1);
      }
    }
    ctx.globalAlpha = 1;
  }
  function drawBlush() {
    if (FX.blush < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const w = s * 0.20, h = s * 0.08;
    const golden = Math.PI * (3 - Math.sqrt(5));
    ctx.fillStyle = `rgb(${palette.accent})`; ctx.globalAlpha = FX.blush * 0.42;
    for (const side of [-1, 1]) {
      const bx = cx + side * s * 0.54, by = cy + s * 0.14;
      for (let i = 0; i < 30; i++) {
        const rr = Math.sqrt((i + 0.5) / 30);
        const ang = i * golden;
        ctx.fillRect((bx + Math.cos(ang) * rr * w) | 0, (by + Math.sin(ang) * rr * h) | 0, 1, 1);
      }
    }
    ctx.globalAlpha = 1;
  }
  function drawNoseBubble() {
    const r = FX.noseBubbleR;
    if (r < 2) return;
    const bx = Face.cx | 0, by = (Face.cy + Face.s * 0.46) | 0;
    const al = Math.max(0, 0.72 - r / (Face.s * 0.28) * 0.58);
    ctx.fillStyle = '#fff'; ctx.globalAlpha = al;
    const n = Math.max(14, (r * 0.95) | 0);
    for (let i = 0; i < n; i++) {
      const ang = (i / n) * Math.PI * 2;
      ctx.fillRect((bx + Math.cos(ang) * r) | 0, (by + Math.sin(ang) * r) | 0, 1, 1);
    }
    ctx.globalAlpha = al * 0.7;
    ctx.fillRect((bx + r * 0.5) | 0, (by - r * 0.5) | 0, 2, 2);
    ctx.globalAlpha = 1;
  }

  function drawSpeedLines() {
    if (FX.speedLines < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s, a = FX.speedLines;
    ctx.fillStyle = '#fff';
    for (let i = 0; i < 14; i++) {
      const ang = (i / 14) * Math.PI * 2;
      const r0 = s * 1.04, r1 = s * (1.38 + (i % 3) * 0.10);
      ctx.globalAlpha = a * (0.32 + (i % 3 === 0 ? 0.48 : 0));
      for (let r = r0; r < r1; r += 2.5) {
        ctx.fillRect((cx + Math.cos(ang) * r) | 0, (cy + Math.sin(ang) * r * 0.84) | 0, 1, 1);
      }
    }
    ctx.globalAlpha = 1;
  }
  function drawTears() {
    if (FX.tears < 0.05) return;
    const cx = Face.cx, cy = Face.cy, s = Face.s;
    const now = performance.now();
    ctx.fillStyle = `rgb(${palette.accent})`;
    for (const side of [-1, 1]) {
      const ex = cx + side * s * 0.30, ey = cy - s * 0.04;
      for (let d = 0; d < 3; d++) {
        const phase = (now * 0.0008 + d * 0.34) % 1;
        const px = (ex + side * phase * s * 0.04) | 0;
        const py = (ey + phase * s * 0.70) | 0;
        const al = FX.tears * Math.sin(phase * Math.PI);
        if (al < 0.03) continue;
        ctx.globalAlpha = al;
        const r = s * 0.022;
        for (let i = 0; i < 10; i++) {
          const ang = (i / 10) * Math.PI;
          ctx.fillRect((px + Math.cos(ang) * r) | 0, (py - Math.sin(ang) * r) | 0, 1, 1);
        }
        for (let j = 0; j <= 4; j++) {
          const f = j / 4, w = (r * (1 - f) * 0.58) | 0;
          ctx.fillRect(px - w, (py + r + f * r) | 0, Math.max(1, w * 2), 1);
        }
      }
    }
    ctx.globalAlpha = 1;
  }

  function drawCombo() {
    if (State.comboCount < 2 || State.comboDecay <= 0) return;
    const frac = State.comboDecay / 2800;
    // float upward as it decays
    const floatY = State.comboY - (1 - frac) * Face.s * 0.18;
    const sz = 8 + Math.min(24, (State.comboCount - 2) * 4);
    ctx.font = `${sz}px "Silkscreen",ui-monospace,monospace`;
    ctx.textBaseline = 'top';
    ctx.fillStyle = `rgba(255,255,255,${(frac * 0.85).toFixed(2)})`;
    ctx.fillText(`x${State.comboCount}`, Math.min(W - 40, (Face.cx + Face.s * 0.6) | 0), floatY | 0);
    ctx.textBaseline = 'alphabetic';
  }

  function drawContinue() {
    if (State.continueCount < 0) return;
    const n = State.continueCount;
    const pulse = 0.55 + Math.sin(performance.now() * 0.004) * 0.17;
    const fontSize = n <= 3 ? 8 + (4 - n) * 4 : 8;
    ctx.font = `${fontSize}px "Silkscreen",ui-monospace,monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = n > 3
      ? `rgba(255,255,255,${pulse.toFixed(2)})`
      : `rgba(255,${n > 1 ? 255 : 80},${n > 1 ? 255 : 80},${(pulse * 1.3).toFixed(2)})`;
    ctx.fillText(`CONTINUE? ${n}`, Face.cx, Face.cy + Face.s * 1.6);
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  const HUD_MODE = { idle: 'IDL', sleep: 'SLP', speaking: 'SPK', thinking: 'THK', listening: 'LSN', error: 'ERR', ack: 'ACK' };
  function drawHUD() {
    ctx.font = '8px "Silkscreen",ui-monospace,monospace';
    ctx.textBaseline = 'top';
    ctx.fillStyle = 'rgba(255,255,255,0.28)';
    const modeCode = HUD_MODE[State.mode] || State.mode.slice(0, 3).toUpperCase();
    const m = tts.muted ? ' [M]' : '';
    const lorenzTag = State.lorenzMode ? ' LZ' : '';
    ctx.fillText(`${modeCode} ${State.mood.slice(0, 8)} ${PIXEL_PAL_NAMES[pixelPal]}${m}${lorenzTag}`, 8, 8);
    ctx.textBaseline = 'alphabetic';
  }

  // Wire events
  cv.addEventListener('pointerdown', pointerStart);
  cv.addEventListener('pointermove', pointerMove);
  cv.addEventListener('pointerup',   pointerEnd);
  cv.addEventListener('pointercancel', pointerEnd);
  document.addEventListener('pointermove', (e) => {
    if (Gesture.down || e.pointerType !== 'mouse') return;
    const lean = 0.25;
    Face.gazeTarget = [(e.clientX - W * 0.5) / W * lean, (e.clientY - H * 0.5) / H * lean];
  }, { passive: true });
  cv.addEventListener('touchstart', (e) => { if (e.touches.length === 2) { Gesture.twoPtr = false; handlePinch(e); } }, { passive: true });
  cv.addEventListener('touchmove',  (e) => { if (e.touches.length === 2) handlePinch(e); }, { passive: true });
  cv.addEventListener('touchend',   () => { Gesture.twoPtr = false; });
  window.addEventListener('resize', resize);

  document.addEventListener('mousemove', (e) => {
    if (e.buttons) return;
    Face.yawTarget   = (e.clientX / innerWidth  - 0.5) * 0.7;
    Face.pitchTarget = (e.clientY / innerHeight - 0.5) * 0.45;
  }, { passive: true });

  // Topology events from visual_bridge.js — drive codebase disperse.
  window.addEventListener('master:visual', (e) => {
    const top = (e.detail || {}).topology || '';
    Face.codespaceTarget = top === 'codebase' ? 1.0 : 0.0;
  });

  // Primer unlock
  const primer = document.getElementById('primer');
  const zshBar = document.getElementById('zsh');
  const zshIn  = document.getElementById('zin');
  const POST_LINES = [
    'MASTER  v1.0', 'RAM: \u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593 2048K OK',
    'SOUL............OK', 'CONSTITUTION....OK',
    'PIPELINE........OK', 'COUNCIL.........OK', '> READY'
  ];
  function startEverything() {
    initAudio();
    if (actx && actx.state === 'suspended') actx.resume();
    // Boot POST: type lines onto canvas, then dismiss primer
    let li = 0;
    const postEl = Object.assign(document.createElement('pre'), {
      style: 'position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font:8px "Silkscreen",monospace;color:#fff;text-align:left;white-space:pre;pointer-events:none'
    });
    primer.appendChild(postEl);
    const postTick = () => {
      if (li < POST_LINES.length) {
        postEl.textContent += POST_LINES[li] + '\n';
        beep(li === POST_LINES.length - 1 ? 880 : 440 + li * 12, 0.04);
        li++;
        setTimeout(postTick, li < POST_LINES.length ? 160 : 320);
      } else {
        primer.classList.add('gone');
        setTimeout(() => primer.remove(), 1000);
        zshBar.classList.add('live');
        unlockTTS();
        requestMotionPermission(); acquireWakeLock(); initVAD();
        Face.dispersionTarget = 0;
        DMESG_PHRASES.slice(0, -1).forEach((p, i) => setTimeout(() => whisper(p), 400 + i * 600));
        setTimeout(() => enqueueSpeech('ready'), 400 + DMESG_PHRASES.length * 600);
        if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
      }
    };
    setTimeout(postTick, 80);
  }
  primer.addEventListener('pointerdown', startEverything, { once: true });
  
  // Zsh prompt bar
  zshIn.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    const v = zshIn.value.trim();
    if (!v) return;
    e.preventDefault();
    window._chatOnUser?.(v);
    zshIn.value = '';
    Face.dispersionTarget = 0.25;
    sendMessage(v);
  });
  zshIn.addEventListener('focus', () => { State.lastTouch = performance.now(); });

  // Konami code — ↑↑↓↓←→←→ba
  const KONAMI = ['ArrowUp','ArrowUp','ArrowDown','ArrowDown','ArrowLeft','ArrowRight','ArrowLeft','ArrowRight','b','a'];
  let konamiIdx = 0;

  // Keyboard fallback
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') ttsSkip();
    if (e.ctrlKey && e.key === 'm') { e.preventDefault(); ttsToggleMute(); }
    if (e.key === 'p' && !e.ctrlKey && !e.altKey && document.activeElement !== zshIn) {
      pixelPal = (pixelPal + 1) % PIXEL_FILTERS.length;
      beep(440 + pixelPal * 110, 0.04);
    }
    if (e.key === 'l' && !e.ctrlKey && !e.altKey && document.activeElement !== zshIn) {
      State.lorenzMode = !State.lorenzMode;
      if (State.lorenzMode) {
        // Re-seed attractor state so particles start near the Lorenz attractor basin
        for (let i = 0; i < particles.length; i++) {
          particles[i].lx = (Math.random() - 0.5) * 2;
          particles[i].ly = (Math.random() - 0.5) * 2;
          particles[i].lz = 24 + Math.random() * 4;
        }
      }
      beep(State.lorenzMode ? 660 : 330, 0.06);
    }
    if (e.key === 'm' && !e.ctrlKey && !e.altKey && document.activeElement !== zshIn) {
      triggerMaskSwitch();
      beep(550, 0.05);
    }
    // Konami sequence tracker
    if (e.key === KONAMI[konamiIdx]) {
      konamiIdx++;
      if (konamiIdx === KONAMI.length) {
        konamiIdx = 0;
        vortex(); Face.coronaFlash = 1.0;
        [330, 440, 550, 660, 880].forEach((f, i) => setTimeout(() => beep(f, 0.06), i * 80));
        State.neonBleed = 1.0;
      }
    } else { konamiIdx = 0; }
  });

  window.sendMessage = sendMessage;

  // boot
  _doResize();
  requestAnimationFrame(frame);
