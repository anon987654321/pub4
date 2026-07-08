// Lightweight 2D face while Three.js loads. Uses canvas#face (2d context only).
"use strict";

let fallbackFrame = null;

function stop2DFallback() {
  if (fallbackFrame) {
    cancelAnimationFrame(fallbackFrame);
    fallbackFrame = null;
  }
}

function start2DFallback() {
  const canvas = document.getElementById("face");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  stop2DFallback();

  const resize = () => {
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.floor(canvas.clientWidth * ratio));
    canvas.height = Math.max(1, Math.floor(canvas.clientHeight * ratio));
  };
  resize();
  window.addEventListener("resize", resize);

  let phase = 0;

  const draw = () => {
    if (window.MASTER_FACE && window.MASTER_FACE.startEverything) {
      stop2DFallback();
      return;
    }

    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    const grad = ctx.createRadialGradient(w * 0.5, h * 0.45, 0, w * 0.5, h * 0.45, w * 0.4);
    grad.addColorStop(0, "#1a1a1a");
    grad.addColorStop(1, "#000000");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    const cx = w * 0.5;
    const cy = h * 0.44;
    ctx.beginPath();
    ctx.ellipse(cx, cy, w * 0.23, h * 0.34, 0, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(60,60,60,0.15)";
    ctx.fill();

    [-0.13, 0.13].forEach((ex) => {
      const exP = cx + ex * w;
      const ey = cy - h * 0.07;
      ctx.beginPath();
      ctx.ellipse(exP, ey, w * 0.035, h * 0.045, 0, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(120,120,120,0.3)";
      ctx.fill();
      const pupilX = exP + Math.sin(phase * 0.5) * w * 0.008;
      const pupilY = ey + Math.cos(phase * 0.7) * h * 0.01;
      ctx.beginPath();
      ctx.arc(pupilX, pupilY, w * 0.012, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(200,200,200,0.3)";
      ctx.fill();
    });

    const mouthY = cy + h * 0.14;
    const mouthW = w * 0.08;
    const mouthH = h * 0.02 + Math.sin(phase * 0.8) * h * 0.01;
    ctx.beginPath();
    ctx.ellipse(cx, mouthY, mouthW, mouthH, 0, 0, Math.PI);
    ctx.strokeStyle = "rgba(160,160,160,0.25)";
    ctx.lineWidth = 2;
    ctx.stroke();

    phase += 0.02;
    if (!document.hidden) fallbackFrame = requestAnimationFrame(draw);
  };

  draw();
}

window.start2DFallback = start2DFallback;
window.stop2DFallback = stop2DFallback;