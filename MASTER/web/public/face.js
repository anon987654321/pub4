"use strict";

const STAGE_LABELS = {
  modules: "loading face modules…",
  parts: "loading face runtime…",
  runtime: "starting face runtime…",
  ready: "face ready"
};

function dispatchFaceStage(stage) {
  const label = STAGE_LABELS[stage] || stage;
  window.dispatchEvent(new CustomEvent("master:face-stage", { detail: { stage: label } }));
}

function dispatchFaceError(error) {
  console.error("face boot failed", error);
  window.dispatchEvent(new CustomEvent("master:face-error", { detail: { message: String(error) } }));
}

async function importFaceBlob(FACE_TEXT) {
  const ASSET_PATHS = window.MASTER_ASSET_PATHS || {};
  const absoluteAsset = (path) => path ? new URL(path, document.baseURI).href : null;
  if (ASSET_PATHS.threeModule) ASSET_PATHS.threeModule = absoluteAsset(ASSET_PATHS.threeModule);
  const MODULE_PATHS = {
    "/three.face.module.js?v=1": absoluteAsset(ASSET_PATHS.threeModule),
    ...Object.fromEntries(Object.entries(ASSET_PATHS.faceModules || {}).map(([name, path]) => [`/${name}`, absoluteAsset(path)]))
  };
  const FACE_SOURCE = Object.entries(MODULE_PATHS).reduce(
    (source, [name, path]) => path ? source.replaceAll(`'${name}'`, JSON.stringify(path)) : source,
    FACE_TEXT.join("\n")
  );
  const FACE_BLOB_URL = URL.createObjectURL(new Blob([FACE_SOURCE], { type: "text/javascript" }));
  try {
    await import(FACE_BLOB_URL);
  } finally {
    URL.revokeObjectURL(FACE_BLOB_URL);
  }
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

  const runtimeUrl = window.MASTER_ASSET_PATHS?.faceRuntime;
  if (runtimeUrl) {
    dispatchFaceStage("runtime");
    await import(runtimeUrl);
  } else {
    dispatchFaceStage("parts");
    const FACE_PARTS = window.MASTER_ASSET_PATHS?.faceParts || [
      "face.part1.txt",
      "face.part2.txt",
      "face.part3.txt",
      "face.part4.txt",
      "face.part5.txt"
    ];
    const FACE_TEXT = await Promise.all(FACE_PARTS.map(async (part) => {
      const res = await fetch(part);
      if (!res.ok) throw new Error(`failed to load ${part}: ${res.status}`);
      return res.text();
    }));
    dispatchFaceStage("runtime");
    await importFaceBlob(FACE_TEXT);
  }

  dispatchFaceStage("ready");
  window.dispatchEvent(new CustomEvent("master:face-ready"));
} catch (error) {
  dispatchFaceError(error);
  throw error;
}