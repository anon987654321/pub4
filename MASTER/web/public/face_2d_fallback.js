// The face while the real one loads, and the only face when it cannot: the same ASCII head
// (face_ascii.js) at rest, drawn on a canvas of its own. It never touches #face — the runtime
// takes a 2D context there for the ASCII face, or a WebGL one for ?face_mode=3d, and a canvas
// keeps whichever it was given first (a 2d context on a WebGL canvas is a dead tap and a black face).
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
  canvas.style.cssText = "position:fixed;inset:0;width:100%;height:100%;z-index:1;pointer-events:none;background:#050710";
  const face = document.getElementById("face");
  if (face?.parentNode) face.parentNode.insertBefore(canvas, face.nextSibling);
  else document.body.appendChild(canvas);
  return canvas;
}

function start2DFallback() {
  stop2DFallback();
  const ascii = window.MASTER_FACE_ASCII;
  if (!ascii || !window.MASTER_FACE_CONTRACT?.ascii) return;

  const canvas = ensureFallbackCanvas();
  let view = null;
  try {
    view = ascii.createView(canvas);
  } catch (err) {
    window.MASTER_LOG?.warn?.("face_2d_fallback:ascii", err);
  }
  if (!view) {
    canvas.remove();
    return;
  }

  const calm = matchMedia("(prefers-reduced-motion: reduce)");
  const draw = (now) => {
    if (window.MASTER_FACE?.startEverything) {
      stop2DFallback();
      return;
    }
    view.draw(now, { state: "idle", reduced: calm.matches });
    if (!document.hidden) fallbackFrame = requestAnimationFrame(draw);
  };
  fallbackFrame = requestAnimationFrame(draw);
}

window.start2DFallback = start2DFallback;
window.stop2DFallback = stop2DFallback;

if (window._primerFired) start2DFallback();
else window.addEventListener("primer:ready", start2DFallback, { once: true });
