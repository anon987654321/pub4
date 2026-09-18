"use strict";

function visionBundleUrl() {
  const paths = window.MASTER_ASSET_PATHS || {};
  return paths.faceVisionBundle || paths.faceModules?.["face_vision.bundle.js"] || "/face_vision.bundle.js";
}

function assetUrl(name) {
  const paths = window.MASTER_ASSET_PATHS || {};
  return paths.faceModules?.[name] || `/${name}`;
}

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[data-deferred-src="${src}"]`);
    if (existing) {
      existing.addEventListener("load", () => resolve(), { once: true });
      existing.addEventListener("error", () => reject(new Error(`load failed: ${src}`)), { once: true });
      return;
    }
    const script = document.createElement("script");
    script.src = src;
    script.defer = true;
    script.dataset.deferredSrc = src;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`load failed: ${src}`));
    document.head.appendChild(script);
  });
}

async function loadDeferredFaceLayer() {
  if (window.__MASTER_DEFERRED_FACE_LOADING__) return window.__MASTER_DEFERRED_FACE_LOADING__;
  window.__MASTER_DEFERRED_FACE_LOADING__ = (async () => {
    const vision = visionBundleUrl();
    await loadScript(vision);
    await Promise.all([
      loadScript(assetUrl("cognition_ecology.js")),
      loadScript(assetUrl("cognition_ecology_render.js")),
      loadScript(assetUrl("face_points_gl.js"))
    ]);
    window.dispatchEvent(new CustomEvent("master:deferred-face-ready"));
  })().catch((err) => {
    window.MASTER_LOG?.warn?.("face_deferred_loader", err);
    delete window.__MASTER_DEFERRED_FACE_LOADING__;
  });
  return window.__MASTER_DEFERRED_FACE_LOADING__;
}

function scheduleDeferredFaceLayer() {
  const run = () => { loadDeferredFaceLayer(); };
  if (window._primerFired) run();
  else window.addEventListener("primer:ready", run, { once: true });
}

scheduleDeferredFaceLayer();

window.MASTER_DEFERRED_FACE = { load: loadDeferredFaceLayer };
