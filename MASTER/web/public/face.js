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

function dispatchFaceError(error) {
  window.MASTER_LOG?.error?.("face boot", error);
  window.dispatchEvent(new CustomEvent("master:face-error", { detail: { message: String(error) } }));
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

try {
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
    await Promise.all([
      import(ASSET_PATHS.faceModulesBundle),
      import(ASSET_PATHS.face3dPreview || "/face3d_preview.js")
    ]);
  } else {
    await Promise.all([
      import(ASSET_PATHS.faceModules?.["face_blendshape_bridge.js"] || "/face_blendshape_bridge.js"),
      import(ASSET_PATHS.face3dPreview || "/face3d_preview.js"),
      ...FACE_MODULES.map(async (modulePath) => {
        const url = ASSET_PATHS.faceModules?.[modulePath] || `/${modulePath}`;
        await import(url);
      })
    ]);
  }

  const runtimeUrl = ASSET_PATHS.faceRuntime;
  if (!runtimeUrl) {
    const err = new Error("face.runtime.js missing — run: rails assets:build_face_runtime");
    dispatchFaceError(err);
    throw err;
  }

  async function bootRuntime() {
    if (window.MASTER_FACE) return;
    dispatchFaceStage("runtime");
    await import(runtimeUrl);
    await loadTailModules();
    dispatchFaceStage("ready");
    window.dispatchEvent(new CustomEvent("master:face-ready"));
  }

  if (window._primerFired) {
    await bootRuntime();
  } else {
    window.addEventListener("primer:ready", () => {
      bootRuntime().catch(dispatchFaceError);
    }, { once: true });
  }
} catch (error) {
  dispatchFaceError(error);
  throw error;
}