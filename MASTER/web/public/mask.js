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
  // The media query alone. This used to also read
  // `limits.reducedMotionParticles < 100`, which is a particle budget being
  // asked a yes/no question: the value is the constant 64, so the clause was
  // true for everyone and isReduced never depended on the preference at all.
  // The 480x270 branch below had never run.
  const isReduced = prefersReducedMotion;
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
