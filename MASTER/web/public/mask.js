// MASTER cognitive mask field
// Default form: Papua New Guinea-inspired ceremonial mask topology.
// This is a procedural 3D particle field projected onto the existing #mask canvas.

const canvas = document.getElementById("mask");
const input = document.getElementById("input");
const statusNode = document.getElementById("status");

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
  mode: "mask"
};

const ctx = canvas.getContext("2d", { alpha: true });
const particles = [];
const TARGETS = [];
const PARTICLE_COUNT = 1700;

function resize() {
  state.width = window.innerWidth;
  state.height = window.innerHeight;
  canvas.width = Math.floor(state.width * state.dpr);
  canvas.height = Math.floor(state.height * state.dpr);
  canvas.style.cssText = [
    "position:fixed",
    "inset:0",
    "width:100vw",
    "height:100vh",
    "z-index:-1",
    "pointer-events:none",
    "background:radial-gradient(circle at 50% 40%, #17110d 0%, #080605 55%, #020202 100%)"
  ].join(";");
  ctx.setTransform(state.dpr, 0, 0, state.dpr, 0, 0);
}

function rand(min, max) {
  return min + Math.random() * (max - min);
}

function noise3(x, y, z) {
  return Math.sin(x * 1.73 + z) * Math.cos(y * 1.91 - z * 0.7) +
    Math.sin((x + y) * 0.77 + z * 1.3) * 0.5;
}

function addTarget(x, y, z, weight = 1, group = "mask") {
  TARGETS.push({ x, y, z, weight, group });
}

function buildPapuaNewGuineaMaskTargets() {
  TARGETS.length = 0;

  // Face shell: long carved ceremonial silhouette, inspired by Sepik-region mask geometry.
  for (let i = 0; i < 760; i++) {
    const a = rand(0, Math.PI * 2);
    const r = Math.sqrt(Math.random());
    const yBias = Math.sin(a);
    const widthTaper = 0.62 - Math.max(0, yBias) * 0.18 + Math.max(0, -yBias) * 0.06;
    const x = Math.cos(a) * r * widthTaper;
    const y = Math.sin(a) * r * 1.08 - 0.02;
    if (y > 0.88 && Math.abs(x) > 0.32) continue;
    const z = 0.22 * Math.cos(r * Math.PI) + noise3(x, y, 0) * 0.03;
    addTarget(x, y, z, 0.9, "face");
  }

  // Strong vertical ridge / nose.
  for (let i = 0; i < 260; i++) {
    const t = i / 259;
    const y = -0.72 + t * 1.36;
    const flare = Math.sin(t * Math.PI);
    const x = rand(-0.018, 0.018) * (1 + flare);
    const z = 0.34 + flare * 0.22;
    addTarget(x, y, z, 1.5, "ridge");
  }

  // Eyes: almond voids outlined by bright particles.
  for (const side of [-1, 1]) {
    for (let i = 0; i < 180; i++) {
      const a = rand(0, Math.PI * 2);
      const x = side * (0.20 + Math.cos(a) * 0.155);
      const y = -0.18 + Math.sin(a) * 0.060;
      const z = 0.40 + Math.cos(a) * 0.025;
      addTarget(x, y, z, 1.4, "eye");
    }
  }

  // Mouth and jaw carving.
  for (let i = 0; i < 180; i++) {
    const t = i / 179;
    const a = Math.PI * (0.12 + t * 0.76);
    const x = Math.cos(a) * 0.28;
    const y = 0.46 + Math.sin(a) * 0.08;
    const z = 0.34;
    addTarget(x, y, z, 1.15, "mouth");
  }

  // Cheek, brow, and forehead carved motifs.
  for (const side of [-1, 1]) {
    for (let i = 0; i < 200; i++) {
      const t = i / 199;
      const wave = Math.sin(t * Math.PI * 3);
      const x = side * (0.12 + t * 0.40);
      const y = -0.48 + t * 0.78;
      const z = 0.31 + wave * 0.055;
      addTarget(x, y, z, 1.05, "carving");
    }
  }

  // Crown/feather halo, deliberately sparse and flowing.
  for (let i = 0; i < 360; i++) {
    const a = -Math.PI * 0.92 + (i / 359) * Math.PI * 1.84;
    const radius = 0.66 + Math.sin(i * 0.37) * 0.05;
    const x = Math.cos(a) * radius;
    const y = -0.72 + Math.sin(a) * 0.34;
    const z = -0.05 + Math.sin(a * 4) * 0.12;
    if (y > -0.48) continue;
    addTarget(x, y, z, 0.65, "halo");
  }
}

