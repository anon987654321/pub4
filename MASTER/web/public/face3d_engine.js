"use strict";

// MASTER Face3D Engine
// A small, standalone engine for semantic 3D faces rendered as particles.
// It does not replace the retro face.js renderer yet; it exposes the normalized
// topology, blendshape rig, typed-array particle core, spatial hash, and quality
// controller needed to migrate face.js in small safe steps.

const ZONES = Object.freeze({
  outlineL: 1, outlineR: 2,
  eyeL: 3, eyeR: 4, pupilL: 5, pupilR: 6,
  browL: 7, browR: 8,
  noseRidge: 9, noseFlare: 10,
  mouth: 11, chin: 12,
  crown: 13, cheekL: 14, cheekR: 15,
  sideL: 16, sideR: 17
});

const ZONE_NAMES = Object.freeze(Object.fromEntries(
  Object.entries(ZONES).map(([name, id]) => [id, name])
));

const DEFAULT_BLEND = Object.freeze({
  blink: 0,
  squint: 0,
  browInnerUp: 0,
  browDown: 0,
  smile: 0,
  frown: 0,
  jawOpen: 0,
  mouthWide: 0,
  mouthRound: 0,
  pupilDilate: 0,
  nostrilFlare: 0,
  cheekRaise: 0,
  shock: 0,
  chibi: 0
});

const DEFAULT_EMOTION = Object.freeze({
  arousal: 0,
  valence: 0,
  focus: 0,
  confidence: 1,
  fatigue: 0
});

function clamp(v, lo = 0, hi = 1) {
  return Math.max(lo, Math.min(hi, v));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function damp(current, target, lambda, dtMs) {
  const t = 1 - Math.exp(-lambda * dtMs * 0.001);
  return lerp(current, target, t);
}

function zoneId(zone) {
  return ZONES[zone] || 0;
}

function makeAnchor(x, y, z, zone, u = 0, normal = [0, 0, 1]) {
  return { x, y, z, zone, zoneId: zoneId(zone), u, normal };
}

function line3(x0, y0, z0, x1, y1, z1, n, zone) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = n > 1 ? i / (n - 1) : 0;
    out.push(makeAnchor(lerp(x0, x1, t), lerp(y0, y1, t), lerp(z0, z1, t), zone, t));
  }
  return out;
}

function ring3(cx, cy, cz, rx, ry, n, zone, zWave = 0) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = i / n;
    const a = t * Math.PI * 2;
    const x = cx + Math.cos(a) * rx;
    const y = cy + Math.sin(a) * ry;
    const z = cz + Math.sin(a * 2) * zWave;
    out.push(makeAnchor(x, y, z, zone, t, normalize3([x - cx, y - cy, 0.7])));
  }
  return out;
}

function disc3(cx, cy, cz, r, n, zone) {
  const out = [];
  const golden = Math.PI * (3 - Math.sqrt(5));
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const rr = r * Math.sqrt(t);
    const a = i * golden;
    out.push(makeAnchor(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr, cz, zone, t));
  }
  return out;
}

function normalize3(v) {
  const len = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / len, v[1] / len, v[2] / len];
}

function buildCanonicalMask(kind = "sepik") {
  switch (kind) {
    case "asmat": return buildAsmatMask();
    case "baining": return buildBainingMask();
    case "tolai": return buildTolaiMask();
    case "neutral": return buildNeutralMask();
    default: return buildSepikMask();
  }
}

function zoneMap(anchors) {
  const zones = {};
  for (const a of anchors) {
    if (!zones[a.zone]) zones[a.zone] = [];
    zones[a.zone].push(a);
  }
  return { anchors, zones };
}

function buildNeutralMask() {
  const a = [];
  for (let i = 0; i < 72; i++) {
    const t = i / 71;
    const y = -0.92 + t * 1.84;
    const w = 0.18 + 0.54 * Math.sin(t * Math.PI);
    const z = 0.08 * Math.sin(t * Math.PI);
    a.push(makeAnchor(-w, y, z, "outlineL", t));
    a.push(makeAnchor(w, y, z, "outlineR", t));
  }
  a.push(...line3(-0.42, -0.30, 0.22, -0.12, -0.24, 0.34, 16, "browL"));
  a.push(...line3(0.12, -0.24, 0.34, 0.42, -0.30, 0.22, 16, "browR"));
  a.push(...ring3(-0.28, -0.13, 0.42, 0.13, 0.07, 28, "eyeL", 0.015));
  a.push(...ring3(0.28, -0.13, 0.42, 0.13, 0.07, 28, "eyeR", 0.015));
  a.push(...disc3(-0.28, -0.13, 0.49, 0.035, 8, "pupilL"));
  a.push(...disc3(0.28, -0.13, 0.49, 0.035, 8, "pupilR"));
  a.push(...line3(0, -0.34, 0.46, 0, 0.34, 0.58, 30, "noseRidge"));
  a.push(...ring3(-0.07, 0.39, 0.54, 0.045, 0.025, 8, "noseFlare"));
  a.push(...ring3(0.07, 0.39, 0.54, 0.045, 0.025, 8, "noseFlare"));
  a.push(...mouthAnchors("neutral", 34));
  a.push(...line3(-0.14, 0.80, 0.18, 0.14, 0.80, 0.18, 12, "chin"));
  a.push(...disc3(-0.38, 0.22, 0.26, 0.055, 10, "cheekL"));
  a.push(...disc3(0.38, 0.22, 0.26, 0.055, 10, "cheekR"));
  return zoneMap(a);
}

