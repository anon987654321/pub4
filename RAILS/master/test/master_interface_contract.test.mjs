import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dashboard = readFileSync(join(root, "app", "views", "dashboard", "index.html.erb"), "utf8");
const chatIndex = readFileSync(join(root, "app", "views", "chat", "index.html.erb"), "utf8");
const pwaManifest = readFileSync(join(root, "app", "views", "pwa", "manifest.json.erb"), "utf8");
const publicDir = join(root, "public");
const chat = readFileSync(join(publicDir, "chat.js"), "utf8");
const faceMotion = readFileSync(join(root, "styles", "face", "40_accessibility_motion.css"), "utf8");
const faceConversation = readFileSync(join(root, "styles", "face", "30_conversation.css"), "utf8");
const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
const laws = readFileSync(join(root, "..", "..", "MASTER", "data", "laws.yml"), "utf8");
const tokens = readFileSync(join(root, "..", "..", "MASTER", "data", "tokens.yml"), "utf8");
const interaction = readFileSync(join(publicDir, "master_interaction_state.js"), "utf8");
const faceWorld = readFileSync(join(publicDir, "face_world.js"), "utf8");
const audio = readFileSync(join(publicDir, "face_audio_field.js"), "utf8");
const render = readFileSync(join(publicDir, "face_render_policy.js"), "utf8");
const voice = readFileSync(join(publicDir, "voice_surface.js"), "utf8");
const tasks = readFileSync(join(publicDir, "master_task_ui.js"), "utf8");
const workspace = readFileSync(join(publicDir, "master_workspace.js"), "utf8");
const accessibility = readFileSync(join(publicDir, "master_accessibility.js"), "utf8");
const part5 = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
const faceCss = readFileSync(join(publicDir, "face.css"), "utf8");
const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");

test("canonical interface modules are declared in the shell manifest", () => {
  for (const name of [
    "master_interaction_state", "face_audio_field", "face_render_policy",
    "voice_surface", "master_task_ui", "master_workspace", "master_accessibility"
  ]) {
    assert.ok(manifest.split("\n").includes("  - " + name));
  }
});

test("tokens publish the canonical interaction, audio and performance contract", () => {
  assert.match(tokens, /interaction:/);
  assert.match(tokens, /audio:/);
  assert.match(tokens, /target_fps: 60/);
  assert.match(tokens, /main_thread_budget_ms: 8/);
  assert.match(tokens, /speech:start/);
  assert.match(tokens, /task:waiting-human/);
});

