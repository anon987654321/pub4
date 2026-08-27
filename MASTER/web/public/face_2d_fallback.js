// Lightweight 2D placeholder while Three.js loads. Never touches #face — a 2d context
// on that canvas permanently blocks WebGLRenderer from initializing (dead tap / black face).
"use strict";

let fallbackFrame = null;

function stop2DFallback() {
  if (fallbackFrame) {
    cancelAnimationFrame(fallbackFrame);
    fallbackFrame = null;
  }
  const canvas = document.getElementById("face-2d-fallback");
  if (canvas) canvas.remove();
}

function ensureFallbackCanvas() {
  let canvas = document.getElementById("face-2d-fallback");
  if (canvas) return canvas;
  canvas = document.createElement("canvas");
  canvas.id = "face-2d-fallback";
  canvas.setAttribute("aria-hidden", "true");
  canvas.style.cssText = "position:fixed;inset:0;width:100%;height:100%;z-index:1;pointer-events:none;background:#000";
  const face = document.getElementById("face");
  if (face?.parentNode) face.parentNode.insertBefore(canvas, face.nextSibling);
  else document.body.appendChild(canvas);
  return canvas;
}

function start2DFallback() {
  const canvas = ensureFallbackCanvas();
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  stop2DFallback();

  // Anatomical point cloud, used directly as particle targets -- built once
  // per resize, not per frame. Adapted from face3d_geometry.js's
  // buildHomoFuturaMask() (the "evolved-human" anatomical rig: outline,
  // crown, brow, eye, pupil, nose, mouth, chin, cheek zones via line3/ring3/
  // disc3 point generators) rather than hand-rolled bezier curves, since
  // that geometry already existed and was more anatomically considered than
  // a first pass would be. face3d's WebGL renderer/blendshape rig around it
  // was not ported -- only the static point layout, which is all a particle
  // field needs. See DECISIONS.md-adjacent MASTER/web/CLAUDE.md: the real
  // WebGL face is "the wireframe mesh", so tracing wireframe-style anatomy
  // (not a filled illustration) keeps this placeholder visually continuous
  // with what it's standing in for.
  let particles = [];

  const line3 = (x0, y0, z0, x1, y1, z1, n) => {
    const out = [];
    for (let i = 0; i < n; i += 1) {
      const t = n > 1 ? i / (n - 1) : 0;
      out.push([x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t]);
    }
    return out;
  };

  const ring3 = (cx, cy, cz, rx, ry, n, zWave = 0) => {
    const out = [];
    for (let i = 0; i < n; i += 1) {
      const a = (i / n) * Math.PI * 2;
      out.push([cx + Math.cos(a) * rx, cy + Math.sin(a) * ry, cz + Math.sin(a * 2) * zWave]);
    }
    return out;
  };

  const disc3 = (cx, cy, cz, r, n) => {
    const out = [];
    const golden = Math.PI * (3 - Math.sqrt(5));
    for (let i = 0; i < n; i += 1) {
      const t = (i + 0.5) / n;
      const rr = r * Math.sqrt(t);
      const a = i * golden;
      out.push([cx + Math.cos(a) * rr, cy + Math.sin(a) * rr, cz]);
    }
    return out;
  };

  const mouthAnchors = (n) => {
    const out = [];
    for (let i = 0; i < n; i += 1) {
      const t = n > 1 ? i / (n - 1) : 0;
      out.push([(t - 0.5) * 2 * 0.34, 0.58, 0.42]);
    }
    return out;
  };

  // buildHomoFuturaMask, trimmed to the anchor positions only (drops the
  // zone/blendshape rig -- unused by a static particle field).
  const buildAnchors = () => {
    const a = [];
    for (let i = 0; i < 80; i += 1) {
      const t = i / 79;
      const y = -1.02 + t * 1.92;
      const w = 0.14 + 0.46 * Math.sin(t * Math.PI);
      const z = 0.06 * Math.sin(t * Math.PI);
      a.push([-w, y, z], [w, y, z]);
    }
    for (let i = 0; i < 14; i += 1) {
      const t = (i - 6.5) / 6.5;
      a.push(...line3(t * 0.06, -0.82, 0.16, t * 0.14, -1.18 - Math.abs(t) * 0.10, 0.08, 8));
    }
    a.push(...line3(-0.36, -0.26, 0.20, -0.10, -0.20, 0.30, 12));
    a.push(...line3(0.10, -0.20, 0.30, 0.36, -0.26, 0.20, 12));
    a.push(...ring3(-0.27, -0.12, 0.40, 0.15, 0.09, 32, 0.012));
    a.push(...ring3(0.27, -0.12, 0.40, 0.15, 0.09, 32, 0.012));
    a.push(...disc3(-0.27, -0.12, 0.48, 0.048, 10));
    a.push(...disc3(0.27, -0.12, 0.48, 0.048, 10));
    a.push(...line3(0, -0.30, 0.42, 0, 0.28, 0.52, 24));
    a.push(...ring3(-0.05, 0.34, 0.50, 0.030, 0.018, 6));
    a.push(...ring3(0.05, 0.34, 0.50, 0.030, 0.018, 6));
    a.push(...mouthAnchors(28));
    a.push(...line3(-0.10, 0.68, 0.14, 0.10, 0.68, 0.14, 8));
    a.push(...disc3(-0.34, 0.20, 0.22, 0.042, 8));
    a.push(...disc3(0.34, 0.20, 0.22, 0.042, 8));
    return a;
  };

  const ANCHORS = buildAnchors();
  // Structural landmarks for the bio-luminescent accent nodes -- outer brow
  // corners, cheekbones, chin -- expressed in the same anchor unit space.
  const ACCENT_ANCHORS = [[-0.36, -0.26, 0.20], [0.36, -0.26, 0.20], [-0.34, 0.20, 0.22], [0.34, 0.20, 0.22], [0, 0.68, 0.14]];

  const project = (anchor, cx, cy, sx, sy) => [cx + anchor[0] * sx, cy + anchor[1] * sy, anchor[2]];

  const syncParticles = (targets, w, h) => {
    if (particles.length !== targets.length) {
      particles = targets.map(([tx, ty, z]) => ({
        x: Math.random() * w,
        y: Math.random() * h,
        tx,
        ty,
        z,
        seed: Math.random() * Math.PI * 2,
      }));
    } else {
      targets.forEach(([tx, ty, z], i) => {
        particles[i].tx = tx;
        particles[i].ty = ty;
        particles[i].z = z;
      });
    }
  };

  let accents = [];

  const resize = () => {
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.floor(canvas.clientWidth * ratio));
    canvas.height = Math.max(1, Math.floor(canvas.clientHeight * ratio));
    const cx = canvas.width * 0.5;
    const cy = canvas.height * 0.44;
    const sx = canvas.width * 0.23 * 1.7;
    const sy = canvas.height * 0.34;
    syncParticles(ANCHORS.map((anchor) => project(anchor, cx, cy, sx, sy)), canvas.width, canvas.height);
    accents = ACCENT_ANCHORS.map((anchor) => project(anchor, cx, cy, sx, sy));
  };
  resize();
  window.addEventListener("resize", resize);

  let phase = 0;
  // Warp-tunnel depth rings, cheapest possible version of the effect: a
  // handful of native stroke() calls (GPU-composited path draws), not
  // per-pixel plotting. This runs on a shared 1-vCPU box alongside the
  // real face/chat/TTS once it boots, so frame cost matters more here
  // than almost anywhere else in the runtime -- stay far under what a
  // dedicated page (e.g. brgen's radio tunnel) can afford.
  const TUNNEL_RINGS = 5;
  const TUNNEL_SIDES = 10;
  const rings = Array.from({ length: TUNNEL_RINGS }, (_, i) => ({
    z: i / TUNNEL_RINGS,
  }));

