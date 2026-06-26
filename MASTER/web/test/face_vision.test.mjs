import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");
const viewsDir = join(root, "app", "views");

const VISION_FILES = [
  "face_vision_core.js",
  "face_vision_a.js",
  "face_vision_b.js",
  "face_vision_c.js",
  "face_vision_d.js"
];

test("face vision sources exist and register 150 features", () => {
  VISION_FILES.forEach((name) => {
    assert.ok(existsSync(join(publicDir, name)), `${name} missing`);
  });
  const registerCount = VISION_FILES.reduce((sum, name) => {
    const src = readFileSync(join(publicDir, name), "utf8");
    const matches = src.match(/V\.register\(\d+/g) || [];
    return sum + matches.length;
  }, 0);
  assert.equal(registerCount, 150, `expected 150 V.register calls, got ${registerCount}`);
});

test("face_vision.bundle.js is generated from vision sources", () => {
  const bundlePath = join(publicDir, "face_vision.bundle.js");
  assert.ok(existsSync(bundlePath), "run rails assets:build_face_vision_bundle");
  const bundle = readFileSync(bundlePath, "utf8");
  assert.match(bundle, /MASTER_FACE_VISION/);
  assert.match(bundle, /V\.register\(150/);
});

test("face vision core exposes registry API and routes", () => {
  const core = readFileSync(join(publicDir, "face_vision_core.js"), "utf8");
  assert.match(core, /MASTER_FACE_VISION/);
  assert.match(core, /register\(id, summary, handler\)/);
  assert.match(core, /patchMasterVisual/);
  assert.match(core, /faceBootMs/);
  assert.match(core, /particleWorkerAlive/);
  assert.match(core, /MAX_FEATURES = 150/);
});

test("chat index defers vision and ecology via face_deferred_loader", () => {
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  const bridgeIdx = index.indexOf("visual_bridge.js");
  const loaderIdx = index.indexOf("face_deferred_loader.js");
  assert.ok(bridgeIdx > 0 && loaderIdx > bridgeIdx, "deferred loader must follow visual_bridge");
  assert.doesNotMatch(index, /face_vision_core\.js/);
  assert.doesNotMatch(index, /cognition_ecology\.js/);
});

test("runtime status includes build and face metrics keys", () => {
  const runtime = readFileSync(join(root, "app", "controllers", "runtime_controller.rb"), "utf8");
  assert.match(runtime, /build:/);
  assert.match(runtime, /face_boot_ms:/);
  assert.match(runtime, /particle_worker_alive:/);
});

test("canvas accepts face:metrics topic", () => {
  const canvas = readFileSync(join(root, "app", "controllers", "canvas_controller.rb"), "utf8");
  assert.match(canvas, /face:metrics/);
  assert.match(canvas, /face:metrics:#{request\.remote_ip}/);
});

test("container gate exposes retry boot button", () => {
  const gate = readFileSync(join(publicDir, "container_gate.js"), "utf8");
  assert.match(gate, /master-retry-boot/);
  assert.match(gate, /ensureRetryBootButton/);
});

test("face.js reports module on boot error", () => {
  const faceJs = readFileSync(join(publicDir, "face.js"), "utf8");
  assert.match(faceJs, /module: moduleName/);
  assert.match(faceJs, /MASTER_FACE_VISION\?\.showBootError/);
});