import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");
const viewsDir = join(root, "app", "views");
// Face assets are declared in config/face_assets.yml and rendered from it, so
// the view no longer spells their names. Read the manifest as text — Node has
// no YAML parser and these are presence checks, not structural ones.
const faceManifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");

function partSources() {
  return [
    readFileSync(join(publicDir, "face.part1.txt"), "utf8"),
    readFileSync(join(publicDir, "face.part2.txt"), "utf8"),
    readFileSync(join(publicDir, "face.part3.txt"), "utf8"),
    readFileSync(join(publicDir, "face_speech_runtime.js"), "utf8"),
    readFileSync(join(publicDir, "face_speech_playback.js"), "utf8"),
    readFileSync(join(publicDir, "face.part5.txt"), "utf8"),
  ];
}

test("face.js loads modules and runtime parts through MASTER_ASSET_PATHS", () => {
  const faceJs = readFileSync(join(publicDir, "face.js"), "utf8");
  const tail = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
  assert.match(faceJs, /MASTER_ASSET_PATHS\?\.faceModules\?\.\[modulePath\]/);
  assert.match(faceJs, /MASTER_ASSET_PATHS\?\.faceModulesList/);
  assert.match(faceJs, /MASTER_ASSET_PATHS\?\.faceRuntime/);
  assert.match(faceJs, /FACE_BLOB_URL/);
  assert.match(tail, /function sendMessage/);
  assert.match(tail, /window\.MASTER_FACE =/);
  assert.match(tail, /_deferFaceMod/);
  assert.doesNotMatch(tail, /await import\('\/face_semantics\.js'\)/);
});

test("face.js builds a blob runtime and rewrites module asset paths", () => {
  const faceJs = readFileSync(join(publicDir, "face.js"), "utf8");
  assert.match(faceJs, /Object\.entries\(MODULE_PATHS\)\.reduce/);
  assert.match(faceJs, /replaceAll/);
  assert.match(faceJs, /URL\.createObjectURL/);
  assert.match(faceJs, /URL\.revokeObjectURL/);
  assert.match(faceJs, /await import\(FACE_BLOB_URL\)/);
});

test("concatenated face parts form a syntactically valid module (guards tap-to-start)", () => {
  // face.js fetches the generated face.runtime.js blob (rake concat of part1-3,
  // speech modules, and part5). A
  // duplicate top-level const (or any syntax error) spanning two parts throws at import
  // time, so window.MASTER_FACE never loads and the primer tap silently does nothing.
  // The per-file assertions above cannot see cross-part collisions — only the join can.
  const blob = partSources().join("\n");
  const tmp = join(tmpdir(), `master-face-blob-${process.pid}.mjs`);
  writeFileSync(tmp, blob);
  try {
    execFileSync(process.execPath, ["--check", tmp], { stdio: "pipe" });
  } catch (err) {
    const detail = err.stderr ? err.stderr.toString() : err.message;
    throw new Error(`concatenated face blob failed syntax check:\n${detail}`);
  } finally {
    rmSync(tmp, { force: true });
  }
});

test("face.modules.bundle.js is generated from face module entry", () => {
  const bundlePath = join(publicDir, "face.modules.bundle.js");
  assert.ok(existsSync(bundlePath), "run rails assets:build_face_modules_bundle");
  const bundle = readFileSync(bundlePath, "utf8");
  assert.match(bundle, /MASTER_FACE_PARTICLES|face_particles/);
  assert.match(bundle, /MASTER_FACE_BLEND|face_blendshape/);
});

test("face_speech_playback.js holds viseme mouth animation", () => {
  const playback = readFileSync(join(publicDir, "face_speech_playback.js"), "utf8");
  const part5 = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
  assert.match(playback, /function startVisemeAnim/);
  assert.match(playback, /MASTER_SPEECH_PLAYBACK/);
  assert.doesNotMatch(part5, /function startVisemeAnim/);
});

test("face_speech_runtime.js holds the TTS implementation", () => {
  const speech = readFileSync(join(publicDir, "face_speech_runtime.js"), "utf8");
  assert.match(speech, /function enqueueSpeech/);
  assert.match(speech, /function ttsTick/);
  // face.part4.txt was a 96-byte "moved to face_speech_runtime.js" stub that
  // the build task never read. This test used to assert the stub did not
  // contain enqueueSpeech, which was true of any file that did not exist.
  assert.ok(!existsSync(join(publicDir, "face.part4.txt")), "the part4 stub is gone");
});

