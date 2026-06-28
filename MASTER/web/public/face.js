"use strict";

const STAGE_LABELS = {
  modules: "loading face modules…",
  runtime: "starting face runtime…",
  ready: "face ready"
};

function dispatchFaceStage(stage) {
  const label = STAGE_LABELS[stage] || stage;
  window.dispatchEvent(new CustomEvent("master:face-stage", { detail: { stage: label } }));
}

function dispatchFaceError(error, moduleName = "face.boot") {
  window.MASTER_LOG?.error?.("face boot", error);
  window.MASTER_FACE_VISION?.showBootError?.(error, { module: moduleName, stage: "boot" });
  window.dispatchEvent(new CustomEvent("master:face-error", {
    detail: { message: String(error), module: moduleName, stage: "boot" }
  }));
}

function onPrimerSession() {
  if (window.MASTER_FACE?.startEverything && !window.MASTER_FACE.primerFired) {
    window.MASTER_FACE.startEverything();
  }
}

async function loadTailModules() {
  const modules = window.MASTER_ASSET_PATHS?.faceModules || {};
  const names = [
    "face_semantics.js",
    "face_minimal_ui.js",
    "face_loops_music.js",
    "face_loops_nudge.js"
  ];
  await Promise.all(names.map((name) => import(modules[name] || `/${name}`)));
}

async function bootFaceStack() {
  if (window.__MASTER_FACE_STACK_READY__) return window.__MASTER_FACE_STACK_PROMISE__;
  window.__MASTER_FACE_STACK_PROMISE__ = (async () => {
    dispatchFaceStage("modules");

    const ASSET_PATHS = window.MASTER_ASSET_PATHS || {};
    const FACE_MODULES = ASSET_PATHS.faceModulesList || [
      "face_particles.js",
      "face_audio_bridge.js",
      "face_tts_bridge.js",
      "face_expression_bridge.js",
      "face_council_multi.js",
      "face_phosphor_trail.js",
      "face_offscreen_ecology.js",
      "face_micro_interactions.js",
      "face_perf_guards.js",
      "face_brutalist.js"
    ];

    if (ASSET_PATHS.faceModulesBundle) {
      await import(ASSET_PATHS.faceModulesBundle);
      if (!window.FACE3D_ACTIVE) await import(ASSET_PATHS.face3dPreview || "/face3d_preview.js");
    } else {
      const imports = [
        import(ASSET_PATHS.faceModules?.["face_blendshape_bridge.js"] || "/face_blendshape_bridge.js")
      ];
      if (!window.FACE3D_ACTIVE) imports.push(import(ASSET_PATHS.face3dPreview || "/face3d_preview.js"));
      imports.push(...FACE_MODULES.map(async (modulePath) => {
        const url = ASSET_PATHS.faceModules?.[modulePath] || `/${modulePath}`;
        await import(url);
      }));
      await Promise.all(imports);
    }

    const runtimeUrl = ASSET_PATHS.faceRuntime;
    if (!runtimeUrl) {
      throw new Error("face.runtime.js missing — run: rails assets:build_face_runtime");
    }
    if (window.MASTER_FACE) {
      window.__MASTER_FACE_STACK_READY__ = true;
      return;
    }

    dispatchFaceStage("runtime");
    await import(runtimeUrl);
    await loadTailModules();
    dispatchFaceStage("ready");
    window.__MASTER_FACE_STACK_READY__ = true;
    window.dispatchEvent(new CustomEvent("master:face-ready"));
    if (window._primerFired) onPrimerSession();
  })().catch((error) => {
    delete window.__MASTER_FACE_STACK_PROMISE__;
    delete window.__MASTER_FACE_STACK_READY__;
    dispatchFaceError(error);
    throw error;
  });
  return window.__MASTER_FACE_STACK_PROMISE__;
}

// Warm face runtime + particles behind the primer overlay (do not wait for tap).
bootFaceStack();

if (window._primerFired) onPrimerSession();
window.addEventListener("primer:ready", onPrimerSession, { once: true });
window.addEventListener("master:face-ready", () => {
  if (window._primerFired) onPrimerSession();
});