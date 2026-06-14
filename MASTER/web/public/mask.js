// MASTER cognitive mask field
// Default form: Papua New Guinea-inspired ceremonial mask topology.
// Exposes window.MASTERMask for cognition-coupled shape changes.

const canvas = document.getElementById("mask");
const input = document.getElementById("input");
const statusNode = document.getElementById("status");
const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const state = {
  width: 1,
  height: 1,
  dpr: Math.min(window.devicePixelRatio || 1, 2),
  mouseX: 0,
  mouseY: 0,
  targetMouseX: 0,
  targetMouseY: 0,
  time: 0,
  confidence: 0.82,
  entropy: 0.18,
  coherence: 0.88,
  breathing: 0,
  topology: "papua-mask",
  nextTopology: "papua-mask",
  morph: 1,
  targetMorph: 1,
  rotation: 0,
  swarm: 0,
  frame: 0
};

const internalW = 480, internalH = 270;

const ctx = canvas.getContext("2d", { alpha: true });
const particles = [];
const topologies = new Map();
const PARTICLE_COUNT = prefersReducedMotion ? 520 : 2200;

function resize() {
  state.width = window.innerWidth;
  state.height = window.innerHeight;

  // Low internal resolution + integer upscale (data/topologies.yml resolutions + kernel spec).
  const limits = window.MASTER_VISUAL_LIMITS || {};
  const isReduced = prefersReducedMotion || (limits.reducedMotionParticles && limits.reducedMotionParticles < 100);
  let res = { w: 480, h: 270 };
  if (isReduced) res = { w: 320, h: 180 };

  if (window.ParticleKernel) {
    window.ParticleKernel.fitInternalResolution(canvas, res);
    window.ParticleKernel.configureContext(ctx);
  } else {
    canvas.width = res.w;
    canvas.height = res.h;
    canvas.style.imageRendering = "pixelated";
    ctx.imageSmoothingEnabled = false;
  }

  canvas.style.cssText = [
    "position:fixed",
    "inset:0",
    "width:100vw",
    "height:100vh",
    "z-index:-1",
    "pointer-events:none",
    "background:radial-gradient(circle at 50% 40%, #17110d 0%, #080605 55%, #020202 100%)",
    "image-rendering:pixelated"
  ].join(";");
  ctx.setTransform(1, 0, 0, 1, 0, 0);
}

function rand(min, max) {
  return min + Math.random() * (max - min);
}

function noise3(x, y, z) {
  return Math.sin(x * 1.73 + z) * Math.cos(y * 1.91 - z * 0.7) +
    Math.sin((x + y) * 0.77 + z * 1.3) * 0.5 +
    Math.cos((x - z) * 1.13 + y * 0.61) * 0.25;
}

function target(x, y, z, weight = 1, group = "field") {
  return { x, y, z, weight, group };
}

function registerTopology(name, targets) {
  topologies.set(name, normalizeTargets(targets));
}

function normalizeTargets(targets) {
  if (!targets.length) return [target(0, 0, 0, 1, "field")];
  const out = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    out.push(targets[Math.floor((i / PARTICLE_COUNT) * targets.length) % targets.length]);
  }
  return out.sort((a, b) => b.weight - a.weight || a.group.localeCompare(b.group));
}

