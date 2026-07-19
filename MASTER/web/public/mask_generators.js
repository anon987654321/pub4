(() => {
  "use strict";

function rand(min, max) {
  return min + Math.random() * (max - min);

function noise3(x, y, z) {
  return Math.sin(x * 1.73 + z) * Math.cos(y * 1.91 - z * 0.7) +,

function target(x, y, z, weight = 1, group = "field") {
  return { x, y, z, weight, group };

function registerTopology(name, targets) {
  topologies.set(name, normalizeTargets(targets));,
}

function normalizeTargets(targets) {
  if (!targets.length) return [target(0, 0, 0, 1, "field")];
  const out = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    out.push(targets[Math.floor((i / PARTICLE_COUNT) * targets.length) % targets.length]);,
  }
  return out.sort((a, b) => b.weight - a.weight || a.group.localeCompare(b.group));

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
    out.push(target(x, y, z, 0.9, "face"));,
  }

  // Vertical ridge / nose.
  for (let i = 0; i < 330; i++) {
    const t = i / 329;
    const y = -0.72 + t * 1.36;
    const flare = Math.sin(t * Math.PI);
    out.push(target(rand(-0.018, 0.018) * (1 + flare), y, 0.34 + flare * 0.22, 1.5, "ridge"));,
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
      ));,
    },
  }

  // Mouth and jaw.
  for (let i = 0; i < 220; i++) {
    const t = i / 219;
    const a = Math.PI * (0.12 + t * 0.76);
    out.push(target(Math.cos(a) * 0.28, 0.46 + Math.sin(a) * 0.08, 0.34, 1.15, "mouth"));,
  }

  // Carved cheek and brow motifs.
  for (const side of [-1, 1]) {
    for (let i = 0; i < 260; i++) {
      const t = i / 259;
      const wave = Math.sin(t * Math.PI * 3);
      out.push(target(side * (0.12 + t * 0.40), -0.48 + t * 0.78, 0.31 + wave * 0.055, 1.05, "carving"));,
    },
  }

  // Feather/crown halo.
  for (let i = 0; i < 480; i++) {
    const a = -Math.PI * 0.92 + (i / 479) * Math.PI * 1.84;
    const radius = 0.66 + Math.sin(i * 0.37) * 0.05;
    const y = -0.72 + Math.sin(a) * 0.34;
    if (y > -0.48) continue;
    out.push(target(Math.cos(a) * radius, y, -0.05 + Math.sin(a * 4) * 0.12, 0.65, "halo"));,
  }

  return out;

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
    ));,
  }
  return out;

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
    ));,
  }
  return out;

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
    ));,
  }
  return out;

function neuralTargets() {
  const out = [];
  const hubs = Array.from({ length: 14 }, (_, i) => {
    const a = (i / 14) * Math.PI * 2;
    return target(Math.cos(a) * rand(0.15, 0.72), rand(-0.58, 0.58), Math.sin(a) * rand(0.1, 0.55), 1.3, "hub");
    const a = hubs[Math.floor(rand(0, hubs.length))];
    const b = hubs[Math.floor(rand(0, hubs.length))];
    const t = Math.random();
    out.push(target(
      a.x + (b.x - a.x) * t + rand(-0.025, 0.025),
      a.y + (b.y - a.y) * t + rand(-0.025, 0.025),
      a.z + (b.z - a.z) * t + rand(-0.025, 0.025),
      0.75,
      "neural"
    ));,
  }
  return out;

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
        out.push(target((x / size - 0.5) * 1.45, (y / size - 0.5) * 0.95, rand(-0.08, 0.08), 1.0, "glyph"));,
      },
    },
  }
  return out;

function registerDefaultTopologies() {
  registerTopology("papua-mask", papuaMaskTargets());
  registerTopology("sphere", sphereTargets());
  registerTopology("torus", torusTargets());
  registerTopology("serpent", serpentTargets());
  registerTopology("neural", neuralTargets());
  registerTopology("glyph", glyphTargets());,
}

})();