// The generated runtime is built from exactly the sources the rake task lists,
// so a part file that stops being read should stop existing.
test("every face.part*.txt on disk is a source of face.runtime.js", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  for (const name of readdirSync(publicDir).filter((f) => /^face\.part\d+\.txt$/.test(f))) {
    const body = readFileSync(join(publicDir, name), "utf8").trim();
    assert.ok(runtime.includes(body.slice(0, 120)), `${name} is not concatenated into face.runtime.js`);
  }
});

test("calm profile is default and gates rich idle motion", () => {
  const part1 = readFileSync(join(publicDir, "face.part1.txt"), "utf8");
  assert.match(part1, /\['calm', 'full', 'crt', 'battery'\]/);
  assert.match(part1, /function isRichMotionProfile/);
  assert.match(part1, /isRichMotionProfile\(\)\) startStar/);
});

test("face.runtime.js is generated from face parts", () => {
  const runtimePath = join(publicDir, "face.runtime.js");
  assert.ok(existsSync(runtimePath), "run rails assets:build_face_runtime");
  const runtime = readFileSync(runtimePath, "utf8");
  const part1 = readFileSync(join(publicDir, "face.part1.txt"), "utf8").trim();
  assert.match(runtime, /Generated by/);
  assert.ok(runtime.includes(part1.slice(0, 120)), "runtime should include part1 body");
});

// Prefix-includes let a hand-edit in the middle of the generated file slip
// through. The louder-voice change lived in face_speech_runtime.js while the
// browser kept loading a stale face.runtime.js until someone patched the
// artifact by hand. Byte-for-byte with the rake's concat is the only check
// that catches that.
test("face.runtime.js matches the rake concat of its sources", () => {
  const banner = [
    "// Generated by rails assets:build_face_runtime — do not edit by hand.",
    "// Import map + MASTER_ASSET_PATHS resolve tail module imports at runtime.",
    "",
  ].join("\n");
  const expected = `${banner}${partSources().join("\n")}\n`;
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.equal(runtime, expected, "run: cd MASTER/web && bundle exec rails assets:build_face_runtime");
});

