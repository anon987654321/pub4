import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");
const viewsDir = join(root, "app", "views");
// Face assets are declared in config/face_assets.yml and rendered from it, so
// the view no longer spells their names. Read the manifest as text — Node has
// no YAML parser and these are presence checks, not structural ones.
const faceManifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");



function sourceSetDigest(relativePaths) {
  const hash = createHash("sha256");
  for (const relativePath of [...relativePaths].sort()) {
    hash.update(readFileSync(join(root, relativePath)));
    hash.update("\0");
  }
  return hash.digest("hex");
}

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

test("face surface owns the full viewport", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  const view = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  assert.match(css, /#face\s*\{[\s\S]*?inset:\s*0;/);
  assert.match(css, /#face\s*\{[\s\S]*?width:\s*100dvw;/);
  assert.match(css, /#face\s*\{[\s\S]*?height:\s*100dvh;/);
  assert.doesNotMatch(css, /#face\s*\{[^}]*min-height:\s*44vh/);
  assert.match(view, /<canvas id="face"/);
});

test("MASTER web face uses the same monospaced presentation contract as the CLI", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  const rules = readFileSync(join(root, "..", "data", "laws.yml"), "utf8");
  assert.match(css, /html, body[\s\S]*font:\s*16px\/1\.5 var\(--font-mono\)/);
  assert.match(css, /--font-label:\s*"JetBrainsMono Nerd Font"/);
  assert.match(rules, /face_interface:/);
  assert.match(rules, /prompt:\s*\n\s+font: font_code/);
});

test("FaceWorld keeps portrait rendering separate from repository overlays", () => {
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  assert.match(world, /const portrait = topology === "face" \|\| topology === "papua-mask";/);
  assert.match(world, /node\.visible = !portrait/);
  assert.match(world, /edges\.visible = !portrait/);
  assert.match(world, /splatProxy\.visible = !portrait/);
  assert.match(world, /sprite\.visible = !portrait/);
  assert.match(world, /jawTaper/);
  assert.match(world, /cheekFull/);
  assert.match(world, /const breath = Math\.sin/);
});

test("FaceWorld consumes the semantic layers and bounded render budget", () => {
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  const state = readFileSync(join(publicDir, "face_state.js"), "utf8");
  assert.match(world, /LAYER_NAMES/);
  assert.match(world, /master-face-layer-\$\{name\}/);
  assert.match(world, /renderBudget/);
  assert.match(world, /spawnPulse/);
  assert.match(state, /mobile_points/);
  assert.match(state, /max_device_pixel_ratio/);
});

test("Face state derives modes and aliases from the shared contract", () => {
  const state = readFileSync(join(publicDir, "face_state.js"), "utf8");
  const rules = readFileSync(join(root, "..", "data", "laws.yml"), "utf8");
  assert.match(state, /CONTRACT_STATE\.modes/);
  assert.match(state, /Object\.entries\(CONTRACT\.mode_aliases/);
  assert.match(state, /mobile_particles/);
  assert.match(state, /reduced_motion_fps/);
  assert.match(rules, /desktop_particles: 200/);
  assert.match(rules, /active_fps: 24/);
});

test("FaceWorld owns camera impulses and actual point draw range", () => {
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  const part1 = readFileSync(join(publicDir, "face.part1.txt"), "utf8");
  const part2 = readFileSync(join(publicDir, "face.part2.txt"), "utf8");
  const part3 = readFileSync(join(publicDir, "face.part3.txt"), "utf8");
  assert.match(world, /cameraZoomAt/);
  assert.match(world, /camera\.fov/);
  assert.match(world, /setDrawRange\(0, activePoints\)/);
  assert.match(world, /CanvasTexture/);
  assert.match(part1, /FACE_CAMERA_DISTANCE/);
  assert.match(part1, /faceRenderDpr/);
  assert.match(part1, /budgetScale/);
  assert.match(part2, /particleBudget/);
  assert.match(part2, /mouthCapacity/);
  assert.match(part2, /State\.cameraZoomAt/);
  assert.doesNotMatch(part2, /requestAnimationFrame\(forward\)/);
  assert.doesNotMatch(part3, /camera\.position\.z \+=/);
});

test("installed MASTER PWA prefers fullscreen display", () => {
  const manifest = readFileSync(join(viewsDir, "pwa", "manifest.json.erb"), "utf8");
  assert.match(manifest, /"display":\s*"fullscreen"/);
  assert.match(manifest, /"display_override":\s*\["fullscreen"/);
});

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

test("live TTS does not delay short completed sentences", () => {
  const part1 = readFileSync(join(publicDir, "face.part1.txt"), "utf8");
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(part1, /function pushLiveStreamTts/);
  assert.match(part1, /const chunk = m\[0\]\.trim\(\);/);
  assert.doesNotMatch(part1, /chunk\.length < TTS_MIN_CHUNK/);
  assert.doesNotMatch(runtime, /chunk\.length < TTS_MIN_CHUNK/);
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

test("TTS playback gain is one published number, and fits under 0 dBFS", () => {
  const speech = readFileSync(join(publicDir, "face_speech_runtime.js"), "utf8");
  const bridge = readFileSync(join(publicDir, "face_audio_bridge.js"), "utf8");
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  // One constant feeding both assignments, rather than the literal written
  // twice — this test is named for that and was pinning the duplication. The
  // level itself moved into data/voice.yml's chain, so what is pinned here is
  // that the graph and the duck read the same published value: unity while the
  // chain carries the level, 1.9 on the bare fallback path, never a second copy.
  assert.match(speech, /const masterGainValue = chain \? 1\.0 : 1\.9/);
  assert.match(speech, /masterGain\.gain\.value = masterGainValue/);
  assert.match(speech, /tts\.playbackGain = masterGainValue/);
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
// Not /HTMLCanvasElement/. The probe used to name the class because it
// patched the prototype; it now asks a canvas it did not have before the
// tap — document.createElement("canvas") inside the after block — which is
// the stronger proof, since a guard that only covers the one element on the
// page is not a guard. The assertion was measuring the old spelling of a
// check that had got better.
assert.match(probe, /createElement\("canvas"\)/);
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

test("face runtime consumes the constitutional state contract", () => {
  const contract = readFileSync(join(root, "..", "data", "laws.yml"), "utf8");
  const state = readFileSync(join(publicDir, "face_state.js"), "utf8");
  const index = readFileSync(join(root, "app", "views", "chat", "index.html.erb"), "utf8");
  assert.match(contract, /face_interface:[\\s\\S]*schema: 1/);
  assert.match(contract, /mode_aliases:[\\s\\S]*phantom: error/);
  assert.match(state, /MASTER_FACE_CONTRACT/);
  assert.match(state, /CONTRACT_STATE\.modes/);
  assert.match(state, /MASTERTopology\.classifyEvent/);
  assert.match(index, /MASTER_FACE_CONTRACT = <%= raw/);
});

test("face.js has no second fallback module list", () => {
  const source = readFileSync(join(publicDir, "face.js"), "utf8");
  assert.match(source, /MASTER_ASSET_PATHS\?\.faceModulesList/);
  assert.doesNotMatch(source, /|| \[\s*"attention_model\.js"/);
});

test("obsolete point renderer stays absent", () => {
  const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
  const loader = readFileSync(join(publicDir, "face_deferred_loader.js"), "utf8");
  assert.doesNotMatch(manifest, /face_points_gl\.js/);
  assert.doesNotMatch(loader, /face_points_gl\.js/);
  assert.doesNotMatch(readFileSync(join(publicDir, "face_world.js"), "utf8"), /new THREE\.WebGLRenderer/);
  assert.doesNotMatch(readFileSync(join(publicDir, "face_world.js"), "utf8"), /requestAnimationFrame/);
});

test("face.css carries no knob for a glow that no longer exists", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.doesNotMatch(css, /body::after/);
  // This used to assert --face-glow-scale: 1.22, pinning the additive halo pass
  // in place. The pass is gone and particle size is fixed at one pixel by
  // FACE_POINT_IS_ONE_PIXEL, so both vars are asserted absent instead — a knob
  // whose only legal value is its default is not a knob.
  assert.doesNotMatch(css, /--face-glow-scale/);
  assert.doesNotMatch(css, /--face-particle-size/);
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

test("MASTER web and CLI share one monospaced face contract", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  const rules = readFileSync(join(root, "..", "data", "laws.yml"), "utf8");
  assert.match(rules, /face_root:[\s\S]*font_label:.*JetBrainsMono/);
  assert.match(css, /--font-label:\s*"JetBrainsMono/);
  assert.match(css, /html, body[\\s\\S]*font:\s*16px\\/1\\.5 var\\(--font-mono\\)/);
  assert.doesNotMatch(css, /var\(--font-label\)/, "MASTER face may not fall back to a second typography contract");
  assert.match(css, /message\\.user,\\s*\\nmessage\\.assistant[\\s\\S]*border:\s*0;[\\s\\S]*background:\s*transparent/);
  assert.match(css, /#chat-log[\\s\\S]*max-inline-size:\s*66ch/);
});

test("FaceWorld is one renderer projection, not a second renderer", () => {
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
  const part3 = readFileSync(join(publicDir, "face.part3.txt"), "utf8");
  const part5 = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
  assert.match(manifest, /- face_world\.js/);
  assert.match(world, /window\.MASTER_FACE_WORLD/);
  assert.match(world, /master-sdf-shell/);
  assert.match(world, /master-splat-field/);
  assert.match(world, /master-node-lib/);
  assert.doesNotMatch(world, /new THREE\.WebGLRenderer/);
  assert.doesNotMatch(world, /new THREE\.Scene/);
  assert.doesNotMatch(world, /requestAnimationFrame/);
  assert.match(part3, /MASTER_FACE_WORLD\?\.update\?\.\(performance\.now\(\)\)/);
  assert.match(part5, /get scene\(\) \{ return scene; \}/);
  assert.match(part5, /get camera\(\) \{ return camera; \}/);
});

test("face.css meets MASTER design_rules typography and touch baselines", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.match(css, /font:\s*16px\/1\.5/);
  assert.match(css, /"ss03"/);
  assert.match(css, /--face-bar-height:\s*44px/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(css, /#chat-log[\s\S]*font:\s*1rem\/1\.5 var\(--font-mono\)/);
  assert.match(css, /body\.face-loading #zsh:not\(\.live\)/);
  assert.match(css, /body\[data-boot-state="ERROR"\] #zsh-status/);
});

// .tool already uses --tap-min (44px). The skipped assertion demanded a
// literal 44px, which would have punished the token the rest of this file
// treats as the source of truth.
test("face.css gives .tool a tap-min touch target", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.match(css, /^\.tool \{[^}]*min-height:\s*var\(--tap-min\)/m);
});

// .mood-sparkline is gone from face.css and from every face HTML/JS file.
// The accent token remaining on a class nothing renders would be a ghost.
test("face.css does not keep a retired mood sparkline", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.doesNotMatch(css, /\.mood-sparkline/);
});

test("face prompt docks above the visual-viewport keyboard inset", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  assert.match(css, /#zsh \{[^}]*inset-block-end:\s*var\(--keyboard-inset/s);
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

test("visual layers consume the canonical face frame", () => {
  const ecology = readFileSync(join(publicDir, "cognition_ecology_render.js"), "utf8");
  const gravity = readFileSync(join(publicDir, "gravity_field.js"), "utf8");
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  assert.match(ecology, /MASTEREcologyRender = Object\.freeze\(\{ update \}\)/);
  assert.match(gravity, /MASTER_GRAVITY_FIELD = Object\.freeze\(\{ update, resize, signal \}\)/);
  assert.doesNotMatch(ecology, /requestAnimationFrame/);
  assert.doesNotMatch(gravity, /requestAnimationFrame/);
  assert.match(world, /MASTEREcologyRender\?\.update/);
  assert.match(world, /MASTER_GRAVITY_FIELD\?\.update/);
});

test("topology registry exposes canonical classifier", () => {
  const registry = readFileSync(join(publicDir, "topology_registry.js"), "utf8");
  assert.match(registry, /phantom:detected/);
  assert.match(registry, /classifyEvent/);
  assert.match(registry, /bootRemoteTopologies\(\)/);
});

test("chat_actions retains interrupted transport failures without duplicating partial replies", () => {
  const actions = readFileSync(join(publicDir, "chat_actions.js"), "utf8");
  assert.match(actions, /function transportFailure\(err\)/);
  assert.match(actions, /async function queueTransportFailure\(message, err, assistantText\)/);
  assert.match(actions, /if \(assistantText\?\.trim\(\)\) return false;/);
  assert.match(actions, /if \(!transportFailure\(err\)\) return false;/);
  assert.match(actions, /queueTransportFailure\(message, err, assistantBuffer\)/);
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

test("web face is an evolved rendering of the CLI face", () => {
  const part3 = readFileSync(join(publicDir, "face.part3.txt"), "utf8");
  const cliFace = readFileSync(join(root, "..", "lib", "cli", "face.rb"), "utf8");
  assert.match(cliFace, /GREYS = \(232\.\.255\)/);
  assert.match(cliFace, /SPECK_LIGHT/);
  assert.match(part3, /CLI_FACE_WEB_DENSITY = 2400/);
  assert.match(part3, /orbitalField = new THREE\.Points/);
  assert.match(part3, /size: 1/);
});

test("face runtime keeps chat stream and particle worker boot paths", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(runtime, /function sendMessage/);
  assert.match(runtime, /MASTERChat\.startChatStream/);
  assert.doesNotMatch(runtime, /new EventSource\(/, "the face sends through chat_actions' POST stream only");
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

// There is no welcome greeting: MASTER speaks when spoken to. It was removed
// deliberately, and face.part5.txt records why — it fired on every page load
// rather than after a human tap, the web session is process-global so the
// instruction landed in whatever conversation was already running, and because
// it was a real chat turn the model kept seeing "introduce yourself" in recent
// history and doing it unprompted.
//
// This test asserted the greeting existed and had been failing ever since,
// unnoticed, because nothing ran this file. It asserts the absence now, so
// re-adding a greeting has to be a decision rather than a regression.
test("no welcome greeting: MASTER speaks when spoken to", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  // Matching the bare identifier finds the comment that explains the removal,
  // so these look for the code shapes instead.
  assert.doesNotMatch(runtime, /^\s*function sendWelcomeGreeting/m);
  assert.doesNotMatch(runtime, /^\s*const WELCOME_GREETING_PROMPT/m);
  assert.doesNotMatch(runtime, /setTimeout\(sendWelcomeGreeting,/);
});

test("voice mode arms from a real gesture and reports microphone startup truthfully", () => {
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  const part5 = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
  assert.match(part5, /function listenOnFirstGesture/);
  assert.match(part5, /enterVoiceMode\(\{ fromAuto: true, fromGesture: true \}\)/);
  assert.match(part5, /listenOnFirstGesture\(\);/);
  assert.match(runtime, /recognition\.onstart = \(\) => \{/);
  assert.match(runtime, /stt_start_timeout/);
  assert.match(runtime, /mic did not start — tap again/);
});

test("TTS does not dequeue speech while the server cooldown is active", () => {
  const speech = readFileSync(join(publicDir, "face_speech_runtime.js"), "utf8");
  const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");
  assert.match(speech, /const unavailableUntil = Number\(tts\.serverUnavailableUntil \|\| 0\)/);
  assert.match(speech, /scheduleTtsTick\(Math\.max\(250, unavailableUntil - Date\.now\(\)\)\)/);
  assert.match(runtime, /const unavailableUntil = Number\(tts\.serverUnavailableUntil \|\| 0\)/);
  assert.match(runtime, /if \(tts\.serverUnavailable && Date\.now\(\) < unavailableUntil\)/);
});

test("voice mode: re-arm loop, exit phrase, wake word, and single-speaker TTS routing", () => {
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
  // Server TTS is the sole speech backend. A reply waits on the same queue for
  // synthesis and playback instead of racing a second OS/browser narrator.
  assert.match(runtime, /function ttsTick/);
  assert.match(runtime, /loadTTSBlob\(text, voice, style\)/);
  assert.match(runtime, /tts\.serverUnavailable/);
  assert.doesNotMatch(runtime, /function highQualityVoiceEnabled/);
  assert.doesNotMatch(runtime, /master:voice-mode-hq/);
  assert.doesNotMatch(runtime, /browserTtsEmergencyAllowed/);
  assert.doesNotMatch(runtime, /speakWithBrowserTTS/);
  assert.doesNotMatch(runtime, /speechSynthesis\.speak\(/);
  assert.doesNotMatch(runtime, /new SpeechSynthesisUtterance/);
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

test("web face keeps filesystem access at the user-upload boundary only", () => {
  const sources = [
    readFileSync(join(publicDir, "face.js"), "utf8"),
    readFileSync(join(publicDir, "face.runtime.js"), "utf8"),
    readFileSync(join(publicDir, "face_world.js"), "utf8"),
    readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8"),
  ].join("\n");
  for (const api of [
    "showOpenFilePicker",
    "showSaveFilePicker",
    "showDirectoryPicker",
    "FileSystemHandle",
    "FileSystemFileHandle",
    "FileSystemDirectoryHandle",
  ]) {
    assert.doesNotMatch(sources, new RegExp(api), api + " must not become a MASTER web capability");
  }
  assert.match(sources, /id="photo"/, "explicit user-selected photo upload remains the only file boundary");
});

test("service worker avoids stale undigested precache", () => {
  const sw = readFileSync(join(publicDir, "sw.js"), "utf8");
  assert.doesNotMatch(sw, /\/face\.js'/);
  assert.doesNotMatch(sw, /\/chat\.js'/);
  assert.match(sw, /OFFLINE_URL/);
  assert.match(sw, /Never cache digested/);
  assert.match(sw, /pathname\.startsWith\('\/assets\/'\)/);
});

test("Android wake reaches the existing face event pipe", () => {
  const bridge = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");
  const events = readFileSync(join(root, "app", "controllers", "events_controller.rb"), "utf8");
  const wake = readFileSync(join(root, "..", "lib", "device", "wake_signal.rb"), "utf8");
  assert.match(bridge, /type === "device:wake"/);
  assert.match(bridge, /master:wake/);
  assert.match(bridge, /mode: "wake"/);
  assert.match(events, /WakeSignal/);
  assert.match(events, /stream_started_at/);
  assert.match(wake, /File\.rename/);
});


test("generated face bundles publish the source-set digest they were built from", () => {
  const visionSources = [
    "public/face_vision_core.js",
    "public/face_vision_a.js",
    "public/face_vision_b.js",
    "public/face_vision_c.js",
    "public/face_vision_d.js",
  ];
  const moduleSources = [
    "script/face_modules_entry.js",
    "public/face_blendshape_bridge.js",
    "public/face_particles.js",
    "public/face_audio_bridge.js",
    "public/face_tts_bridge.js",
    "public/face_expression_bridge.js",
    "public/face_council_multi.js",
    "public/face_phosphor_trail.js",
    "public/face_micro_interactions.js",
    "public/face_perf_guards.js",
    "public/face_brutalist.js",
  ];
  const visionDigest = sourceSetDigest(visionSources);
  const moduleDigest = sourceSetDigest(moduleSources);
  const vision = readFileSync(join(publicDir, "face_vision.bundle.js"), "utf8");
  const modules = readFileSync(join(publicDir, "face.modules.bundle.js"), "utf8");

  assert.match(vision, new RegExp("SOURCE-SET-SHA256:\\s*" + visionDigest));
  assert.match(modules, new RegExp("SOURCE-SET-SHA256:\\s*" + moduleDigest));
});

test("MASTER face markup hooks have owned styling", () => {
  const css = readFileSync(join(publicDir, "face.css"), "utf8");
  const view = readFileSync(join(viewsDir, "chat", "index.html.erb"), "utf8");
  for (const hook of [".brand-mark", ".brand-text", ".mic-indicator"]) {
    assert.match(view, new RegExp(hook.replace(".", "\\.")));
    assert.match(css, new RegExp(hook.replace(".", "\\.") + "\\s*\\{"));
  }
  assert.match(css, /body\[data-mode="listening"\] \.mic-indicator/);
});