function buildSepikMask() {
  const base = buildNeutralMask().anchors.slice();
  const crown = [];
  for (let i = 0; i < 16; i++) {
    const t = (i - 7.5) / 7.5;
    crown.push(...line3(t * 0.09, -0.78, 0.18, t * 0.28, -1.28 - Math.abs(t) * 0.16, 0.05, 9, "crown"));
  }
  const noseHook = line3(0, 0.28, 0.58, 0.15, 0.44, 0.54, 8, "noseRidge");
  return zoneMap(base.concat(crown, noseHook));
}

function buildAsmatMask() {
  const a = buildNeutralMask().anchors.filter(anchor => !anchor.zone.startsWith("eye"));
  a.push(...diamondEye(-0.29, -0.08, 0.43, "eyeL"));
  a.push(...diamondEye(0.29, -0.08, 0.43, "eyeR"));
  a.push(...disc3(-0.29, -0.08, 0.50, 0.040, 8, "pupilL"));
  a.push(...disc3(0.29, -0.08, 0.50, 0.040, 8, "pupilR"));
  for (let r = 0; r < 3; r++) {
    const y = -0.58 - r * 0.12;
    a.push(...line3(-0.34, y, 0.14, 0, y - 0.08, 0.20, 8, "crown"));
    a.push(...line3(0, y - 0.08, 0.20, 0.34, y, 0.14, 8, "crown"));
  }
  return zoneMap(a);
}

function buildBainingMask() {
  const a = buildNeutralMask().anchors.filter(anchor => !["eyeL", "eyeR", "pupilL", "pupilR", "mouth"].includes(anchor.zone));
  a.push(...ring3(-0.36, -0.18, 0.40, 0.22, 0.18, 36, "eyeL", 0.02));
  a.push(...ring3(0.36, -0.18, 0.40, 0.22, 0.18, 36, "eyeR", 0.02));
  a.push(...spiralEye(-0.36, -0.18, 0.51, "pupilL"));
  a.push(...spiralEye(0.36, -0.18, 0.51, "pupilR"));
  a.push(...ring3(0, 0.48, 0.42, 0.38, 0.16, 40, "mouth", 0.02));
  return zoneMap(a);
}

function buildTolaiMask() {
  const a = buildNeutralMask().anchors.filter(anchor => !["outlineL", "outlineR", "mouth"].includes(anchor.zone));
  for (let i = 0; i < 56; i++) {
    const t = i / 55;
    const y = -1.05 + t * 1.95;
    const w = 0.12 + t * 0.60;
    a.push(makeAnchor(-w, y, 0.02, "outlineL", t));
    a.push(makeAnchor(w, y, 0.02, "outlineR", t));
  }
  a.push(...mouthAnchors("O", 32));
  a.push(...line3(-0.72, -0.05, 0.00, -0.84, 0.66, -0.05, 16, "sideL"));
  a.push(...line3(0.72, -0.05, 0.00, 0.84, 0.66, -0.05, 16, "sideR"));
  return zoneMap(a);
}

function diamondEye(cx, cy, cz, zone) {
  return [
    ...line3(cx, cy - 0.10, cz, cx + 0.18, cy, cz, 8, zone),
    ...line3(cx + 0.18, cy, cz, cx, cy + 0.10, cz, 8, zone),
    ...line3(cx, cy + 0.10, cz, cx - 0.18, cy, cz, 8, zone),
    ...line3(cx - 0.18, cy, cz, cx, cy - 0.10, cz, 8, zone)
  ];
}