function makeParticle(index) {
  const target = TARGETS[index % TARGETS.length];
  return {
    x: rand(-1, 1),
    y: rand(-1, 1),
    z: rand(-0.4, 0.4),
    vx: 0,
    vy: 0,
    vz: 0,
    target,
    group: target.group,
    heat: Math.random(),
    orbit: rand(-1, 1),
    size: rand(0.65, 1.8)
  };
}

function seedParticles() {
  particles.length = 0;
  for (let i = 0; i < PARTICLE_COUNT; i++) particles.push(makeParticle(i));
}

function project(p) {
  const scaleBase = Math.min(state.width, state.height) * 0.43;
  const depth = 1.8 / (1.8 + p.z);
  return {
    x: state.width * 0.5 + p.x * scaleBase * depth,
    y: state.height * 0.47 + p.y * scaleBase * depth,
    depth
  };
}

function semanticPulse() {
  const text = input ? input.value : "";
  const length = text.length;
  state.entropy += ((Math.min(length / 260, 1) * 0.55) - state.entropy) * 0.025;
  state.confidence += ((length > 0 ? 0.66 : 0.86) - state.confidence) * 0.016;
  state.coherence = 1 - state.entropy * 0.55;

  if (statusNode && statusNode.textContent) {
    const active = /thinking|running|loading|stream|agent|model/i.test(statusNode.textContent);
    state.breathing += ((active ? 1 : 0.22) - state.breathing) * 0.035;
  } else {
    state.breathing += (0.22 - state.breathing) * 0.02;
  }
}

function updateParticle(p, dt) {
  const t = state.time * 0.001;
  const target = p.target;
  const curl = noise3(p.y * 2.2, p.z * 2.2, t + p.orbit) * 0.0028;
  const curl2 = noise3(p.z * 1.8, p.x * 2.6, t * 0.8 - p.orbit) * 0.0028;

  const mouseForceX = (state.mouseX - 0.5) * 0.045;
  const mouseForceY = (state.mouseY - 0.5) * 0.035;
  const breath = Math.sin(t * 1.4 + p.heat * Math.PI * 2) * 0.015 * (0.6 + state.breathing);
  const intelligence = state.coherence * target.weight;
  const pull = 0.010 + intelligence * 0.014;
  const turbulence = 0.003 + state.entropy * 0.016;

  const desiredX = target.x + mouseForceX + breath * Math.sign(target.x || 1);
  const desiredY = target.y + mouseForceY + breath * 0.55;
  const desiredZ = target.z + Math.sin(t + p.heat * 8) * 0.035;

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
  switch (p.group) {
    case "eye": return `rgba(245,220,160,${alpha})`;
    case "ridge": return `rgba(205,62,37,${alpha})`;
    case "halo": return `rgba(235,190,95,${alpha * 0.72})`;
    case "carving": return `rgba(180,80,45,${alpha})`;
    case "mouth": return `rgba(225,210,175,${alpha})`;
    default: return `rgba(210,145,78,${alpha})`;
  }
}

let previous = performance.now();
function frame(now) {
  const dt = Math.min(2, (now - previous) / 16.67);
  previous = now;
  state.time = now;
  state.mouseX += (state.targetMouseX - state.mouseX) * 0.05;
  state.mouseY += (state.targetMouseY - state.mouseY) * 0.05;
  semanticPulse();

  ctx.clearRect(0, 0, state.width, state.height);
  ctx.globalCompositeOperation = "source-over";
  ctx.fillStyle = "rgba(3,2,2,0.24)";
  ctx.fillRect(0, 0, state.width, state.height);
  ctx.globalCompositeOperation = "lighter";

  particles.sort((a, b) => a.z - b.z);
  for (const p of particles) {
    updateParticle(p, dt);
    const screen = project(p);
    const alpha = Math.max(0.08, Math.min(0.72, 0.22 + screen.depth * 0.22 + p.heat * 0.16));
    const radius = p.size * screen.depth * (0.85 + state.breathing * 0.4);
    ctx.beginPath();
    ctx.fillStyle = particleColor(p, alpha);
    ctx.arc(screen.x, screen.y, radius, 0, Math.PI * 2);
    ctx.fill();
  }

  requestAnimationFrame(frame);
}

function onPointerMove(event) {
  state.targetMouseX = event.clientX / Math.max(1, state.width);
  state.targetMouseY = event.clientY / Math.max(1, state.height);
}

window.addEventListener("resize", resize, { passive: true });
window.addEventListener("pointermove", onPointerMove, { passive: true });

resize();
buildPapuaNewGuineaMaskTargets();
seedParticles();
requestAnimationFrame(frame);