// No tunnel. It drew polygon rings behind the face — moveTo/lineTo strokes, a
// dozen of them, at the exact moment the face itself is nothing but 1px points.
// Operator, 2026-08-27: lines between the dots and lines in the background are
// both wrong, and neither is brutalist. The face is points; the background is
// nothing.

  const draw = () => {
    if (window.MASTER_FACE?.startEverything) {
      stop2DFallback();
      return;
    }

    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    const breath = 0.5 + 0.5 * Math.sin(phase * 0.9);
    const grad = ctx.createRadialGradient(w * 0.5, h * 0.45, 0, w * 0.5, h * 0.45, w * 0.42);
    grad.addColorStop(0, `rgba(28,26,24,${0.55 + breath * 0.08})`);
    grad.addColorStop(0.55, "#121110");
    grad.addColorStop(1, "#000000");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    // Single white pixel particles, scattered on first build, easing toward
    // their target position on the anatomical point cloud every frame --
    // slow enough to read as flying/assembling, not snapping into place.
    // Same particle objects persist across resizes (syncParticles just
    // updates tx/ty/z), so a resize reflows the field instead of
    // re-scattering it. z (depth, from the source anchor -- higher is
    // further forward, e.g. nose/mouth vs. the outline/crown at the back)
    // gives a cheap depth-of-field cue: nothing extra to compute, the value
    // was already carried along for free.
    const settleAlpha = 0.55 + breath * 0.25;
    ctx.fillStyle = "#fff";
    particles.forEach((p) => {
      p.x += (p.tx - p.x) * 0.02;
      p.y += (p.ty - p.y) * 0.02;
      const twinkle = 0.5 + 0.5 * Math.sin(phase * 2 + p.seed);
      const depth = 0.55 + (p.z || 0) * 0.7;
      ctx.globalAlpha = settleAlpha * depth * (0.6 + twinkle * 0.4);
      ctx.fillRect(Math.round(p.x), Math.round(p.y), 1, 1);
    });
    ctx.globalAlpha = 1;

    // Bio-luminescent accent nodes at structural landmarks (brow/cheek/chin) --
    // the one "future human" flourish, kept small and few so it reads as
    // augmentation, not decoration.
    const glow = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(phase * 1.3));
    ctx.fillStyle = `rgba(110,170,200,${(glow * 0.8).toFixed(3)})`;
    accents.forEach(([ax, ay]) => {
      ctx.beginPath();
      ctx.arc(ax, ay, Math.max(1, w * 0.0022), 0, Math.PI * 2);
      ctx.fill();
    });

    phase += 0.02;
    if (!document.hidden) fallbackFrame = requestAnimationFrame(draw);
  };

  draw();
}

window.start2DFallback = start2DFallback;
window.stop2DFallback = stop2DFallback;

if (window._primerFired) start2DFallback();
else window.addEventListener("primer:ready", start2DFallback, { once: true });
