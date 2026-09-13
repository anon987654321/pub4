import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");

function loadContract() {
  const logged = [];
  const window = { MASTER_LOG: { warn: (...args) => logged.push(args), error: (...args) => logged.push(args) } };
  runInContext(readFileSync(join(publicDir, "sse_contract.js"), "utf8"), createContext({ window }));
  return { sse: window.MASTER_SSE, window, logged };
}

// Every name ChatService writes through write_event or write_json_event. The
// trace event goes straight to the stream, carries an id for the logs, and no
// client reacts to it.
function emittedEvents() {
  const service = readFileSync(join(root, "app", "services", "chat_service.rb"), "utf8");
  return new Set([...service.matchAll(/write_(?:json_)?event\("([^"]+)"/g)].map((match) => match[1]));
}

function faceEvents() {
  const part5 = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
  const body = part5.slice(part5.indexOf("function handleFaceNamedEvent"), part5.indexOf("\n}\n", part5.indexOf("function handleFaceNamedEvent")));
  return new Set([...body.matchAll(/event === '([^']+)'/g)].map((match) => match[1]));
}

test("every named event the chat stream writes has exactly one owner", () => {
  const { sse } = loadContract();
  const emitted = emittedEvents();
  const face = faceEvents();
  const generic = new Set(Object.keys(sse.NAMED_HANDLERS));

  // The census has to see what it is counting before an empty difference means
  // anything: council:speech is written through a helper, content_kind from the
  // chunk path, and the face owns both.
  assert.ok(emitted.has("council:speech") && emitted.has("content_kind"), `chat_service census missed events: ${[...emitted]}`);
  assert.ok(face.has("mood") && face.has("felt"), `face census missed events: ${[...face]}`);

  const unhandled = [...emitted].filter((name) => !generic.has(name) && !face.has(name));
  assert.deepEqual(unhandled, [], "chat stream writes events nothing handles");
  const unproduced = [...generic, ...face].filter((name) => !emitted.has(name));
  assert.deepEqual(unproduced, [], "handlers wait for events the chat stream never writes");
  const doubled = [...generic].filter((name) => face.has(name));
  assert.deepEqual(doubled, [], "the face shadows these contract handlers, so the contract copy never runs");
});

test("dispatchNamed runs the contract handler, prefers an extension, and logs a throwing one", () => {
  const { sse, window, logged } = loadContract();
  const lines = [];
  window._chatOnDmesg = (line) => lines.push(line);

  assert.equal(sse.dispatchNamed("dmesg", JSON.stringify("core0 at master0: ok")), true);
  assert.deepEqual(lines, ["core0 at master0: ok"]);

  const seen = [];
  assert.equal(sse.dispatchNamed("dmesg", "x", { dmesg: (data) => seen.push(data) }), true);
  assert.deepEqual(seen, ["x"]);

  assert.equal(sse.dispatchNamed("mood", "calm"), false, "face-owned events are not the contract's");
  assert.equal(sse.dispatchNamed("dmesg", "x", { dmesg: () => { throw new Error("boom"); } }), false);
  assert.equal(logged.at(-1)[0], "sse:dmesg");
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
  // threeModule is declared in config/face_assets.yml; what matters here is that
  // the view never preloads or prefetches it ahead of the tap.
  const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
  assert.match(manifest, /three\.face\.module\.js/);
  assert.doesNotMatch(index, /rel="prefetch"[^>]+three\.face\.module\.js/);
  assert.doesNotMatch(index, /rel="modulepreload"[^>]+three\.face\.module\.js/);
});

test("face runtime logs failures for chat and TTS paths", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(runtime, /face_runtime:chat_transport_missing/);
  assert.match(runtime, /speakFailure/);
  assert.match(runtime, /tts fail/);
});
