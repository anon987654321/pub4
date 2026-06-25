"use strict";

await import(window.MASTER_ASSET_PATHS?.faceModules?.["face_blendshape_bridge.js"] || "/face_blendshape_bridge.js");
await import("/face3d_preview.js");

const FACE_MODULES = window.MASTER_ASSET_PATHS?.faceModulesList || [
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

await Promise.all(FACE_MODULES.map(async (modulePath) => {
  const url = window.MASTER_ASSET_PATHS?.[modulePath] || modulePath;
  await import(url);
}));

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
const FACE_BLOB = new Blob([FACE_SOURCE], { type: "text/javascript" });
const FACE_BLOB_URL = URL.createObjectURL(FACE_BLOB);
try {
  await import(FACE_BLOB_URL);
} finally {
  URL.revokeObjectURL(FACE_BLOB_URL);
}
