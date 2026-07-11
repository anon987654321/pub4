import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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
  const actions = readFileSync(join(publicDir, "chat_actions.js"), "utf8");
  assert.match(actions, /MASTER_SSE\?\.dispatchNamed/);
  assert.match(actions, /handlers\.extensions/);
});

test("chat_actions validates felt state before POST", () => {
  const actions = readFileSync(join(publicDir, "chat_actions.js"), "utf8");
  assert.match(actions, /MASTERFeltState/);
  assert.match(actions, /validatedFeltState/);
  assert.match(actions, /MASTER_SSE/);
  assert.match(actions, /method:\s*"POST"/);
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
  assert.match(gate, /MAX_POLLS/);
  assert.match(gate, /POLL_MS_FAST/);
  assert.match(gate, /master:container-timeout/);
});

test("visual_bridge owns runtime SSE connection", () => {
  const bridge = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");
  assert.match(bridge, /new EventSource\("\/events\/stream"\)/);
  assert.match(bridge, /connectSse/);
  assert.match(bridge, /disconnectSse/);
  assert.match(bridge, /document\.addEventListener\("visibilitychange"/);
});

test("visual_bridge logs parse failures instead of silent catch", () => {
  const bridge = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");
  assert.match(bridge, /MASTER_LOG\?\.warn\?\.\("visual_bridge:sse_frame"/);
  assert.match(bridge, /MASTER_LOG\?\.warn\?\.\("visual_bridge:cable_frame"/);
});

test("chat index keeps THREE behind the primer tap", () => {
  const index = readFileSync(join(root, "app", "views", "chat", "index.html.erb"), "utf8");
  assert.match(index, /three\.face\.module\.js/);
  assert.doesNotMatch(index, /rel="prefetch"[^>]+three\.face\.module\.js/);
  assert.doesNotMatch(index, /rel="modulepreload"[^>]+three\.face\.module\.js/);
});

test("face runtime logs failures for chat and TTS paths", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(runtime, /evtSrc\.onerror/);
  assert.match(runtime, /speakFailure/);
  assert.match(runtime, /tts fail/);
});