function spiralEye(cx, cy, cz, zone) {
  const out = [];
  for (let i = 0; i < 26; i++) {
    const t = i / 25;
    const ang = t * Math.PI * 4;
    const r = t * 0.15;
    out.push(makeAnchor(cx + Math.cos(ang) * r, cy + Math.sin(ang) * r * 0.82, cz, zone, t));
  }
  return out;
}

function mouthAnchors(shape = "neutral", n = 34) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = n > 1 ? i / (n - 1) : 0;
    const u = (t - 0.5) * 2;
    const x = u * 0.34;
    let y = 0.58;
    let z = 0.42;
    if (shape === "smile") y -= Math.sin(t * Math.PI) * 0.12;
    if (shape === "frown") y += Math.sin(t * Math.PI) * 0.12;
    if (shape === "O") { y += Math.sin(t * Math.PI) * 0.18; z += 0.04; }
    out.push(makeAnchor(x, y, z, "mouth", t));
  }
  return out;
}

function applyBlendshape(anchor, blend) {
  let x = anchor.x;
  let y = anchor.y;
  let z = anchor.z;
  const zone = anchor.zone;
  const side = x < 0 ? -1 : 1;
  const centerWeight = 1 - clamp(Math.abs(x) / 0.7);

  if (zone === "browL" || zone === "browR") {
    y += blend.browDown * 0.07;
    y -= blend.browInnerUp * centerWeight * 0.10;
    z += blend.focus * 0.02 || 0;
  }

  if (zone === "eyeL" || zone === "eyeR") {
    y *= 1 - blend.blink * 0.72 - blend.squint * 0.20;
    x += side * blend.shock * 0.035;
  }

  if (zone === "pupilL" || zone === "pupilR") {
    x += side * blend.shock * 0.025;
    y -= blend.shock * 0.010;
    z += blend.pupilDilate * 0.030;
  }

  if (zone === "mouth") {
    const lower = anchor.u > 0.50 ? 1 : 0.45;
    y += blend.jawOpen * lower * 0.16;
    y -= blend.smile * Math.sin(anchor.u * Math.PI) * 0.11;
    y += blend.frown * Math.sin(anchor.u * Math.PI) * 0.10;
    x *= 1 + blend.mouthWide * 0.22 - blend.mouthRound * 0.22;
    z += blend.mouthRound * 0.08;
  }

  if (zone === "noseFlare") {
    x += side * blend.nostrilFlare * 0.035;
    z += blend.nostrilFlare * 0.035;
  }

  if (zone === "cheekL" || zone === "cheekR") {
    y -= blend.cheekRaise * 0.07;
    z += blend.cheekRaise * 0.04;
  }

  if (blend.chibi > 0) {
    y *= 1 - blend.chibi * 0.28;
    x *= 1 + blend.chibi * 0.10;
  }

  return { ...anchor, x, y, z };
}

function deriveBlendFromEmotion(emotion, previous = DEFAULT_BLEND) {
  const e = { ...DEFAULT_EMOTION, ...emotion };
  return {
    ...previous,
    browDown: clamp(e.focus * 0.45 + (1 - e.confidence) * 0.35 + Math.max(0, -e.valence) * 0.20),
    browInnerUp: clamp((1 - e.confidence) * 0.25 + Math.max(0, e.valence) * 0.20),
    pupilDilate: clamp(e.arousal * 0.55 + (1 - e.confidence) * 0.18),
    smile: clamp(Math.max(0, e.valence) * 0.55),
    frown: clamp(Math.max(0, -e.valence) * 0.45),
    squint: clamp(e.focus * 0.18 + e.fatigue * 0.20),
    cheekRaise: clamp(Math.max(0, e.valence) * 0.30)
  };
}

class ParticleField3D {
  constructor(count = 2200) {
    this.count = count;
    this.x = new Float32Array(count);
    this.y = new Float32Array(count);
    this.z = new Float32Array(count);
    this.vx = new Float32Array(count);
    this.vy = new Float32Array(count);
    this.homeX = new Float32Array(count);
    this.homeY = new Float32Array(count);
    this.homeZ = new Float32Array(count);
    this.u = new Float32Array(count);
    this.mass = new Float32Array(count);
    this.zone = new Uint8Array(count);
    this.seed = new Uint32Array(count);
    this.depth = new Float32Array(count);
    this.brightness = new Float32Array(count);

    for (let i = 0; i < count; i++) {
      this.x[i] = (Math.random() - 0.5) * 2;
      this.y[i] = (Math.random() - 0.5) * 2;
      this.z[i] = 0;
      this.mass[i] = 0.75 + Math.random() * 0.75;
      this.u[i] = Math.random();
      this.seed[i] = (Math.random() * 0xFFFFFFFF) >>> 0;
    }
  }

