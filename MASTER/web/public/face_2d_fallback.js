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

  // Anatomical wireframe head, built once per resize (not per frame) as
  // Path2D so the per-frame cost stays a handful of stroke(path) calls.
  // Wireframe, not filled illustration, deliberately: the real WebGL face
  // this placeholder stands in for is itself described as "the wireframe
  // mesh" (see MASTER/web/CLAUDE.md) -- this keeps the placeholder visually
  // continuous with the thing it's waiting on, instead of a mismatched style.
  let head = null;

  const smoothPath = (points) => {
    const path = new Path2D();
    path.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length - 1; i += 1) {
      const [cx0, cy0] = points[i];
      const [nx, ny] = points[i + 1];
      path.quadraticCurveTo(cx0, cy0, (cx0 + nx) / 2, (cy0 + ny) / 2);
    }
    const last = points[points.length - 1];
    path.lineTo(last[0], last[1]);
    return path;
  };

  const buildHead = (w, h, cx, cy) => {
    const rw = w * 0.23;
    const rh = h * 0.34;
    // One continuous jaw/skull contour: temple -> cheekbone -> jaw angle -> chin -> mirror.
    const outline = smoothPath([
      [cx - rw * 0.55, cy - rh * 0.92],
      [cx - rw * 1.02, cy - rh * 0.2],
      [cx - rw * 0.86, cy + rh * 0.48],
      [cx - rw * 0.4, cy + rh * 0.92],
      [cx, cy + rh * 1.04],
      [cx + rw * 0.4, cy + rh * 0.92],
      [cx + rw * 0.86, cy + rh * 0.48],
      [cx + rw * 1.02, cy - rh * 0.2],
      [cx + rw * 0.55, cy - rh * 0.92],
    ]);
    const browL = smoothPath([[cx - rw * 0.62, cy - rh * 0.2], [cx - rw * 0.34, cy - rh * 0.34], [cx - rw * 0.08, cy - rh * 0.22]]);
    const browR = smoothPath([[cx + rw * 0.08, cy - rh * 0.22], [cx + rw * 0.34, cy - rh * 0.34], [cx + rw * 0.62, cy - rh * 0.2]]);
    const cheekL = smoothPath([[cx - rw * 0.7, cy], [cx - rw * 0.5, cy + rh * 0.22], [cx - rw * 0.22, cy + rh * 0.3]]);
    const cheekR = smoothPath([[cx + rw * 0.22, cy + rh * 0.3], [cx + rw * 0.5, cy + rh * 0.22], [cx + rw * 0.7, cy]]);
    const nose = smoothPath([[cx, cy - rh * 0.12], [cx - rw * 0.04, cy + rh * 0.1], [cx - rw * 0.09, cy + rh * 0.16]]);
    const noseR = smoothPath([[cx, cy - rh * 0.12], [cx + rw * 0.04, cy + rh * 0.1], [cx + rw * 0.09, cy + rh * 0.16]]);
    const lipTop = smoothPath([[cx - rw * 0.16, cy + rh * 0.42], [cx - rw * 0.05, cy + rh * 0.38], [cx, cy + rh * 0.41], [cx + rw * 0.05, cy + rh * 0.38], [cx + rw * 0.16, cy + rh * 0.42]]);
    const lipBottom = smoothPath([[cx - rw * 0.14, cy + rh * 0.44], [cx, cy + rh * 0.51], [cx + rw * 0.14, cy + rh * 0.44]]);
    const accents = [
      [cx - rw * 0.62, cy - rh * 0.2],
      [cx + rw * 0.62, cy - rh * 0.2],
      [cx - rw * 0.7, cy],
      [cx + rw * 0.7, cy],
      [cx, cy + rh * 1.02],
    ];
    return { outline, browL, browR, cheekL, cheekR, nose, noseR, lipTop, lipBottom, accents, cx, cy, rw, rh };
  };

  const resize = () => {
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.floor(canvas.clientWidth * ratio));
    canvas.height = Math.max(1, Math.floor(canvas.clientHeight * ratio));
    head = buildHead(canvas.width, canvas.height, canvas.width * 0.5, canvas.height * 0.44);
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

  const drawTunnel = (w, h, cx, cy) => {
    const fov = Math.max(w, h) * 0.6;
    ctx.strokeStyle = "rgba(90,110,130,0.10)";
    ctx.lineWidth = 1;
    rings.forEach((ring) => {
      ring.z = (ring.z + 0.0025) % 1;
      const scale = fov / (fov + ring.z * fov);
      const radius = Math.min(w, h) * 0.32 * scale;
      const alpha = 0.16 * (1 - ring.z);
      if (alpha <= 0.005) return;
      ctx.beginPath();
      for (let s = 0; s <= TUNNEL_SIDES; s += 1) {
        const angle = (s / TUNNEL_SIDES) * Math.PI * 2 + phase * 0.15;
        const x = cx + Math.cos(angle) * radius;
        const y = cy + Math.sin(angle) * radius * 0.82;
        if (s === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `rgba(90,110,130,${alpha.toFixed(3)})`;
      ctx.stroke();
    });
  };

  const draw = () => {
    if (window.MASTER_FACE?.startEverything) {
      stop2DFallback();
      return;
    }

    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    const breath = 0.5 + 0.5 * Math.sin(phase * 0.9);
    drawTunnel(w, h, w * 0.5, h * 0.44);
    const grad = ctx.createRadialGradient(w * 0.5, h * 0.45, 0, w * 0.5, h * 0.45, w * 0.42);
    grad.addColorStop(0, `rgba(28,26,24,${0.55 + breath * 0.08})`);
    grad.addColorStop(0.55, "#121110");
    grad.addColorStop(1, "#000000");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    const { outline, browL, browR, cheekL, cheekR, nose, noseR, lipTop, lipBottom, accents, cx, cy, rw, rh } = head;
    const lineAlpha = 0.22 + breath * 0.08;
    ctx.lineWidth = Math.max(1, w * 0.0012);
    ctx.strokeStyle = `rgba(150,155,160,${lineAlpha.toFixed(3)})`;
    ctx.stroke(outline);
    ctx.strokeStyle = `rgba(150,155,160,${(lineAlpha * 0.8).toFixed(3)})`;
    [browL, browR, cheekL, cheekR, nose, noseR].forEach((path) => ctx.stroke(path));
    ctx.strokeStyle = `rgba(190,195,200,${(lineAlpha * 1.1).toFixed(3)})`;
    ctx.stroke(lipTop);
    ctx.stroke(lipBottom);

    // Eyes: almond socket outline (static path) + iris ring + pupil (dynamic, per-frame).
    [-1, 1].forEach((side) => {
      const ex = cx + side * rw * 0.34;
      const ey = cy - rh * 0.08;
      const socketW = rw * 0.17;
      const socketH = rh * 0.09;
      ctx.beginPath();
      ctx.moveTo(ex - socketW, ey);
      ctx.quadraticCurveTo(ex, ey - socketH, ex + socketW, ey);
      ctx.quadraticCurveTo(ex, ey + socketH * 0.7, ex - socketW, ey);
      ctx.strokeStyle = `rgba(160,165,170,${lineAlpha.toFixed(3)})`;
      ctx.stroke();

      const irisR = rh * 0.045;
      const pupilX = ex + Math.sin(phase * 0.5) * irisR * 0.3;
      const pupilY = ey + Math.cos(phase * 0.7) * irisR * 0.25;
      ctx.beginPath();
      ctx.arc(pupilX, pupilY, irisR, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(210,215,220,${(lineAlpha * 1.2).toFixed(3)})`;
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(pupilX, pupilY, irisR * 0.4, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(210,215,220,${(lineAlpha * 0.9).toFixed(3)})`;
      ctx.fill();
    });

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