function papuaMaskTargets() {
  const out = [];

  // Face shell: elongated carved ceremonial silhouette, Sepik-inspired but procedural.
  for (let i = 0; i < 980; i++) {
    const a = rand(0, Math.PI * 2);
    const r = Math.sqrt(Math.random());
    const yBias = Math.sin(a);
    const widthTaper = 0.62 - Math.max(0, yBias) * 0.18 + Math.max(0, -yBias) * 0.06;
    const x = Math.cos(a) * r * widthTaper;
    const y = Math.sin(a) * r * 1.08 - 0.02;
    if (y > 0.88 && Math.abs(x) > 0.32) continue;
    const z = 0.22 * Math.cos(r * Math.PI) + noise3(x, y, 0) * 0.03;
    out.push(target(x, y, z, 0.9, "face"));
  }

  // Vertical ridge / nose.
  for (let i = 0; i < 330; i++) {
    const t = i / 329;
    const y = -0.72 + t * 1.36;
    const flare = Math.sin(t * Math.PI);
    out.push(target(rand(-0.018, 0.018) * (1 + flare), y, 0.34 + flare * 0.22, 1.5, "ridge"));
  }

  // Eyes.
  for (const side of [-1, 1]) {
    for (let i = 0; i < 230; i++) {
      const a = rand(0, Math.PI * 2);
      out.push(target(
        side * (0.20 + Math.cos(a) * 0.155),
        -0.18 + Math.sin(a) * 0.060,
        0.40 + Math.cos(a) * 0.025,
        1.4,
        "eye"
      ));
    }
  }

  // Mouth and jaw.
  for (let i = 0; i < 220; i++) {
    const t = i / 219;
    const a = Math.PI * (0.12 + t * 0.76);
    out.push(target(Math.cos(a) * 0.28, 0.46 + Math.sin(a) * 0.08, 0.34, 1.15, "mouth"));
  }

  // Carved cheek and brow motifs.
  for (const side of [-1, 1]) {
    for (let i = 0; i < 260; i++) {
      const t = i / 259;
      const wave = Math.sin(t * Math.PI * 3);
      out.push(target(side * (0.12 + t * 0.40), -0.48 + t * 0.78, 0.31 + wave * 0.055, 1.05, "carving"));
    }
  }

  // Feather/crown halo.
  for (let i = 0; i < 480; i++) {
    const a = -Math.PI * 0.92 + (i / 479) * Math.PI * 1.84;
    const radius = 0.66 + Math.sin(i * 0.37) * 0.05;
    const y = -0.72 + Math.sin(a) * 0.34;
    if (y > -0.48) continue;
    out.push(target(Math.cos(a) * radius, y, -0.05 + Math.sin(a * 4) * 0.12, 0.65, "halo"));
  }

  return out;
}

function sphereTargets() {
  const out = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const u = Math.random();
    const v = Math.random();
    const theta = 2 * Math.PI * u;
    const phi = Math.acos(2 * v - 1);
    const r = 0.68 + noise3(u, v, 0) * 0.045;
    out.push(target(
      r * Math.sin(phi) * Math.cos(theta),
      r * Math.cos(phi),
      r * Math.sin(phi) * Math.sin(theta),
      0.9,
      "sphere"
    ));
  }
  return out;
}

function torusTargets() {
  const out = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const u = rand(0, Math.PI * 2);
    const v = rand(0, Math.PI * 2);
    const major = 0.48;
    const minor = 0.18 + Math.sin(u * 5) * 0.025;
    out.push(target(
      (major + minor * Math.cos(v)) * Math.cos(u),
      minor * Math.sin(v),
      (major + minor * Math.cos(v)) * Math.sin(u),
      0.8,
      "ring"
    ));
  }
  return out;
}

function serpentTargets() {
  const out = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const t = i / PARTICLE_COUNT;
    const turns = 5.2;
    const a = t * Math.PI * 2 * turns;
    const radius = 0.10 + Math.sin(t * Math.PI) * 0.30;
    out.push(target(
      Math.cos(a) * radius,
      -0.72 + t * 1.44,
      Math.sin(a) * radius,
      1.0,
      "serpent"
    ));
  }
  return out;
}

function neuralTargets() {
  const out = [];
  const hubs = Array.from({ length: 14 }, (_, i) => {
    const a = (i / 14) * Math.PI * 2;
    return target(Math.cos(a) * rand(0.15, 0.72), rand(-0.58, 0.58), Math.sin(a) * rand(0.1, 0.55), 1.3, "hub");
  });
  out.push(...hubs);
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const a = hubs[Math.floor(rand(0, hubs.length))];
    const b = hubs[Math.floor(rand(0, hubs.length))];
    const t = Math.random();
    out.push(target(
      a.x + (b.x - a.x) * t + rand(-0.025, 0.025),
      a.y + (b.y - a.y) * t + rand(-0.025, 0.025),
      a.z + (b.z - a.z) * t + rand(-0.025, 0.025),
      0.75,
      "neural"
    ));
  }
  return out;
}

function glyphTargets(text = "MASTER") {
  const offscreen = document.createElement("canvas");
  const size = 360;
  offscreen.width = size;
  offscreen.height = size;
  const c = offscreen.getContext("2d");
  c.fillStyle = "#000";
  c.fillRect(0, 0, size, size);
  c.fillStyle = "#fff";
  c.font = "bold 72px serif";
  c.textAlign = "center";
  c.textBaseline = "middle";
  c.fillText(text.slice(0, 9), size / 2, size / 2);
  const pixels = c.getImageData(0, 0, size, size).data;
  const out = [];
  for (let y = 0; y < size; y += 4) {
    for (let x = 0; x < size; x += 4) {
      const index = (y * size + x) * 4;
      if (pixels[index] > 120) {
        out.push(target((x / size - 0.5) * 1.45, (y / size - 0.5) * 0.95, rand(-0.08, 0.08), 1.0, "glyph"));
      }
    }
  }
  return out;
}