test("TTS playback gain is one published number, not leftover copies of 1.9", () => {
  const speech = readFileSync(join(publicDir, "face_speech_runtime.js"), "utf8");
  const bridge = readFileSync(join(publicDir, "face_audio_bridge.js"), "utf8");
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  // One constant feeding both assignments, rather than the literal written
  // twice — this test is named for that and was pinning the duplication.
  assert.match(speech, /const masterGainValue = 19\.0/);
  assert.match(speech, /masterGain\.gain\.value = masterGainValue/);
  assert.match(speech, /tts\.playbackGain = masterGainValue/);
  assert.match(bridge, /TTS_PLAYBACK_GAIN = 19\.0/);
  assert.match(bridge, /tts\.playbackGain \|\| TTS_PLAYBACK_GAIN/);
  assert.match(speech, /setValueAtTime\(tts\.playbackGain/);
  assert.doesNotMatch(speech, /setValueAtTime\(1\.9/);
  assert.doesNotMatch(runtime, /masterGain\.gain\.value = 1\.9/);
  assert.doesNotMatch(runtime, /setValueAtTime\(1\.9/);
});

test("master_namespace exposes canonical MASTER facade getters", () => {
  const ns = readFileSync(join(publicDir, "master_namespace.js"), "utf8");
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(ns, /Object\.defineProperty\(root,\s*name/);
  assert.match(ns, /\["speech"/);
  assert.match(faceManifest, /master_namespace/);
});

test("attention_model loads before face modules", () => {
  const faceJs = readFileSync(join(publicDir, "face.js"), "utf8");
  const attn = readFileSync(join(publicDir, "attention_model.js"), "utf8");
  assert.match(faceJs, /"attention_model\.js"/);
  assert.match(attn, /window\.MASTER\.attention/);
});

test("boot_fsm defines deterministic boot phases before primer tap", () => {
  const fsm = readFileSync(join(publicDir, "boot_fsm.js"), "utf8");
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(fsm, /INIT.*PRIMER.*ASSETS.*FACE.*VOICE.*READY/s);
  assert.match(fsm, /master:boot-state/);
  assert.match(index, /asset_path\("boot_fsm\.js"\)/);
  assert.ok(index.indexOf('asset_path("boot_fsm.js")') < index.indexOf("function go()"));
});

test("chat index inline boot lazy-imports face with status hint, auto-retry, 35s watchdog", () => {
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(index, /MASTER_ASSET_PATHS/);
  assert.match(index, /function loadFace/);
  assert.match(index, /import\("<%= asset_path\("face\.js"\) %>"\)/);
  assert.match(index, /dismissPrimer\(\);\n\s+revealPrompt\(\);/);
  assert.match(index, /window\.__MASTER_PRIMER_TAP__=go/);
  assert.doesNotMatch(index, /DOMContentLoaded.*armPrimer/);
  assert.match(index, /error-live/);
  // NN/g recovery + visibility-of-status UX
  assert.match(index, /still loading the face/);
  assert.match(index, /retrying/);
  assert.match(index, /loadFace\(true\)/);
  assert.match(index, /35000/);
  assert.doesNotMatch(index, /60000/);
  assert.doesNotMatch(index, /15000/);
  assert.doesNotMatch(index, /render "shared\/face_boot"/);
});

test("probe_chat_e2e script covers primer chat and felt state", () => {
  const probe = readFileSync(join(root, "script", "probe_chat_e2e.rb"), "utf8");
  const gemfile = readFileSync(join(root, "Gemfile"), "utf8");
  assert.match(probe, /probe_chat_e2e/);
  assert.match(probe, /run_ping_chat/);
  assert.match(probe, /MASTERFeltState/);
  assert.match(probe, /hasPong/);
  assert.match(probe, /MASTER_FACE\?\.State/);
  assert.match(gemfile, /gem "ferrum"/);
  assert.match(probe, /MAX_PROBE_SECONDS/);
  assert.match(probe, /browser\.go_to\(URL\)/);
});

test("probe_webgl_guard covers before-tap canvas lock and after-tap unlock", () => {
  const probe = readFileSync(join(root, "script", "probe_webgl_guard.mjs"), "utf8");
  const ciProbe = readFileSync(join(root, "script", "ci_web_probe"), "utf8");
  assert.match(probe, /HTMLCanvasElement/);
  assert.match(probe, /getContext/);
  assert.match(probe, /WebGL escaped guard before tap/);
  assert.match(probe, /WebGL unavailable after tap/);
  assert.match(probe, /PROBE_REQUIRE_BROWSER/);
  assert.match(ciProbe, /probe_webgl_guard\.mjs/);
});

test("chat index wires viseme and experimental asset paths", () => {
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(faceManifest, /faceRuntime/);
  assert.match(index, /faceModules/);
  assert.doesNotMatch(index, /faceParts/);
  assert.match(faceManifest, /visemePacks/);
  assert.match(faceManifest, /clusterMiner/);
});

test("visual_bridge emits master:emotion and uses asset paths", () => {
  const bridge = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");
  assert.match(bridge, /master:emotion/);
  assert.match(bridge, /MASTER_ASSET_PATHS\?\.clusterMiner/);
});

test("chat index includes photo attach", () => {
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(index, /id="photo-button"/);
  assert.match(index, /id="photo"/);
  assert.match(index, /chat_upload\.css/);
  assert.doesNotMatch(index, /face_agent_hud/);
});

test("face_research catalog documents ar5iv and github references", () => {
  const research = readFileSync(join(root, "..", "data", "runtime.yml"), "utf8");
  assert.match(research, /2405\.13050/);
  assert.match(research, /2410\.22370/);
  assert.match(research, /open-webui/);
  assert.match(research, /modalities:/);
});

test("chat index wires digested assets around lazy face boot", () => {
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(index, /asset_path\("face\.css"\)/);
  assert.match(index, /asset_path\("face\.js"\)/);
  assert.match(faceManifest, /faceRuntime/);
  assert.match(index, /asset_path\("face_2d_fallback\.js"\).*defer/);
  assert.match(index, /function zshEl/);
  assert.doesNotMatch(index, /getElementById\('zsh'\),ui=document\.getElementById\('ui-status'\)/);
  assert.match(index, /asset_path\("particle_kernel\.js"\)/);
  // Deferred modules come from config/face_assets.yml#shell_manifest, rendered
  // by the view — not a literal list in the ERB.
  assert.match(index, /javascript_include_tag\(\*FaceAssets\.group\("shell_manifest"\)/);
  assert.match(faceManifest, /- chat_actions/);
  assert.match(faceManifest, /- visual_bridge/);
  assert.match(index, /defer: true/);
  assert.doesNotMatch(index, /rel="modulepreload"[^>]+asset_path\("face\.js"\)/);
  assert.doesNotMatch(index, /<link rel="prefetch"[^>]+asset_path\("three\.face\.module\.js"\)/);
  assert.doesNotMatch(index, /<link rel="prefetch"[^>]+asset_path\("face\.js"\)/);
  const particleIdx = index.indexOf('asset_path("particle_kernel.js")');
  const fallbackIdx = index.indexOf('asset_path("face_2d_fallback.js")');
  const primerIdx = index.indexOf('id="primer"');
  const bootIdx = index.indexOf("function go()");
  assert.ok(primerIdx > 0 && bootIdx > primerIdx, "inline boot should follow primer markup");
  assert.ok(fallbackIdx > bootIdx, "face_2d_fallback must not block inline boot before tap wiring");
  assert.ok(particleIdx > 0 && bootIdx > 0, "particle_kernel and inline boot must be present");
});

test("default application layout removed — chat/index owns boot shell", () => {
  const layoutPath = join(viewsDir, "layouts", "application.html.erb");
  assert.equal(existsSync(layoutPath), false, "dead application layout should stay deleted");
});

// The face3d overlay — a second, competing face painter — was removed on
// 2026-07-24 (commit 6f1867972). It took a 2D context on the shared #face
// canvas, and a canvas can only ever hold one context type, so booting it
// permanently blocked the real WebGL face from initializing. These two tests
// used to assert its five source files still behaved; they now assert it stays
// gone, which is the invariant that actually matters.
test("there is exactly one face renderer", () => {
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  const bridge = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");

  for (const gone of ["face3d_preview.js", "face3d_renderer.js", "face3d_geometry.js",
                      "face3d_engine.js", "face3d_support.js"]) {
    assert.ok(!existsSync(join(publicDir, gone)), `${gone} is back`);
  }
  assert.doesNotMatch(index, /face3d/, "no overlay canvas, toggle or asset path");
  assert.doesNotMatch(css, /face3d/, "no styling for a canvas that does not exist");
  assert.doesNotMatch(bridge, /face3d/, "no dynamic import of the removed overlay");
});

// The reason the overlay was a footgun in the first place: #face is bound to
// WebGL by the primary renderer, and a second getContext("2d") on it returns
// null forever after. The 2D placeholder shown while THREE loads is careful to
// use its own canvas — keep it that way.
test("nothing takes a 2D context on the shared #face canvas", () => {
  const fallback = readFileSync(join(publicDir, "face_2d_fallback.js"), "utf8");

  assert.match(fallback, /getElementById\("face-2d-fallback"\)/);
  assert.doesNotMatch(fallback, /getElementById\(["']face["']\)\s*\.getContext/);
});

test("face.css includes subtle visual polish layers", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.doesNotMatch(css, /body::after/);
  assert.match(css, /--face-glow-scale:\s*1\.22/);
  assert.match(css, /mood-sparkline i[\s\S]*--canvas-mood-accent/);
  assert.match(css, /--mood-accent:\s*var\(--c-accent\)/);
  assert.doesNotMatch(css, /speaking.*#zsh \.pp.*--mood-accent/);
});

test("face.css keeps primer and prompt layering stable", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.match(css, /#primer/);
  assert.match(css, /z-index:\s*var\(--z-modal\)/);
  assert.match(css, /body:not\(\.face-ready\) #zsh:not\(\.live\)/);
  assert.match(css, /--x-text:\s*#d8d6e0/);
  assert.match(css, /--face-bg:\s*black/);
  assert.match(css, /body\[data-runtime-profile="calm"\]/);
});

test("face.css meets MASTER design_rules typography and touch baselines", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.match(css, /font:\s*16px\/1\.5/);
  assert.match(css, /"ss03"/);
  assert.match(css, /--face-bar-height:\s*44px/);
  assert.match(css, /\.tool[\s\S]*min-height:\s*44px/);
  assert.match(css, /#spin-btn[\s\S]*min-height:\s*44px/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(css, /#chat-log[\s\S]*font:\s*12px\/1\.42/);
  assert.match(css, /body\.face-loading #zsh:not\(\.live\)/);
  assert.match(css, /body\[data-boot-state="ERROR"\] #zsh-status/);
});

test("visual_bridge connects SSE and normalizes visual events", () => {
  const bridge = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");
  assert.match(bridge, /new EventSource\("\/events\/stream"\)/);
  assert.match(bridge, /MASTERTopology\.classifyEvent/);
  assert.match(bridge, /master:visual/);
  assert.match(bridge, /disconnectSse/);
  assert.doesNotMatch(bridge, /MASTERFace/);
  assert.match(bridge, /MASTER_FACE/);
});

test("ecology render starts RAF and resumes on visual events", () => {
  const ecology = readFileSync(join(publicDir, "cognition_ecology_render.js"), "utf8");
  assert.match(ecology, /ensureEcologyFrame/);
  assert.match(ecology, /addEventListener\("master:visual"/);
  assert.match(ecology, /ecologyFrameActive = false/);
});

test("topology registry exposes canonical classifier", () => {
  const registry = readFileSync(join(publicDir, "topology_registry.js"), "utf8");
  assert.match(registry, /phantom:detected/);
  assert.match(registry, /classifyEvent/);
  assert.match(registry, /bootRemoteTopologies\(\)/);
});

test("chat_actions posts chat stream instead of EventSource GET", () => {
  const actions = readFileSync(join(publicDir, "chat_actions.js"), "utf8");
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(actions, /method:\s*"POST"/);
  assert.match(actions, /\/chat\/message/);
  assert.doesNotMatch(actions, /new EventSource\(/);
  assert.match(actions, /window\.MASTERChat/);
  assert.match(actions, /async function sendMessage/);
  assert.match(actions, /sendMessage,/);
  assert.match(actions, /if \(!window\.sendMessage\) window\.sendMessage = sendMessage/);
  assert.match(runtime, /MASTERChat\.startChatStream/);
  assert.match(runtime, /handleFaceNamedEvent\(event, data\)/);
});

test("face runtime dispatches ready event for deferred vision hooks", () => {
  const part1 = readFileSync(join(publicDir, "face.part1.txt"), "utf8");
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  const vision = readFileSync(join(publicDir, "face_vision_core.js"), "utf8");
  assert.match(part1, /master:face-ready/);
  assert.match(runtime, /master:face-ready/);
  assert.match(vision, /addEventListener\("master:face-ready"/);
});

test("face runtime keeps named SSE reactions on the POST stream path", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(runtime, /function handleFaceNamedEvent/);
  ["mood", "model", "verdict", "council:speech", "confidence", "felt"].forEach((event) => {
    assert.ok(runtime.includes(`event === '${event}'`), `missing named handler for ${event}`);
  });
  assert.match(runtime, /applyPersonaVisual/);
  assert.match(runtime, /MASTER_SSE\?\.dispatchNamed/);
});

test("face runtime keeps chat stream and particle worker boot paths", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(runtime, /function sendMessage/);
  assert.match(runtime, /MASTERChat\.startChatStream/);
  assert.match(runtime, /const url = `\/chat\/message\?message=/);
  assert.match(runtime, /new Worker\('\/particle_worker\.js'\)|new Worker\("\/particle_worker\.js"\)/);
  assert.match(runtime, /window\.MASTER_FACE/);
});

test("tts defaults to server style inference and recovers after fallback cooldown", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  const controller = readFileSync(join(root, "app", "controllers", "tts_controller.rb"), "utf8");
  const chatJs = readFileSync(join(publicDir, "chat.js"), "utf8");
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(runtime, /TTS_STYLE_DEFAULT = 'auto'/);
  assert.match(runtime, /MASTER_VOICE_POLICY/);
  assert.match(runtime, /setTtsHealthStatus/);
  assert.match(runtime, /ttsStreamLiveEnabled/);
  assert.match(runtime, /content_kind/);
  assert.match(runtime, /style_locked/);
  assert.match(runtime, /serverUnavailableUntil/);
  assert.match(runtime, /serverFailureCount/);
  assert.match(runtime, /res\.status === 429/);
  assert.match(runtime, /pullStreamingTtsChunk/);
  assert.match(runtime, /flushStreamTts/);
  assert.match(runtime, /looksLikeListingStream/);
  assert.match(runtime, /shouldSpeakStreamReply/);
  assert.match(runtime, /synthInFlight/);
  assert.doesNotMatch(runtime, /while \(\(m = pending\.match\(SENT_BREAK\)\)/);
  assert.doesNotMatch(chatJs, /osman/);
  assert.match(index, /MASTER_VOICE_POLICY/);
  assert.doesNotMatch(controller, /params\[:style\]\.present\?/);
  assert.doesNotMatch(controller, /params\[:voice\]\.present\?/);
  assert.match(controller, /Voice::Policy\.single_voice_key/);
});

test("dynamic welcome greeting fires once after face boot via the real chat pipeline", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  // Generated by the actual model through startChatStream, not a canned string --
  // distinguishes this from the static /whoami summary.
  assert.match(runtime, /function sendWelcomeGreeting/);
  assert.match(runtime, /WELCOME_GREETING_PROMPT/);
  assert.match(runtime, /world's first AI built entirely in pure Ruby/);
  assert.match(runtime, /_welcomeGreetingSent/);
  assert.match(runtime, /_welcomeGreetingTries/);
  // Retries until MASTERChat arrives instead of a one-shot early return that
  // lost the race and never spoke. The 700ms kickoff from startEverything is
  // still there; the 250ms retry is the wait.
  assert.match(runtime, /if \(!window\.MASTERChat\?\.startChatStream\)/);
  assert.match(runtime, /setTimeout\(sendWelcomeGreeting, 250\)/);
  assert.match(runtime, /setTimeout\(sendWelcomeGreeting, 700\)/);
});

test("voice mode: re-arm loop, exit phrase, wake word, and browser-first TTS routing", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  const index = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  // Continuous re-arm loop keyed off recognition.onend, not a fixed interval —
  // must re-check State.voiceMode each cycle rather than assuming it stays on.
  assert.match(runtime, /if \(State\.voiceMode\) \{[\s\S]{0,400}startSTT\(\);/);
  // Exit phrase is checked client-side before sendMessage, no server round-trip.
  assert.match(runtime, /EXIT_PHRASE_RE/);
  assert.match(runtime, /stop listening/);
  // Wake word is opt-in (URL param or localStorage), not on by default.
  assert.match(runtime, /WAKE_PHRASE_RE/);
  assert.match(runtime, /function wakeWordEnabled/);
  assert.match(runtime, /master:wake-word/);
  // iOS Safari degradation guard: bail out of the loop rather than spinning
  // forever if recognition keeps ending near-instantly with no speech.
  assert.match(runtime, /_voiceModeRearmFails/);
  // Voice Mode defaults to instant browser TTS; high-quality voice is opt-in
  // and explicitly does NOT change behavior outside Voice Mode.
  assert.match(runtime, /function highQualityVoiceEnabled/);
  assert.match(runtime, /State\.voiceMode && !highQualityVoiceEnabled\(\)/);
  assert.match(runtime, /master:voice-mode-hq/);
  // Mic button was removed: Voice Mode is hands-free by default, so the
  // dedicated control was redundant chrome. Confirm it's actually gone.
  assert.doesNotMatch(index, /data-act="mic"/);
  assert.doesNotMatch(runtime, /data-act="mic"/);
  // STT/TTS echo regression: continuous SpeechRecognition has no echo
  // cancellation against this page's own TTS audio, so an open mic during
  // playback transcribed the assistant's own reply and resubmitted it as a
  // new user message -- reported as the assistant "randomly saying facts."
  // ttsTick() must duck the mic while speaking and only resume it via
  // resumeSttAfterSpeech() once the queue empties -- and that function must
  // actually be defined (it previously wasn't, only called, which would
  // throw ReferenceError the first time a reply finished playing).
  assert.match(runtime, /function resumeSttAfterSpeech/);
  assert.match(runtime, /if \(!text\) \{ resumeSttAfterSpeech\(\); return; \}/);
  assert.match(runtime, /tts_tick_stt_duck/);
  assert.match(runtime, /State\.voiceMode && !tts\.playing/);
  assert.match(runtime, /State\.wakeArmed && !State\.voiceMode && !tts\.playing/);
});

test("service worker avoids stale undigested precache", () => {
  const sw = readFileSync(join(publicDir, "sw.js"), "utf8");
  assert.doesNotMatch(sw, /\/face\.js'/);
  assert.doesNotMatch(sw, /\/chat\.js'/);
  assert.match(sw, /OFFLINE_URL/);
  assert.match(sw, /Never cache digested/);
  assert.match(sw, /pathname\.startsWith\('\/assets\/'\)/);
});
