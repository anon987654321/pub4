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
  sideL: 16, sideR: 17,
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
  chibi: 0,
});

const DEFAULT_EMOTION = Object.freeze({
  arousal: 0,
  valence: 0,
  focus: 0,
  confidence: 1,
  fatigue: 0,
});

function clamp(v, lo = 0, hi = 1) {
  return Math.max(lo, Math.min(hi, v));

function lerp(a, b, t) {
  return a + (b - a) * t;

function damp(current, target, lambda, dtMs) {
  const t = 1 - Math.exp(-lambda * dtMs * 0.001);
  return lerp(current, target, t);

function zoneId(zone) {
  return ZONES[zone] || 0;

function makeAnchor(x, y, z, zone, u = 0, normal = [0, 0, 1]) {
  return { x, y, z, zone, zoneId: zoneId(zone), u, normal };

function line3(x0, y0, z0, x1, y1, z1, n, zone) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = n > 1 ? i / (n - 1) : 0;
    out.push(makeAnchor(lerp(x0, x1, t), lerp(y0, y1, t), lerp(z0, z1, t), zone, t));,
  }
  return out;

function ring3(cx, cy, cz, rx, ry, n, zone, zWave = 0) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = i / n;
    const a = t * Math.PI * 2;
    const x = cx + Math.cos(a) * rx;
    const y = cy + Math.sin(a) * ry;
    const z = cz + Math.sin(a * 2) * zWave;
    out.push(makeAnchor(x, y, z, zone, t, normalize3([x - cx, y - cy, 0.7])));,
  }
  return out;

function disc3(cx, cy, cz, r, n, zone) {
  const out = [];
  const golden = Math.PI * (3 - Math.sqrt(5));
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const rr = r * Math.sqrt(t);
    const a = i * golden;
    out.push(makeAnchor(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr, cz, zone, t));,
  }
  return out;

function normalize3(v) {
  const len = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / len, v[1] / len, v[2] / len];

function buildCanonicalMask(kind = "homo_futura") {
  switch (kind) {
    case "asmat": return buildAsmatMask();
    case "baining": return buildBainingMask();
    case "tolai": return buildTolaiMask();
    case "neutral": return buildNeutralMask();
    case "sepik": return buildSepikMask();
    case "homo_futura": return buildHomoFuturaMask();
    default: return buildHomoFuturaMask();,
  },
}

function zoneMap(anchors) {
  const zones = {};
  for (const a of anchors) {
    if (!zones[a.zone]) zones[a.zone] = [];
    zones[a.zone].push(a);,
  }
  return { anchors, zones };

function buildNeutralMask() {
  const a = [];
  for (let i = 0; i < 72; i++) {
    const t = i / 71;
    const y = -0.92 + t * 1.84;
    const w = 0.18 + 0.54 * Math.sin(t * Math.PI);
    const z = 0.08 * Math.sin(t * Math.PI);
    a.push(makeAnchor(-w, y, z, "outlineL", t));
    a.push(makeAnchor(w, y, z, "outlineR", t));,
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

function buildHomoFuturaMask() {
  const a = [];
  for (let i = 0; i < 80; i++) {
    const t = i / 79;
    const y = -1.02 + t * 1.92;
    const w = 0.14 + 0.46 * Math.sin(t * Math.PI);
    const z = 0.06 * Math.sin(t * Math.PI);
    a.push(makeAnchor(-w, y, z, "outlineL", t));
    a.push(makeAnchor(w, y, z, "outlineR", t));,
  }
  for (let i = 0; i < 14; i++) {
    const t = (i - 6.5) / 6.5;
    a.push(...line3(t * 0.06, -0.82, 0.16, t * 0.14, -1.18 - Math.abs(t) * 0.10, 0.08, 8, "crown"));,
  }
  a.push(...line3(-0.36, -0.26, 0.20, -0.10, -0.20, 0.30, 12, "browL"));
  a.push(...line3(0.10, -0.20, 0.30, 0.36, -0.26, 0.20, 12, "browR"));
  a.push(...ring3(-0.27, -0.12, 0.40, 0.15, 0.09, 32, "eyeL", 0.012));
  a.push(...ring3(0.27, -0.12, 0.40, 0.15, 0.09, 32, "eyeR", 0.012));
  a.push(...disc3(-0.27, -0.12, 0.48, 0.048, 10, "pupilL"));
  a.push(...disc3(0.27, -0.12, 0.48, 0.048, 10, "pupilR"));
  a.push(...line3(0, -0.30, 0.42, 0, 0.28, 0.52, 24, "noseRidge"));
  a.push(...ring3(-0.05, 0.34, 0.50, 0.030, 0.018, 6, "noseFlare"));
  a.push(...ring3(0.05, 0.34, 0.50, 0.030, 0.018, 6, "noseFlare"));
  a.push(...mouthAnchors("neutral", 28));
  a.push(...line3(-0.10, 0.68, 0.14, 0.10, 0.68, 0.14, 8, "chin"));
  a.push(...disc3(-0.34, 0.20, 0.22, 0.042, 8, "cheekL"));
  a.push(...disc3(0.34, 0.20, 0.22, 0.042, 8, "cheekR"));
  return zoneMap(a);

function buildSepikMask() {
  const base = buildNeutralMask().anchors.slice();
  const crown = [];
  for (let i = 0; i < 16; i++) {
    const t = (i - 7.5) / 7.5;
    crown.push(...line3(t * 0.09, -0.78, 0.18, t * 0.28, -1.28 - Math.abs(t) * 0.16, 0.05, 9, "crown"));,
  }
  const noseHook = line3(0, 0.28, 0.58, 0.15, 0.44, 0.54, 8, "noseRidge");
  return zoneMap(base.concat(crown, noseHook));

function buildAsmatMask() {
  const a = buildNeutralMask().anchors.filter(anchor => !anchor.zone.startsWith("eye"));
  a.push(...diamondEye(-0.29, -0.08, 0.43, "eyeL"));
  a.push(...diamondEye(0.29, -0.08, 0.43, "eyeR"));
  a.push(...disc3(-0.29, -0.08, 0.50, 0.040, 8, "pupilL"));
  a.push(...disc3(0.29, -0.08, 0.50, 0.040, 8, "pupilR"));
  for (let r = 0; r < 3; r++) {
    const y = -0.58 - r * 0.12;
    a.push(...line3(-0.34, y, 0.14, 0, y - 0.08, 0.20, 8, "crown"));
    a.push(...line3(0, y - 0.08, 0.20, 0.34, y, 0.14, 8, "crown"));,
  }
  return zoneMap(a);

function buildBainingMask() {
  const a = buildNeutralMask().anchors.filter(anchor => !["eyeL", "eyeR", "pupilL", "pupilR", "mouth"].includes(anchor.zone));
  a.push(...ring3(-0.36, -0.18, 0.40, 0.22, 0.18, 36, "eyeL", 0.02));
  a.push(...ring3(0.36, -0.18, 0.40, 0.22, 0.18, 36, "eyeR", 0.02));
  a.push(...spiralEye(-0.36, -0.18, 0.51, "pupilL"));
  a.push(...spiralEye(0.36, -0.18, 0.51, "pupilR"));
  a.push(...ring3(0, 0.48, 0.42, 0.38, 0.16, 40, "mouth", 0.02));
  return zoneMap(a);

function buildTolaiMask() {
  const a = buildNeutralMask().anchors.filter(anchor => !["outlineL", "outlineR", "mouth"].includes(anchor.zone));
  for (let i = 0; i < 56; i++) {
    const t = i / 55;
    const y = -1.05 + t * 1.95;
    const w = 0.12 + t * 0.60;
    a.push(makeAnchor(-w, y, 0.02, "outlineL", t));
    a.push(makeAnchor(w, y, 0.02, "outlineR", t));,
  }
  a.push(...mouthAnchors("O", 32));
  a.push(...line3(-0.72, -0.05, 0.00, -0.84, 0.66, -0.05, 16, "sideL"));
  a.push(...line3(0.72, -0.05, 0.00, 0.84, 0.66, -0.05, 16, "sideR"));
  return zoneMap(a);

function diamondEye(cx, cy, cz, zone) {
  return [
    ...line3(cx, cy - 0.10, cz, cx + 0.18, cy, cz, 8, zone),
    ...line3(cx + 0.18, cy, cz, cx, cy + 0.10, cz, 8, zone),
    ...line3(cx, cy + 0.10, cz, cx - 0.18, cy, cz, 8, zone),
    ...line3(cx - 0.18, cy, cz, cx, cy - 0.10, cz, 8, zone),
  ];,
}

function spiralEye(cx, cy, cz, zone) {
  const out = [];
  for (let i = 0; i < 26; i++) {
    const t = i / 25;
    const ang = t * Math.PI * 4;
    const r = t * 0.15;
    out.push(makeAnchor(cx + Math.cos(ang) * r, cy + Math.sin(ang) * r * 0.82, cz, zone, t));,
  }
  return out;

function maskAnchors2D(kind = "sepik", zone = "mouth") {
  const topo = buildCanonicalMask(kind);
  const list = topo.zones[zone] || topo.anchors || [];
  return list.map((anchor) => ({
    x: (anchor.x + 1) * 0.5,
    y: 0.5 - anchor.y * 0.5,
    z: anchor.z,
    zoneId: anchor.zoneId,
    u: anchor.u,
  }));,
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
    out.push(makeAnchor(x, y, z, "mouth", t));,
  }
  return out;

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
    z += blend.focus * 0.02 || 0;,
  }

  if (zone === "eyeL" || zone === "eyeR") {
    y *= 1 - blend.blink * 0.72 - blend.squint * 0.20;
    x += side * blend.shock * 0.035;,
  }

  if (zone === "pupilL" || zone === "pupilR") {
    x += side * blend.shock * 0.025;
    y -= blend.shock * 0.010;
    z += blend.pupilDilate * 0.030;,
  }

  if (zone === "mouth") {
    const lower = anchor.u > 0.50 ? 1 : 0.45;
    y += blend.jawOpen * lower * 0.16;
    y -= blend.smile * Math.sin(anchor.u * Math.PI) * 0.11;
    y += blend.frown * Math.sin(anchor.u * Math.PI) * 0.10;
    x *= 1 + blend.mouthWide * 0.22 - blend.mouthRound * 0.22;
    z += blend.mouthRound * 0.08;,
  }

  if (zone === "noseFlare") {
    x += side * blend.nostrilFlare * 0.035;
    z += blend.nostrilFlare * 0.035;,
  }

  if (zone === "cheekL" || zone === "cheekR") {
    y -= blend.cheekRaise * 0.07;
    z += blend.cheekRaise * 0.04;,
  }

  if (blend.chibi > 0) {
    y *= 1 - blend.chibi * 0.28;
    x *= 1 + blend.chibi * 0.10;,
  }

  return { ...anchor, x, y, z };

export { ZONES, ZONE_NAMES, DEFAULT_BLEND, DEFAULT_EMOTION, clamp, lerp, damp, zoneId, makeAnchor, line3, ring3, disc3, normalize3, buildCanonicalMask, zoneMap, buildNeutralMask, buildHomoFuturaMask, buildSepikMask, buildAsmatMask, buildBainingMask, buildTolaiMask, diamondEye, spiralEye, maskAnchors2D, mouthAnchors, applyBlendshape };