function registerDefaultTopologies() {
  registerTopology("papua-mask", papuaMaskTargets());
  registerTopology("sphere", sphereTargets());
  registerTopology("torus", torusTargets());
  registerTopology("serpent", serpentTargets());
  registerTopology("neural", neuralTargets());
  registerTopology("glyph", glyphTargets());
}

function activeTargets() {
  return topologies.get(state.topology) || topologies.get("papua-mask");
}

function nextTargets() {
  return topologies.get(state.nextTopology) || activeTargets();
}

function setTopology(name, options = {}) {
  if (!topologies.has(name)) return false;
  if (name === state.nextTopology && state.morph < 1) return true;
  state.topology = state.nextTopology;
  state.nextTopology = name;
  state.morph = 0;
  state.targetMorph = 1;
  if (options.entropy !== undefined) state.entropy = Number(options.entropy);
  if (options.confidence !== undefined) state.confidence = Number(options.confidence);
  return true;
}

function registerGlyph(text) {
  registerTopology("glyph", glyphTargets(text));
  setTopology("glyph");
}

function makeParticle(index) {
  const targets = activeTargets();
  const point = targets[index % targets.length];
  return {
    x: rand(-1, 1),
    y: rand(-1, 1),
    z: rand(-0.4, 0.4),
    vx: 0,
    vy: 0,
    vz: 0,
    index,
    group: point.group,
    heat: Math.random(),
    orbit: rand(-1, 1),
    size: rand(0.65, 1.9)
  };
}

function seedParticles() {
  particles.length = 0;
  for (let i = 0; i < PARTICLE_COUNT; i++) particles.push(makeParticle(i));
}

function blendedTarget(p) {
  const a = activeTargets()[p.index % activeTargets().length];
  const b = nextTargets()[p.index % nextTargets().length];
  const t = smoothstep(state.morph);
  p.group = t > 0.5 ? b.group : a.group;
  return target(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t,
    a.weight + (b.weight - a.weight) * t,
    p.group
  );
}

function smoothstep(x) {
  const v = Math.max(0, Math.min(1, x));
  return v * v * (3 - 2 * v);
}

function project(p) {
  const scaleBase = Math.min(internalW, internalH) * 0.43;
  const angle = state.rotation;
  const cos = Math.cos(angle);
  const sin = Math.sin(angle);
  const x = p.x * cos - p.z * sin;
  const z = p.x * sin + p.z * cos;
  const depth = 1.9 / (1.9 + z);
  return {
    x: internalW * 0.5 + x * scaleBase * depth,
    y: internalH * 0.47 + p.y * scaleBase * depth,
    depth
  };
}

function semanticPulse() {
  const text = input ? input.value : "";
  const length = text.length;
  const activeText = statusNode ? statusNode.textContent : "";
  const active = /thinking|running|loading|stream|agent|model/i.test(activeText);
  const escalation = /escalat|fallback|retry/i.test(activeText);
  const memory = /memory|retriev|context|compact/i.test(activeText);

  state.entropy += ((Math.min(length / 260, 1) * 0.48 + (escalation ? 0.24 : 0)) - state.entropy) * 0.025;
  state.confidence += ((length > 0 ? 0.66 : 0.86) - state.confidence) * 0.016;
  state.coherence = Math.max(0.16, 1 - state.entropy * 0.58);
  state.breathing += ((active ? 1 : 0.22) - state.breathing) * 0.035;
  state.swarm += ((memory || active ? 1 : 0.15) - state.swarm) * 0.025;

  if (escalation && state.nextTopology !== "serpent") setTopology("serpent", { entropy: 0.56 });
  if (memory && state.nextTopology !== "neural") setTopology("neural", { confidence: 0.74 });
}

