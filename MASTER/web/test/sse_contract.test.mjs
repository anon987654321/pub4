import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");

test("sse_contract defines canonical chat event handlers", () => {
  const source = readFileSync(join(publicDir, "sse_contract.js"), "utf8");
  ["thought", "tool", "enhance", "dmesg", "compaction", "ctx_footer", "phantom", "tool_stack", "stage", "btw", "client_action", "pressure"].forEach((event) => {
    assert.match(source, new RegExp(`\\b${event}\\b`));
  });
  assert.match(source, /MASTER_SSE/);
  assert.match(source, /dispatchNamed/);
  assert.match(source, /MASTER_LOG/);
});

test("face runtime delegates named SSE events to MASTER_SSE", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(runtime, /MASTER_SSE\?\.dispatchNamed/);
  assert.match(runtime, /sseExtensions/);
});

test("chat_actions validates felt state before POST", () => {
  const actions = readFileSync(join(publicDir, "chat_actions.js"), "utf8");
  assert.match(actions, /MASTERFeltState/);
  assert.match(actions, /validatedFeltState/);
  assert.match(actions, /MASTER_SSE/);
});

test("felt_state uses seven-field pipe format", () => {
  const felt = readFileSync(join(publicDir, "felt_state.js"), "utf8");
  assert.match(felt, /FIELD_COUNT\s*=\s*7/);
  assert.match(felt, /validateFeltState/);
  assert.match(felt, /feltStateOrFallback/);
});

test("container gate polls runtime status endpoint", () => {
  const gate = readFileSync(join(publicDir, "container_gate.js"), "utf8");
  assert.match(gate, /\/runtime\/status/);
  assert.match(gate, /MASTER_CONTAINER_READY/);
  assert.match(gate, /blockingSend/);
});

test("visual_bridge logs parse failures instead of silent catch", () => {
  const bridge = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");
  assert.match(bridge, /MASTER_LOG\?\.warn\?\.\("visual_bridge:sse_frame"/);
  assert.doesNotMatch(bridge, /catch \(_error\) \{\}/);
});

test("three.module.js is not part of face boot asset contract", () => {
  const helper = readFileSync(join(root, "app", "helpers", "face_assets_helper.rb"), "utf8");
  assert.match(helper, /three\.face\.module\.js/);
  assert.doesNotMatch(helper, /three\.module\.js/);
});

test("three.module.js source file removed from public", () => {
  const legacy = join(publicDir, "three.module.js");
  assert.equal(existsSync(legacy), false, "delete unused public/three.module.js");
});

test("face runtime has no silent empty catches", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.doesNotMatch(runtime, /catch \(_\) \{\}/);
  assert.match(runtime, /MASTER_LOG\?\.warn/);
});