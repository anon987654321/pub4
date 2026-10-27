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
const faceChrome = readFileSync(join(root, "styles", "face", "60_session_chrome.css"), "utf8");
const faceBuilder = readFileSync(join(root, "..", "..", "MASTER", "tools", "rails", "build_face_css.rb"), "utf8");
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
  // The lookahead sits before the whitespace so "backdrop-filter: none;" cannot
  // slip past it by backtracking \s*.
  assert.doesNotMatch(faceCss, /backdrop-filter\s*:(?!\s*none\b)[^;]+;/i);
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
  assert.match(faceWorld, /function updateActivityNodes\(now, state, reducedMotion = false\)/);
  assert.match(faceWorld, /updateActivityNodes\(now, state, reducedMotion\)/);
  assert.doesNotMatch(faceWorld, /requestAnimationFrame\(/);
  assert.ok(manifest.includes("- face_world.js"), "spatial nodes must use the already loaded FaceWorld asset");
});

test("mission control distinguishes fresh, failed and terminal live states", () => {
  // The view owns the status node and localized strings; dashboard_live.js polls.
  const poller = readFileSync(join(publicDir, "dashboard_live.js"), "utf8");
  assert.match(dashboard, /id="refresh-state"[^>]*role="status"/);
  assert.match(dashboard, /data-i18n-refresh-failed=/);
  assert.match(dashboard, /data-i18n-updated=/);
  assert.match(dashboard, /<script src="\/dashboard_live\.js"/);
  assert.match(poller, /if \(!r\.ok \|\| d\.error\)/);
  assert.match(poller, /catch \(error\)/);
  assert.match(poller, /document\.hidden/);
  assert.match(poller, /inFlight/);
  assert.match(poller, /i18nRefreshFailed/);
  assert.match(poller, /i18nUpdated/);
  assert.match(poller, /closeDoor\(\)/);
});

test("chat and mission control share accessible Ghostty-inspired session tabs", () => {
  for (const page of [chatIndex, dashboard]) {
    assert.match(page, /class="[^"]*\bmaster-titlebar\b/);
    assert.match(page, /class="master-session-tabs" aria-label=/);
    assert.match(page, /class="master-session-tab"/);
    assert.match(page, /href="\/" /);
    assert.match(page, /href="\/dashboard"/);
  }
  assert.match(chatIndex, /href="\/" aria-current="page"/);
  assert.match(dashboard, /href="\/dashboard" aria-current="page"/);
  assert.match(faceChrome, /\.master-session-tab\[aria-current="page"\]::after/);
  assert.match(faceChrome, /@media \(min-width: 480px\)/);
  assert.match(faceChrome, /\.master-session-tab:focus-visible/);
});

test("canonical theme token reaches CSS, routes and PWA manifest", () => {
  const rootStart = faceCss.indexOf("/* BEGIN:generated-face-root");
  const rootEnd = faceCss.indexOf("/* END:generated-face-root */", rootStart);
  assert.ok(rootStart >= 0 && rootEnd > rootStart, "generated face token block is missing");
  const root = faceCss.slice(rootStart, rootEnd);
  // face_root.palette is the grayscale face; anchors keep the older tinted values.
  assert.match(tokens, /face_bg: "#050505"/);
  assert.match(tokens, /palette:[\s\S]*?x_text: "#E7E7E7"/);
  assert.match(root, /--face-bg: #050505;/);
  assert.match(root, /--x-text: #E7E7E7;/);
  // raw keeps ActionView from HTML-escaping the JSON string's quotes.
  assert.match(pwaManifest, /"background_color": <%= raw theme_color\.to_json %>/);
  assert.match(pwaManifest, /"theme_color": <%= raw theme_color\.to_json %>/);
  for (const page of [chatIndex, dashboard]) {
    assert.match(page, /theme_color = Master\.tokens\.fetch\("face_root"\)\.fetch\("face_bg"\)/);
    assert.match(page, /meta name="theme-color" content="<%= theme_color %>"/);
  }
  assert.match(dashboard, /rel="manifest" href="<%= pwa_manifest_path\(format: :json\) %>"/);
  assert.doesNotMatch(faceMotion, /--c-accent: oklch\(82% 0\.12 222\)/);
  assert.doesNotMatch(faceMotion, /--radius-md: 12px/);
});

test("session chrome is mobile-first, nuanced, flat and touch-ready", () => {
  assert.ok(faceChrome.includes("background: var(--chrome-bg)"));
  assert.ok(faceChrome.includes("background: var(--chrome-surface-active)"));
  assert.ok(faceChrome.includes("outline: 2px solid var(--chrome-focus)"));
  assert.ok(faceChrome.includes('.master-session-tab[aria-current="page"]::after'));
  assert.ok(faceChrome.includes("var(--safe-left)"));
  assert.ok(faceChrome.includes("var(--safe-bottom)"));
  assert.ok(faceChrome.includes("min-block-size: var(--tap-min)"));
  assert.match(faceChrome, /@media \(min-width: 480px\)/);
  assert.match(faceChrome, /prefers-reduced-motion/);
  assert.match(faceChrome, /prefers-reduced-transparency/);
  assert.match(faceChrome, /forced-colors/);
  assert.doesNotMatch(faceChrome, /@media \(max-width:/);
  assert.doesNotMatch(faceChrome, /backdrop-filter\s*:/);
  assert.doesNotMatch(faceChrome, /box-shadow\s*:/);
  assert.doesNotMatch(faceChrome, /border-radius:\s*(?:[1-9]\d*|\d*\.\d+)(?:px|rem|em|%)?/);
  assert.doesNotMatch(faceChrome, /border-(?:block|inline)-end:\s*1px/);
});


test("served face.css is generated from the ordered editable sources", () => {
  const rootStart = faceCss.indexOf("/* BEGIN:generated-face-root");
  const rootMarker = "/* END:generated-face-root */";
  const rootEnd = faceCss.indexOf(rootMarker, rootStart);
  assert.ok(rootStart >= 0 && rootEnd >= 0, "generated token block is missing");
  const rootBlock = faceCss.slice(rootStart, rootEnd + rootMarker.length);
  const partsBlock = faceBuilder.match(/PARTS = %w\[([\s\S]*?)\]/);
  assert.ok(partsBlock, "stylesheet builder source list is missing");
  const parts = partsBlock[1].trim().split(/\s+/);
  assert.ok(parts.includes("60_session_chrome.css"), "session chrome must be in the generated source order");
  const expected = readFileSync(join(root, "styles", "face", parts[0]), "utf8")
    + rootBlock
    + parts.slice(1).map(name => readFileSync(join(root, "styles", "face", name), "utf8")).join("");
  assert.equal(faceCss, expected, "public/face.css drifted from its authoritative source modules");
});