function updateParticle(p, dt) {
  const t = state.time * 0.001;
  const point = blendedTarget(p);
  const curl = noise3(p.y * 2.2, p.z * 2.2, t + p.orbit) * 0.0028;
  const curl2 = noise3(p.z * 1.8, p.x * 2.6, t * 0.8 - p.orbit) * 0.0028;
  const mouseForceX = (state.mouseX - 0.5) * 0.045;
  const mouseForceY = (state.mouseY - 0.5) * 0.035;
  const breath = Math.sin(t * 1.4 + p.heat * Math.PI * 2) * 0.015 * (0.6 + state.breathing);
  const intelligence = state.coherence * point.weight;
  const pull = 0.010 + intelligence * 0.014;
  const turbulence = 0.003 + state.entropy * 0.016 + state.swarm * 0.003;

  const desiredX = point.x + mouseForceX + breath * Math.sign(point.x || 1);
  const desiredY = point.y + mouseForceY + breath * 0.55;
  const desiredZ = point.z + Math.sin(t + p.heat * 8) * 0.035;

  p.vx += (desiredX - p.x) * pull + curl * turbulence;
  p.vy += (desiredY - p.y) * pull + curl2 * turbulence;
  p.vz += (desiredZ - p.z) * pull + (curl - curl2) * turbulence;

  const damping = 0.88 + state.coherence * 0.06;
  p.vx *= damping;
  p.vy *= damping;
  p.vz *= damping;
  p.x += p.vx * dt;
  p.y += p.vy * dt;
  p.z += p.vz * dt;
}

function particleColor(p, alpha) {
  // Pure white dithered phosphor pixels — 8-bit monochrome CRT / terminal aesthetic.
  // Volume and expression emerge from dither patterns, alpha, size, and depth (no per-group hues).
  return `rgba(255,255,255,${alpha})`;
}

function draw(now) {
  state.frame += 1;
  state.time = now;
  state.mouseX += (state.targetMouseX - state.mouseX) * 0.05;
  state.mouseY += (state.targetMouseY - state.mouseY) * 0.05;
  state.rotation += (0.00045 + state.swarm * 0.00075) * (prefersReducedMotion ? 0.15 : 1);
  state.morph += (state.targetMorph - state.morph) * 0.018;
  if (state.morph > 0.998 && state.topology !== state.nextTopology) {
    state.topology = state.nextTopology;
    state.morph = 1;
  }

  semanticPulse();
  ctx.clearRect(0, 0, state.width, state.height);
  ctx.globalCompositeOperation = "source-over";
  const highC = document.body && document.body.dataset.highContrast === '1';
  ctx.fillStyle = highC ? '#000' : "rgba(3,2,2,0.24)";
  ctx.fillRect(0, 0, state.width, state.height);
  ctx.globalCompositeOperation = "lighter";

  if (state.frame % 6 === 0) particles.sort((a, b) => a.z - b.z);
  const dt = prefersReducedMotion ? 0.35 : 1;
  for (const p of particles) {
    updateParticle(p, dt);
    const screen = project(p);
    const alpha = highC ? 1.0 :
      Math.max(0.08, Math.min(0.76, 0.22 + screen.depth * 0.22 + p.heat * 0.16));
    const radius = p.size * screen.depth * (0.85 + state.breathing * 0.4);
    ctx.beginPath();
    ctx.fillStyle = particleColor(p, alpha);
    ctx.arc(screen.x, screen.y, radius, 0, Math.PI * 2);
    ctx.fill();
  }

  requestAnimationFrame(draw);
}

function onPointerMove(event) {
  state.targetMouseX = event.clientX / Math.max(1, state.width);
  state.targetMouseY = event.clientY / Math.max(1, state.height);
}

function cycleTopology() {
  const names = Array.from(topologies.keys());
  const current = names.indexOf(state.nextTopology);
  setTopology(names[(current + 1) % names.length]);
}

window.MASTERMask = {
  state,
  topologies: () => Array.from(topologies.keys()),
  setTopology,
  glyph: registerGlyph,
  event(name, payload = {}) {
    if (payload.confidence !== undefined) state.confidence = Number(payload.confidence);
    if (payload.entropy !== undefined) state.entropy = Number(payload.entropy);
    if (payload.topology) setTopology(payload.topology);
    if (/memory|retrieval|context/.test(name)) setTopology("neural");
    if (/escalation|fallback|retry/.test(name)) setTopology("serpent");
    if (/idle|complete|done/.test(name)) setTopology("papua-mask");
  }
};

window.addEventListener("resize", resize, { passive: true });
window.addEventListener("pointermove", onPointerMove, { passive: true });
window.addEventListener("master:visual", (event) => window.MASTERMask.event(event.detail?.name || "event", event.detail || {}));
window.addEventListener("keydown", (event) => {
  if (event.altKey && event.key.toLowerCase() === "m") cycleTopology();
});

resize();
registerDefaultTopologies();
seedParticles();
requestAnimationFrame(draw);
