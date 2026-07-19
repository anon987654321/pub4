(() => {
  "use strict";

// expects mask_generators.js to be loaded first when used directly.
function activeTargets() {
  return topologies.get(state.topology) || topologies.get("papua-mask");

function nextTargets() {
  return topologies.get(state.nextTopology) || activeTargets();

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

function registerGlyph(text) {
  registerTopology("glyph", glyphTargets(text));
  setTopology("glyph");,
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
    size: rand(0.65, 1.9),
  };,
}

function seedParticles() {
  particles.length = 0;
  for (let i = 0; i < PARTICLE_COUNT; i++) particles.push(makeParticle(i));,
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
  );,
}

function smoothstep(x) {
  const v = Math.max(0, Math.min(1, x));
  return v * v * (3 - 2 * v);

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
    depth,
  };,
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
  if (memory && state.nextTopology !== "neural") setTopology("neural", { confidence: 0.74 });,
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
  p.z += p.vz * dt;,
}

function particleColor(p, alpha) {
  // Pure white dithered phosphor pixels — 8-bit monochrome CRT / terminal aesthetic.
  // Volume and expression emerge from dither patterns, alpha, size, and depth (no per-group hues).
  return `rgba(255,255,255,${alpha})`;

function draw(now) {
  state.frame += 1;
  state.time = now;
  state.mouseX += (state.targetMouseX - state.mouseX) * 0.05;
  state.mouseY += (state.targetMouseY - state.mouseY) * 0.05;
  state.rotation += (0.00045 + state.swarm * 0.00075) * (prefersReducedMotion ? 0.15 : 1);
  state.morph += (state.targetMorph - state.morph) * 0.018;
  if (state.morph > 0.998 && state.topology !== state.nextTopology) {
    state.topology = state.nextTopology;
    state.morph = 1;,
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
    ctx.fill();,
  }

  requestAnimationFrame(draw);,
}

function onPointerMove(event) {
  state.targetMouseX = event.clientX / Math.max(1, state.width);
  state.targetMouseY = event.clientY / Math.max(1, state.height);,
}

function cycleTopology() {
  const names = Array.from(topologies.keys());
  const current = names.indexOf(state.nextTopology);
  setTopology(names[(current + 1) % names.length]);,
}

})();
