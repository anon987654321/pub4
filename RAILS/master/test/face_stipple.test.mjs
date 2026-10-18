import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");
const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
const system = readFileSync(join(publicDir, "face_stipple_system.js"), "utf8");
const playground = readFileSync(join(publicDir, "face_playground.js"), "utf8");
const css = readFileSync(join(publicDir, "face.css"), "utf8");

test("stipple assets are declared after existing face modules", () => {
  assert.match(manifest, /- master_namespace\s+\n\s+- face_stipple_system\s+\n\s+- face_playground/);
  assert.match(system, /window\.MASTER_FACE_STIPPLE/);
  assert.match(system, /renderer\.render = function/);
  assert.match(system, /active\.root\.add\(active\.points\)/);
});

test("stipple shares face state and obeys point and motion budgets", () => {
  assert.match(system, /state\.pressureFields\?\.pct/);
  assert.match(system, /state\.pressureFields\?\.entropy/);
  assert.match(system, /state\.reducedMotion/);
  assert.match(system, /budget\.mobile_points/);
  assert.match(system, /budget\.desktop_points/);
  assert.doesNotMatch(system, /budget\.desktop_particles/);
  assert.match(system, /buildFromSamples/);
  assert.match(system, /gl_PointSize = aThreshold > uDensity \? 0\.0 : 1\.0/);
});

test("playground is opt-in and supplies seven semantic states", () => {
  assert.match(playground, /get\("playground"\) !== "1"/);
  for (const mode of ["idle", "thinking", "listening", "working", "speaking", "warning", "error"]) assert.match(playground, new RegExp(mode));
  assert.match(playground, /FacePlayground/);
  assert.match(css, /\.master-face-stipple-playground/);
});
