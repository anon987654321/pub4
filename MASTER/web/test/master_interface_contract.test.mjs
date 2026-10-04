import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");
const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
const laws = readFileSync(join(root, "..", "data", "laws.yml"), "utf8");
const interaction = readFileSync(join(publicDir, "master_interaction_state.js"), "utf8");
const audio = readFileSync(join(publicDir, "face_audio_field.js"), "utf8");
const render = readFileSync(join(publicDir, "face_render_policy.js"), "utf8");
const voice = readFileSync(join(publicDir, "voice_surface.js"), "utf8");
const tasks = readFileSync(join(publicDir, "master_task_ui.js"), "utf8");
const workspace = readFileSync(join(publicDir, "master_workspace.js"), "utf8");
const accessibility = readFileSync(join(publicDir, "master_accessibility.js"), "utf8");
const part5 = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");

test("canonical interface modules are declared in the shell manifest", () => {
  for (const name of [
    "master_interaction_state", "face_audio_field", "face_render_policy",
    "voice_surface", "master_task_ui", "master_workspace", "master_accessibility"
  ]) {
    assert.ok(manifest.split("\n").includes("  - " + name));
  }
});

test("laws publish the canonical interaction, audio and performance contract", () => {
  assert.match(laws, /interaction:/);
  assert.match(laws, /audio:/);
  assert.match(laws, /target_fps: 60/);
  assert.match(laws, /main_thread_budget_ms: 8/);
  assert.match(laws, /speech:start/);
  assert.match(laws, /task:waiting-human/);
});

test("interaction state defines the canonical turn task tool visual and memory stores", () => {
  for (const name of ["interaction", "turn", "task", "tool", "visual", "memory"]) assert.match(interaction, new RegExp(name + ":"));
  for (const event of [
    "speech:start", "speech:partial", "speech:end", "speech:abort",
    "tts:start", "tts:end", "tts:interrupt",
    "turn:committed", "turn:discarded", "turn:interrupted",
    "task:queued", "task:waiting-human", "task:waiting-network", "task:waiting-model",
    "tool:queued", "tool:active", "tool:retry", "tool:complete", "tool:failed"
  ]) assert.ok(interaction.includes(event), event + " missing");
});

test("audio field keeps smoothed and transient signals separate", () => {
  for (const field of ["rms", "peak", "bass", "mid", "high", "centroid", "onset", "speechActivity",
                       "sampleRate", "channels", "analyserWindow", "latencyMs", "playbackBufferMs", "underruns"]) {
    assert.ok(audio.includes(field), field + " missing");
  }
  assert.match(audio, /const transientDecay/);
  assert.match(audio, /function ingestMicrophone/);
  assert.match(audio, /function ingestPlayback/);
  assert.match(audio, /audio:update/);
});

test("render policy exposes a 60fps target and adaptive hysteresis without a second RAF", () => {
  assert.match(render, /TARGET_FPS = 60/);
  assert.match(render, /HYSTERESIS/);
  assert.match(render, /function recordFrame/);
  assert.match(render, /PerformanceObserver/);
  assert.doesNotMatch(render, /requestAnimationFrame\(/);
});

test("voice surface coordinates typing suspension and explicit recovery", () => {
  assert.match(voice, /enterkeyhint/);
  assert.match(voice, /suspendForTyping/);
  assert.match(voice, /resumeAfterTyping/);
  assert.match(voice, /retry voice/);
});

test("task and workspace projections expose stable IDs and provenance", () => {
  assert.match(tasks, /taskCreate/);
  assert.match(tasks, /provenance/);
  assert.match(tasks, /waiting for you/);
  assert.match(tasks, /retry/);
  assert.match(workspace, /version:/);
  assert.match(workspace, /provenance/);
  assert.match(workspace, /relationships/);
  assert.match(workspace, /select\(/);
  assert.match(workspace, /master:workspace:v1/);
});

test("accessibility projection exposes live state, reduced motion and forced colours", () => {
  assert.match(accessibility, /aria-live/);
  assert.match(accessibility, /prefers-reduced-motion/);
  assert.match(accessibility, /forced-colors/);
  assert.match(accessibility, /microphone/);
  assert.match(accessibility, /task failed/);
});

test("recognizer end is not treated as a conversational boundary", () => {
  assert.match(part5, /orphanedTranscript = sttPartial\.trim\(\)/);
  assert.match(part5, /Browser onend is an implementation boundary/);
  assert.match(part5, /new CustomEvent\('stt:partial'/);
  assert.match(part5, /new CustomEvent\('stt:end'/);
  assert.match(part5, /commitTurn\?\.\(t2, 'voice'/);
});

test("generated face runtime contains current face sources", () => {
  for (const file of ["face.part1.txt", "face.part2.txt", "face.part3.txt", "face_speech_runtime.js", "face_speech_playback.js", "face.part5.txt"]) {
    const source = readFileSync(join(publicDir, file), "utf8").trim();
    assert.ok(runtime.includes(source.slice(0, 160)), file + " is not represented in face.runtime.js");
  }
});

test("FaceWorld reports one performance sample per canonical update", () => {
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  assert.match(world, /MasterRenderPolicy\?\.recordFrame\?\.\(now\)/);
});