test("interaction state defines the canonical turn task tool visual and memory stores", () => {
  for (const name of ["interaction", "turn", "task", "tool", "visual", "memory"]) assert.match(interaction, new RegExp(name + ":"));
  for (const event of [
    "speech:start", "speech:partial", "speech:end", "speech:abort",
    "tts:start", "tts:end", "tts:interrupt",
    "turn:committed", "turn:discarded", "turn:interrupted",
    "task:queued", "task:waiting-human", "task:waiting-network", "task:waiting-model",
    "tool:queued", "tool:active", "tool:retry", "tool:complete", "tool:failed"
  ]) assert.ok((interaction + tokens).includes(event), event + " missing");
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
  assert.match(render, /TARGET_FPS = Number\(PERFORMANCE\.target_fps\) \|\| 60/);
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
  assert.match(accessibility, /aria-pressed/);
  assert.match(accessibility, /state === "listening" \? "true" : "false"/);
  assert.match(accessibility, /task failed/);
  assert.match(faceCss, /#cmd-palette-input:focus-visible/);
});

test("recognizer end is not treated as a conversational boundary", () => {
  assert.match(part5, /orphanedTranscript = sttPartial\.trim\(\)/);
  assert.match(part5, /Browser onend is an implementation boundary/);
  assert.match(part5, /new CustomEvent\('stt:partial'/);
  assert.match(part5, /new CustomEvent\('stt:end'/);
  assert.match(part5, /commitTurn\?\.\(t2, 'voice'/);
});

test("generated face runtime names current face sources", () => {
  for (const file of ["face.part1.txt", "face.part2.txt", "face.part3.txt", "face_speech_runtime.js", "face_speech_playback.js", "face.part5.txt"]) {
    const escaped = file.replace(".", "\\.");
    assert.match(runtime, new RegExp(escaped + "\\b"), file + " is not named by face.runtime.js");
  }
});

test("virtualized chat retains recoverable older messages", () => {
  assert.match(chat, /const CHAT_ARCHIVE_BATCH = 28;/);
  assert.match(chat, /function restoreOlderChatMessages\(\)/);
  assert.match(chat, /chatArchive\.splice\(start\)/);
  assert.match(chat, /chatT\('load_older_messages'/);
  assert.doesNotMatch(chat, /chatArchived \* 68/);
  assert.match(faceMotion, /\.virtual-spacer-load/);
  assert.match(faceCss, /\.virtual-spacer-load/);
});
test("message action menu is localized, safe to render, and viewport-aware", () => {
  const start = chat.indexOf("function openActionMenu(msgEl)");
  const end = chat.indexOf("// Per-message context-usage footer", start);
  const menu = chat.slice(start, end);
  assert.ok(start >= 0 && end > start, "openActionMenu function is missing");
  for (const key of ["message_actions", "message_copy", "message_quote", "message_simpler", "message_deeper"]) {
    assert.match(menu, new RegExp("chatT\\('" + key + "'"));
  }
  assert.match(menu, /visualViewport/);
  assert.match(menu, /setAttribute\('role', 'group'\)/);
  assert.match(menu, /menu\.querySelector\('button'\)\?\.focus/);
  assert.match(menu, /e\.key === 'Escape'/);
  assert.match(menu, /removeEventListener\('keydown', close\)/);
  assert.match(menu, /activeChatActionMenuDismiss\?\.\(\)/);
  assert.match(menu, /activeChatActionMenuDismiss === dismiss/);
  assert.doesNotMatch(menu, /menu\.innerHTML/);
  for (const css of [faceConversation, faceCss]) {
    assert.match(css, /\.action-menu button\s*\{[^}]*min-block-size:\s*var\(--tap-min\)/s);
    assert.match(css, /\.action-menu button:focus-visible\s*\{[^}]*outline:/s);
  }
});
test("face shell stays flat and square", () => {
  assert.doesNotMatch(faceCss, /backdrop-filter\s*:\s*(?!none\b)[^;]+;/i);
  assert.doesNotMatch(faceCss, /filter\s*:\s*[^;]*\b(?:blur|drop-shadow)\(/i);

  const pip = faceCss.match(/body\[data-face-pip="1"\] canvas\s*\{[^}]+\}/);
  assert.ok(pip, "PIP face canvas rule is missing");
  assert.match(pip[0], /border-radius:\s*0;/);

  const rail = faceCss.match(/\.master-task-rail\s*\{[^}]+\}/);
  assert.ok(rail, "task rail rule is missing");
  assert.match(rail[0], /background:\s*var\(--face-bg\);/);
});

test("FaceWorld reports one performance sample per canonical update", () => {
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  assert.match(world, /MasterRenderPolicy\?\.recordFrame\?\.\(now\)/);
});


test("evidence events retain their event name and reach the shared FaceWorld clock", () => {
  assert.ok(tokens.includes("- memory:added"), "memory:added must be allowed by the canonical contract");
  assert.match(tokens, /task_ring:\n\s+enabled: true/);
  assert.match(interaction, /const detail = \{ \.\.\.payload, ts: now\(\), type: name \}/);
  assert.match(interaction, /detail\.recordType = payload\.type/);
  for (const event of ["task:queued", "task:active", "task:waiting-human", "task:complete",
                       "task:failed", "tool:queued", "tool:active", "tool:complete", "tool:failed",
                       "memory:added"]) {
    assert.ok(tokens.includes("- " + event), event + " is missing from the face contract");
  }
  assert.match(faceWorld, /function syncActivitySnapshot\(\)/);
  assert.match(faceWorld, /function updateActivityNodes\(now, state\)/);
  assert.match(faceWorld, /updateActivityNodes\(now, state\)/);
  assert.doesNotMatch(faceWorld, /requestAnimationFrame\(/);
  assert.ok(manifest.includes("- face_world.js"), "spatial nodes must use the already loaded FaceWorld asset");
});

test("mission control distinguishes fresh, failed and terminal live states", () => {
  assert.match(dashboard, /id="refresh-state"[^>]*role="status"/);
  assert.match(dashboard, /if \(!r\.ok \|\| d\.error\)/);
  assert.match(dashboard, /catch \(error\)/);
  assert.match(dashboard, /document\.hidden/);
  assert.match(dashboard, /inFlight/);
  assert.match(dashboard, /i18nRefreshFailed/);
  assert.match(dashboard, /i18nUpdated/);
  assert.match(dashboard, /closeDoor\(\)/);
});

test("chat and mission control share accessible Ghostty-inspired session tabs", () => {
  for (const page of [chatIndex, dashboard]) {
    assert.match(page, /class="master-titlebar/);
    assert.match(page, /class="master-session-tabs" aria-label=/);
    assert.match(page, /class="master-session-tab"/);
    assert.match(page, /href="\/" /);
    assert.match(page, /href="\/dashboard"/);
  }
  assert.match(chatIndex, /href="\/" aria-current="page"/);
  assert.match(dashboard, /href="\/dashboard" aria-current="page"/);
  assert.match(faceMotion, /\.master-session-tab\[aria-current="page"\]::after/);
  assert.match(faceMotion, /@media \(max-width: 420px\)/);
  assert.match(faceMotion, /\.master-session-tab:focus-visible/);
});

test("canonical graphite theme reaches generated face CSS and the installed PWA", () => {
  const rootStart = faceCss.indexOf("/* BEGIN:generated-face-root");
  const rootEnd = faceCss.indexOf("/* END:generated-face-root */", rootStart);
  assert.ok(rootStart >= 0 && rootEnd > rootStart, "generated face token block is missing");
  const root = faceCss.slice(rootStart, rootEnd);
  assert.match(tokens, /face_bg: "#050710"/);
  assert.match(tokens, /x_text: "#e7eeff"/);
  assert.match(root, /--face-bg: #050710;/);
  assert.match(root, /--x-text: #e7eeff;/);
  assert.match(pwaManifest, /"background_color": "#050710"/);
  assert.match(pwaManifest, /"theme_color": "#050710"/);
  assert.match(chatIndex, /meta name="theme-color" content="#050710"/);
  assert.doesNotMatch(faceMotion, /--c-accent: oklch\(82% 0\.12 222\)/);
  assert.doesNotMatch(faceMotion, /--radius-md: 12px/);
});

test("session chrome uses space, not decorative divider borders", () => {
  const start = faceMotion.indexOf("/* Ghostty-inspired session chrome:");
  assert.ok(start >= 0, "shared session chrome source is missing");
  const chrome = faceMotion.slice(start);
  assert.match(chrome, /gap: 0\.25rem/);
  assert.doesNotMatch(chrome, /border-(?:block|inline)-end:\s*1px/);
});