  assignStable(topology) {
    const zoneNames = Object.keys(topology.zones);
    const weighted = [];
    const density = { pupilL: 5, pupilR: 5, eyeL: 3, eyeR: 3, mouth: 2, noseRidge: 2, browL: 2, browR: 2 };
    for (const name of zoneNames) {
      const repeats = density[name] || 1;
      for (let r = 0; r < repeats; r++) weighted.push(name);
    }

    for (let i = 0; i < this.count; i++) {
      const name = weighted[i % weighted.length];
      const list = topology.zones[name] || topology.anchors;
      const u = ((this.seed[i] % 10000) / 9999);
      const idx = Math.min(list.length - 1, Math.floor(u * list.length));
      const a = list[idx];
      this.zone[i] = a.zoneId;
      this.u[i] = u;
      this.setHome(i, a);
    }
  }

  setHome(i, anchor) {
    const jitter = seededJitter(this.seed[i]);
    this.homeX[i] = anchor.x + jitter[0] * 0.008;
    this.homeY[i] = anchor.y + jitter[1] * 0.008;
    this.homeZ[i] = anchor.z + jitter[2] * 0.006;
  }

  updateHomes(topology, blend) {
    for (let i = 0; i < this.count; i++) {
      const name = ZONE_NAMES[this.zone[i]];
      const list = topology.zones[name] || topology.anchors;
      const idx = Math.min(list.length - 1, Math.floor(this.u[i] * list.length));
      this.setHome(i, applyBlendshape(list[idx], blend));
    }
  }

  tick(dtMs, pose, quality) {
    const yaw = pose.yaw || 0;
    const pitch = pose.pitch || 0;
    const roll = pose.roll || 0;
    const cy = Math.cos(yaw), sy = Math.sin(yaw);
    const cp = Math.cos(pitch), sp = Math.sin(pitch);
    const cr = Math.cos(roll), sr = Math.sin(roll);
    const spring = quality?.spring ?? 0.080;
    const damping = quality?.damping ?? 0.88;

    for (let i = 0; i < this.count; i++) {
      let x = this.homeX[i], y = this.homeY[i], z = this.homeZ[i];
      const xr = x * cr - y * sr;
      const yr = x * sr + y * cr;
      x = xr; y = yr;
      const xy = x * cy + z * sy;
      const zy = -x * sy + z * cy;
      x = xy; z = zy;
      const yp = y * cp - z * sp;
      z = y * sp + z * cp;
      y = yp;

      const fov = 2.2;
      const ps = fov / Math.max(0.25, fov - z);
      const tx = x * ps;
      const ty = y * ps;

      this.vx[i] += (tx - this.x[i]) * spring / this.mass[i];
      this.vy[i] += (ty - this.y[i]) * spring / this.mass[i];
      this.vx[i] *= damping;
      this.vy[i] *= damping;
      this.x[i] += this.vx[i] * dtMs * 0.06;
      this.y[i] += this.vy[i] * dtMs * 0.06;
      this.depth[i] = z;
      this.brightness[i] = clamp(0.25 + z * 0.35 + ps * 0.25, 0.05, 1);
    }
  }
}

function seededJitter(seed) {
  let s = seed >>> 0;
  const next = () => {
    s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
    return ((s >>> 0) / 0xFFFFFFFF) * 2 - 1;
  };
  return [next(), next(), next()];
}

class SpatialHash2D {
  constructor(cellSize = 0.025) {
    this.cellSize = cellSize;
    this.cells = new Map();
  }

  clear() { this.cells.clear(); }

  key(x, y) {
    return `${Math.floor(x / this.cellSize)},${Math.floor(y / this.cellSize)}`;
  }

  add(index, x, y) {
    const key = this.key(x, y);
    let bucket = this.cells.get(key);
    if (!bucket) this.cells.set(key, bucket = []);
    bucket.push(index);
  }

  nearby(x, y) {
    const cx = Math.floor(x / this.cellSize);
    const cy = Math.floor(y / this.cellSize);
    const out = [];
    for (let yy = cy - 1; yy <= cy + 1; yy++) {
      for (let xx = cx - 1; xx <= cx + 1; xx++) {
        const bucket = this.cells.get(`${xx},${yy}`);
        if (bucket) out.push(...bucket);
      }
    }
    return out;
  }
}

class QualityController {
  constructor() {
    this.tier = "auto";
    this.particles = matchMedia('(pointer: coarse)').matches ? 700 : 2600;
    this.dpr = Math.min(devicePixelRatio || 1, matchMedia('(pointer: coarse)').matches ? 1.25 : 2);
    this.fpsCap = 60;
    this.spring = 0.080;
    this.damping = 0.88;
    this.effects = {
      phosphor: true,
      bloom: true,
      oscilloscope: true,
      spatialRepulsion: !matchMedia('(pointer: coarse)').matches
    };
    this.avgFrameMs = 16.7;
  }

  observeFrame(dtMs) {
    this.avgFrameMs = damp(this.avgFrameMs, dtMs, 2.0, dtMs);
    if (this.avgFrameMs > 24) this.drop();
    else if (this.avgFrameMs < 13) this.raise();
  }

  drop() {
    if (this.tier === "battery") return;
    this.fpsCap = 30;
    this.effects.bloom = false;
    this.effects.spatialRepulsion = false;
  }

  raise() {
    if (this.tier === "battery") return;
    this.fpsCap = 60;
    this.effects.bloom = true;
  }

  battery() {
    this.tier = "battery";
    this.fpsCap = 30;
    this.effects.bloom = false;
    this.effects.oscilloscope = false;
    this.effects.spatialRepulsion = false;
  }
}

class VisemeDriver {
  constructor() {
    this.shape = "neutral";
    this.jaw = 0;
  }

  shapeAt(text, audioTime, duration, energy = 0) {
    const idx = Math.floor((audioTime / Math.max(duration, 0.1)) * text.length);
    const c = (text[idx] || '').toLowerCase();
    if ('aæɑ'.includes(c)) this.shape = "A";
    else if ('eɛi'.includes(c)) this.shape = "E";
    else if ('oɔå'.includes(c)) this.shape = "O";
    else if ('uʊy'.includes(c)) this.shape = "U";
    else if ('mbpfvw'.includes(c)) this.shape = "M";
    else if (c === ' ' || c === '.' || c === ',') this.shape = "neutral";
    else this.shape = "E";
    this.jaw = clamp(energy * 1.4);
    return { shape: this.shape, jaw: this.jaw };
  }

  toBlend(viseme) {
    return {
      jawOpen: viseme.jaw + (viseme.shape === "A" ? 0.35 : 0) + (viseme.shape === "O" ? 0.22 : 0),
      mouthRound: viseme.shape === "O" || viseme.shape === "U" ? 0.85 : 0,
      mouthWide: viseme.shape === "E" ? 0.55 : 0,
      smile: 0,
      frown: 0
    };
  }
}

class Face3DEngine {
  constructor({ count } = {}) {
    this.quality = new QualityController();
    this.topology = buildCanonicalMask("sepik");
    this.particles = new ParticleField3D(count || this.quality.particles);
    this.particles.assignStable(this.topology);
    this.blend = { ...DEFAULT_BLEND };
    this.emotion = { ...DEFAULT_EMOTION };
    this.pose = { yaw: 0, pitch: 0, roll: 0 };
    this.visemes = new VisemeDriver();
  }

  setMask(kind) {
    this.topology = buildCanonicalMask(kind);
    this.particles.assignStable(this.topology);
  }

  setEmotion(patch) {
    this.emotion = { ...this.emotion, ...patch };
    this.blend = deriveBlendFromEmotion(this.emotion, this.blend);
  }

  setBlend(patch) {
    this.blend = { ...this.blend, ...patch };
  }

  setPose(patch) {
    this.pose = { ...this.pose, ...patch };
  }

  speakFrame(text, audioTime, duration, energy = 0) {
    const viseme = this.visemes.shapeAt(text, audioTime, duration, energy);
    this.setBlend(this.visemes.toBlend(viseme));
    return viseme;
  }

  tick(dtMs) {
    this.quality.observeFrame(dtMs);
    this.particles.updateHomes(this.topology, this.blend);
    this.particles.tick(dtMs, this.pose, this.quality);
  }

  snapshot() {
    return {
      count: this.particles.count,
      x: this.particles.x,
      y: this.particles.y,
      depth: this.particles.depth,
      brightness: this.particles.brightness,
      zone: this.particles.zone
    };
  }
}

window.MasterFace3D = Object.freeze({
  ZONES,
  ZONE_NAMES,
  buildCanonicalMask,
  applyBlendshape,
  deriveBlendFromEmotion,
  ParticleField3D,
  SpatialHash2D,
  QualityController,
  VisemeDriver,
  Face3DEngine
});

export {
  ZONES,
  ZONE_NAMES,
  buildCanonicalMask,
  applyBlendshape,
  deriveBlendFromEmotion,
  ParticleField3D,
  SpatialHash2D,
  QualityController,
  VisemeDriver,
  Face3DEngine
};
