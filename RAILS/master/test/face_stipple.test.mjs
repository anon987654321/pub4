import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");
const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
const system = readFileSync(join(publicDir, "face_stipple_system.js"), "utf8");
const playground = readFileSync(join(publicDir, "face_playground.js"), "utf8");
const css = readFileSync(join(publicDir, "face.css"), "utf8");
const faceStateSource = readFileSync(join(publicDir, "face_state.js"), "utf8");
const faceWorld = readFileSync(join(publicDir, "face_world.js"), "utf8");
const sparseField = readFileSync(join(publicDir, "face_sparse_field.js"), "utf8");
const microInteractions = readFileSync(join(publicDir, "face_micro_interactions.js"), "utf8");
const faceParticles = readFileSync(join(publicDir, "face_particles.js"), "utf8");
const phosphorTrail = readFileSync(join(publicDir, "face_phosphor_trail.js"), "utf8");

test("shared face budgets classify coarse pointers and declared reduced motion", () => {
  assert.match(faceStateSource, /mediaMatches\("\(pointer: coarse\)"\)/);
  assert.match(faceStateSource, /function reducedMotionEnabled\(snapshotValue = state\)/);
  assert.match(faceStateSource, /reducedMotion: reducedMotionEnabled/);
  assert.match(faceStateSource, /const mediaQueryCache = new Map\(\)/);
  assert.match(faceStateSource, /window\.MASTER_FACE\?\.State\?\.reducedMotion/);
  assert.match(faceStateSource, /dataset\?\.reducedMotion === "1"/);
  assert.match(sparseField, /function reducedMotionEnabled\(state = \{\}\)/);
  assert.match(sparseField, /MASTER_FACE_STATE\?\.reducedMotion/);
  assert.match(sparseField, /window\.MASTER_FACE\?\.State\?\.reducedMotion/);
  assert.match(sparseField, /window\.matchMedia\?\.\("\(pointer: coarse\)"\)/);
  assert.match(sparseField, /const reduced = reducedMotionEnabled\(state\)/);
});

test("stipple discovery accepts Group containers with point children", () => {
  assert.match(system, /function hasFacePoints\(node\)/);
  assert.match(system, /scene\.children\.some\(hasFacePoints\)/);
  assert.match(system, /scene\.children\.find\(hasFacePoints\)/);
});

test("particle emissions share the canonical reduced-motion policy", () => {
  let reduced = true;
  let spawns = 0;
  const listeners = new Map();
  const window = {
    MASTER_FACE_STATE: { reducedMotion: () => reduced },
    ParticleKernel: { spawn: () => { spawns += 1; } },
    addEventListener: (name, callback) => listeners.set(name, callback)
  };
  const performance = { now: () => 1000 };
  const document = { documentElement: { dataset: { reducedMotion: "0" } } };
  runInNewContext(faceParticles, { window, document, performance, matchMedia: () => ({ matches: false }) });
  listeners.get("audio:update")({ detail: { onset: 0.9, mid: 0.5, bass: 0.5, high: 0.3, rms: 0.2 } });
  const state = { reducedMotion: false, confidence: 0.9, pressureFields: {}, emotionalGhosts: [] };
  const pool = {};
  window.MASTER_FACE_PARTICLES.reactAudio(state, pool);
  window.MASTER_FACE_PARTICLES.spawnEmotionalGhost(state, pool, "thinking");
  assert.equal(spawns, 0);
  reduced = false;
  window.MASTER_FACE_PARTICLES.reactAudio(state, pool);
  window.MASTER_FACE_PARTICLES.spawnEmotionalGhost(state, pool, "thinking");
  assert.ok(spawns > 0);
});

test("phosphor afterimage capture stops when canonical reduced motion is active", () => {
  let reduced = true;
  let draws = 0;
  let creations = 0;
  const context = {
    globalCompositeOperation: "source-over", globalAlpha: 1, fillStyle: "",
    drawImage() { draws += 1; }, fillRect() {},
  };
  const body = { dataset: { runtimeProfile: "calm" }, appendChild() {} };
  const document = {
    body, documentElement: { dataset: { aesthetic: "", reducedMotion: "0" } },
    createElement() { creations += 1; return { id: "", style: {}, width: 0, height: 0, getContext: () => context }; }
  };
  const window = {
    MASTER_FACE_STATE: { snapshot: () => ({}), reducedMotion: () => reduced },
    addEventListener() {}
  };
  runInNewContext(phosphorTrail, { window, document, matchMedia: () => ({ matches: false }) });
  window.MASTER_PHOSPHOR_TRAIL.capture({ width: 32, height: 32 });
  assert.equal(draws, 0);
  assert.equal(creations, 0);
  assert.equal(window.MASTER_PHOSPHOR_TRAIL.reducedMotion(), true);
  reduced = false;
  window.MASTER_PHOSPHOR_TRAIL.capture({ width: 32, height: 32 });
  assert.equal(draws, 1);
  assert.equal(creations, 1);
});

test("micro-interactions remove continuous motion and crown spawns under reduced motion", () => {
  assert.match(microInteractions, /function reducedMotionActive\(state = st\(\)\)/);
  assert.match(microInteractions, /if \(reducedMotionActive\(\)\) return/);
  assert.doesNotMatch(microInteractions, /phase \+= 0\.08/);
  assert.match(microInteractions, /ecology\?\.agents \|\| reducedMotionActive\(\)/);
  assert.match(microInteractions, /cv\.addEventListener\("pointermove", \(e\) => \{\s*if \(reducedMotionActive\(\)\) return;/);
  let spawns = 0;
  let reduced = true;
  const pool = { count: 1, alive: new Uint8Array([1]), cells: new Float32Array(16) };
  const window = {
    MASTER_FACE_STATE: { reducedMotion: () => reduced },
    MASTER_FACE: { State: { reducedMotion: false }, eyePool: pool, mouthPool: pool },
    ParticleKernel: { spawn: () => { spawns += 1; }, FIELDS_PER_CELL: 16, FIELD: { attention: 0, pressure: 1 } },
    addEventListener() {}, dispatchEvent() {}
  };
  const document = { getElementById: () => null, documentElement: { dataset: { reducedMotion: "1" } } };
  runInNewContext(microInteractions, {
    window, document, matchMedia: () => ({ matches: false }),
    setInterval() { return 1; },
    CustomEvent: class CustomEvent { constructor(type, options = {}) { this.type = type; this.detail = options.detail; } }
  });
  window.MASTER_FACE_MICRO.spawnCrown(3);
  assert.equal(spawns, 0);
  reduced = false;
  window.MASTER_FACE_MICRO.spawnCrown(3);
  assert.equal(spawns, 3);
});

test("micro and nano expressions reuse blendshapes and respect reduced motion", () => {
  const listeners = new Map();
  const expressions = [];
  const state = { mode: "thinking", valence: 0.2, arousal: 0.3, eyeMaskBiasX: 0, eyeMaskBiasY: 0 };
  let reduced = false;
  const pool = { count: 0, alive: new Uint8Array(0), cells: new Float32Array(0) };
  const window = {
    MASTER_FACE_STATE: { reducedMotion: () => reduced },
    MASTER_FACE: { State: state, eyePool: pool, mouthPool: pool },
    MASTER_FACE_BLEND: { applyExpression: (value) => expressions.push(value), applyMouthDrive() {} },
    ParticleKernel: { FIELDS_PER_CELL: 16, FIELD: { attention: 0, pressure: 1 }, spawn() {} },
    MASTEREcology: { agents: [] },
    addEventListener(name, callback) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(callback);
    },
    dispatchEvent() {}
  };
  const document = { getElementById: () => null, documentElement: { dataset: { reducedMotion: "0", masterMode: "thinking" }, style: { getPropertyValue: () => "0.86" } } };
  runInNewContext(microInteractions, {
    window, document, matchMedia: () => ({ matches: false }), innerWidth: 1000, innerHeight: 800,
    setInterval() { return 1; },
    CustomEvent: class CustomEvent { constructor(type, options = {}) { this.type = type; this.detail = options.detail; } }
  });
  for (const listener of listeners.get("master:visual") || []) listener({ detail: { mode: "thinking" } });
  assert.ok(expressions.length > 0);
  assert.ok(Math.abs(state.eyeMaskBiasX) <= 0.035);
  assert.ok(Math.abs(state.eyeMaskBiasY) <= 0.035);
  const count = expressions.length;
  reduced = true;
  for (const listener of listeners.get("master:visual") || []) listener({ detail: { mode: "speaking" } });
  assert.equal(expressions.length, count);
  assert.ok(Math.abs(state.eyeMaskBiasX) <= 0.035);
});

test("FaceWorld observes reduced motion across shader, camera and event layers", () => {
  assert.match(faceWorld, /function reducedMotionEnabled\(state = \{\}\)/);
  assert.match(faceWorld, /MASTER_FACE_STATE\?\.reducedMotion/);
  assert.match(faceWorld, /window\.MASTER_FACE\?\.State\?\.reducedMotion/);
  assert.match(faceWorld, /document\.documentElement\?\.dataset\?\.reducedMotion === "1"/);
  assert.match(faceWorld, /window\.matchMedia\?\.\("\(prefers-reduced-motion: reduce\)"\)/);
  assert.match(faceWorld, /const reducedMotion = reducedMotionEnabled\(state\)/);
  assert.match(faceWorld, /shellMaterial\.uniforms\.uTime\.value = reducedMotion \? 0 : now/);
  assert.match(faceWorld, /audioPulse = reducedMotion \? 0 : Math\.max/);
  assert.match(faceWorld, /\(reducedMotion \? 0 : audioEnergy\) \* 0\.12/);
  assert.match(faceWorld, /function updateActivityNodes\(now, state, reducedMotion = false\)/);
  assert.match(faceWorld, /reducedMotion \? 0 : now \* orbitSpeed/);
  assert.match(faceWorld, /!reducedMotion && active \? 0\.12 \*/);
  assert.match(faceWorld, /terminalFade = !reducedMotion && record\.terminalAt/);
  assert.match(faceWorld, /updatePulses\(now, reducedMotion\)/);
  assert.match(faceWorld, /const rotationEase = reducedMotion \? 1 : 0\.035/);
  assert.match(faceWorld, /const cameraEase = reducedMotion \? 1 : 0\.035/);
});

function loadFaceStateBudget({ coarsePointer = false, narrowViewport = false, cores = 8, reducedMotion = false, faceMotion = false, prefersReducedMotion = false, hidden = false } = {}) {
  const window = {
    MASTER_FACE_CONTRACT: {
      state: {
        modes: ["idle", "listening", "thinking", "working", "speaking", "warning", "error", "sleeping", "ready"],
        default_mode: "idle", default_topology: "face", entropy: 0.18, confidence: 0.86,
        attention: 1, arousal: 0.22, valence: 0.18, focus: 0.86, activity: 0.14, risk: 0
      },
      spatial: { budget: {
        point_allocation: { stipple_fraction: 0.75, world_fraction: 0.25 },
        desktop_points: 1200, mobile_points: 420, desktop_particles: 200, mobile_particles: 120,
        reduced_motion_particles: 64, max_device_pixel_ratio: 2, active_fps: 24, idle_fps: 12,
        hidden_fps: 0, reduced_motion_fps: 8, battery_fps: 12, pulse_limit: 24, hud_labels: 5
      } }
    },
    MASTER_FACE: { State: { reducedMotion: faceMotion } },
    addEventListener() {},
  };
  const document = {
    documentElement: { dataset: { reducedMotion: reducedMotion ? "1" : "0", runtimeProfile: "" }, style: { setProperty() {} } },
    body: { dataset: {} }, hidden, addEventListener() {}, getElementById() { return null; }
  };
  const matchMedia = (query) => ({ matches:
    query === "(pointer: coarse)" ? coarsePointer :
    query === "(max-width: 767px)" ? narrowViewport :
    query === "(prefers-reduced-motion: reduce)" ? prefersReducedMotion : false
  });
  runInNewContext(faceStateSource, {
    window, document, matchMedia, navigator: { hardwareConcurrency: cores }, devicePixelRatio: 2,
    performance: { now: () => 100 },
    CustomEvent: class CustomEvent { constructor(type, options = {}) { this.type = type; this.detail = options.detail; } }
  });
  return window.MASTER_FACE_STATE;
}

test("shared render budget gives coarse-pointer devices the mobile ceiling", () => {
  const coarse = loadFaceStateBudget({ coarsePointer: true, narrowViewport: false, cores: 8 }).renderBudget();
  assert.equal(coarse.points, 420);
  assert.equal(coarse.stipple_points, 315);
  assert.equal(coarse.world_points, 105);
  assert.equal(coarse.stipple_points + coarse.world_points, coarse.points);
  assert.equal(coarse.constrained_device, true);
  const narrow = loadFaceStateBudget({ narrowViewport: true, cores: 8 }).renderBudget();
  assert.equal(narrow.stipple_points, 315);
  assert.equal(narrow.world_points, 105);
  const lowCore = loadFaceStateBudget({ cores: 4 }).renderBudget();
  assert.equal(lowCore.stipple_points + lowCore.world_points, lowCore.points);
  assert.equal(loadFaceStateBudget({ coarsePointer: true, narrowViewport: false, cores: 8 }).renderBudget().particles, 120);
  assert.equal(loadFaceStateBudget({ narrowViewport: true, cores: 8 }).renderBudget().points, 420);
  assert.equal(loadFaceStateBudget({ cores: 4 }).renderBudget().points, 420);
  const desktop = loadFaceStateBudget({}).renderBudget();
  assert.equal(desktop.points, 1200);
  assert.equal(desktop.stipple_points, 900);
  assert.equal(desktop.world_points, 300);
  assert.equal(desktop.stipple_points + desktop.world_points, desktop.points);
  assert.equal(desktop.constrained_device, false);
});

test("shared render budget honors declared reduced motion and hidden-tab ceilings", () => {
  const reducedState = loadFaceStateBudget({ reducedMotion: true });
  assert.equal(reducedState.reducedMotion(), true);
  const reduced = reducedState.renderBudget();
  assert.equal(reduced.particles, 64);
  assert.equal(reduced.fps, 8);
  const liveFaceReduced = loadFaceStateBudget({ faceMotion: true }).renderBudget();
  assert.equal(liveFaceReduced.particles, 64);
  assert.equal(liveFaceReduced.fps, 8);
  const osReducedState = loadFaceStateBudget({ prefersReducedMotion: true });
  assert.equal(osReducedState.reducedMotion(), true);
  const osReduced = osReducedState.renderBudget();
  assert.equal(osReduced.particles, 64);
  assert.equal(osReduced.fps, 8);
  assert.equal(loadFaceStateBudget({ hidden: true }).renderBudget().fps, 0);
});

test("stipple assets are declared after existing face modules", () => {
  assert.match(manifest, /- master_namespace\s+- face_stipple_system\s+- face_playground/);
  assert.match(system, /window\.MASTER_FACE_STIPPLE/);
  assert.match(system, /renderWrapper = function/);
  assert.match(system, /active\.root\.add\(active\.points\)/);
});

test("stipple shares face state and obeys point and motion budgets", () => {
  assert.match(system, /state\.pressureFields\?\.pct/);
  assert.match(system, /state\.pressureFields\?\.entropy/);
  assert.match(system, /state\??\.reducedMotion/);
  assert.match(system, /budget\[mobile \? "mobile_points" : "desktop_points"\]/);
  assert.match(system, /const shared = Number\(sharedBudget\.stipple_points\)/);
  assert.match(system, /max-width: 767px/);
  assert.match(system, /hardwareConcurrency/);
  assert.doesNotMatch(system, /budget\.desktop_particles/);
  assert.match(readFileSync(join(publicDir, "face_world.js"), "utf8"), /effectiveBudget\.world_points/);
  assert.match(faceStateSource, /stipple_points: stipplePoints/);
  assert.match(faceStateSource, /world_points: worldPoints/);
  assert.match(readFileSync(join(publicDir, "face_world.js"), "utf8"), /fallbackShare/);
  assert.match(sparseField, /sharedParticleBudget = Number\(sharedBudget\.particles\)/);
  assert.match(sparseField, /sharedBudget\.constrained_device/);
  assert.match(system, /buildFromSamples/);
  assert.match(system, /uDepthReferenceDistance: \{ value: clamp\(depth\.reference_distance/);
  // FACE_POINT_IS_ONE_PIXEL: depth scales alpha; no point-size controls survive.
  assert.match(system, /gl_PointSize = 1\.0;/);
  assert.match(system, /vAlpha = clamp\([^;]*\* depthScale, 0\.0, 1\.0\)/);
  assert.doesNotMatch(system, /uPointSize(?:Base|Bias|Reference|Distance|Output)/);
  assert.match(system, /vThreshold = aThreshold/);
  assert.match(system, /vThreshold > uDensity/);
});

test("the swarm geometry, force constants, modes and glyph ramp live in face tokens", () => {
  const tokens = readFileSync(join(root, "..", "..", "MASTER", "data", "tokens.yml"), "utf8");
  assert.match(tokens, /^    swarm:\s*$/m);
  assert.match(tokens, /particle_budget:\s*240/);
  assert.match(tokens, /damping:\s*0\.86/);
  assert.match(tokens, /cohesion_radius:\s*0\.11/);
  assert.match(tokens, /cohesion_strength:\s*0\.045/);
  assert.match(tokens, /separation_radius:\s*0\.035/);
  assert.match(tokens, /separation_strength:\s*0\.08/);
  assert.match(tokens, /noise_scale:\s*0\.014/);
  assert.match(tokens, /dial_modulation:\s*\n\s+activity:/);
  assert.match(system, /function dialAdjustments\(state = \{\}\)/);
  assert.match(system, /modulation\.turbulence/);
  assert.match(tokens, /residual:\s*\n\s+fraction:\s*0\.18\s+\n\s+strength:\s*0\.12/);
  assert.match(system, /const force = contract\.stipple_force\?\.\[mode\] \|\| contract\.stipple_force\?\.idle \|\| "none"/);
  assert.match(system, /homePositions\?\.length >= offset \+ 3/);
  assert.match(system, /rand\(i, 97\.3\) < residualFraction/);
  assert.match(tokens, /glyph_ramp:\s*\["·", "˙", "∘", "•", "○", "●"\]/);
  assert.match(tokens, /left:\s*\{ pos: \[-0\.29, 0\.21, 0\.58\], radius: 0\.17, weight: 1\.40 \}/);
  assert.match(tokens, /right:\s*\{ pos: \[0\.29, 0\.21, 0\.58\], radius: 0\.17, weight: 1\.40 \}/);
  assert.match(system, /function swarmConfiguration\(\)/);
  assert.match(system, /Number\(config\.noise_scale\)/);
  assert.match(system, /Number\(config\.cohesion_strength\)/);
  assert.match(system, /Number\(config\.separation_strength\)/);
  assert.match(system, /uDepthFromRank: \{ value: swarmConfiguration\(\)\.size_from_depth === true \? 1\.0 : 0\.0 \}/);
  assert.match(system, /uDepthSteps: \{ value: Math\.max\(2, Array\.isArray\(swarmConfiguration\(\)\.glyph_ramp\)/);
  assert.doesNotMatch(system, /const SWARM_(?:DAMPING|RAMP|TARGET_FIELD)/);
});

test("stipple moods come from the face contract, not a second table", () => {
  const tokens = readFileSync(join(root, "..", "..", "MASTER", "data", "tokens.yml"), "utf8");
  assert.match(system, /MASTER_FACE_CONTRACT\?\.stipple\?\.profiles/);
  assert.doesNotMatch(system, /speaking:\s*\{ density/);
  assert.match(tokens, /depth_response:\s*\n\s+reference_distance: 5\.0/);
  assert.match(tokens, /point_allocation: \{ stipple_fraction: 0\.75, world_fraction: 0\.25 \}/);
  assert.match(tokens, /reference_distance: 5\.0/);
  assert.match(tokens, /scale_min: 0\.75/);
  assert.match(tokens, /scale_max: 1\.25/);
  const modes = tokens.match(/modes: \[([^\]]+)\]/)[1].split(",").map((name) => name.trim());
  for (const mode of modes) assert.match(tokens, new RegExp(`^        ${mode}:\\s+\\{ density:`, "m"));
});

test("playground is opt-in and exposes all canonical semantic states", () => {
  assert.match(playground, /get\("playground"\) !== "1"/);
  assert.match(playground, /MASTER_FACE_CONTRACT\?\.state\?\.modes/);
  assert.match(playground, /MASTER_FACE_STATE/);
  assert.match(playground, /bridge\.setMode\(value, \{ source: "face-playground" \}\)/);
  for (const mode of ["idle", "listening", "thinking", "working", "speaking", "warning", "error", "sleeping", "ready"]) assert.match(playground, new RegExp(mode));
  assert.match(playground, /FacePlayground/);
  assert.match(playground, /stipple_force\?\.\[name\]/);
  assert.match(playground, /Refresh diagnostics/);
  assert.match(playground, /MASTER_FACE_STIPPLE\?\.snapshot/);
  assert.match(css, /\.master-face-stipple-playground/);
  assert.match(css, /\.master-stipple-diagnostics/);
});

test("playground routes all canonical states through FaceState", () => {
  let applied = null;
  const modes = ["idle", "listening", "thinking", "working", "speaking", "warning", "error", "sleeping", "ready"];
  const window = {
    MASTER_FACE_CONTRACT: { state: { modes } },
    MASTER_FACE_STATE: { setMode: (mode, detail) => { applied = { mode, detail }; } },
    addEventListener() {},
    dispatchEvent() {}
  };
  const location = { search: "" };
  runInNewContext(playground, {
    window, location, URLSearchParams,
    CustomEvent: class CustomEvent { constructor(type, options = {}) { this.type = type; this.detail = options.detail; } }
  });
  assert.equal(window.FacePlayground.states.length, 9);
  assert.equal(window.FacePlayground.setState("sleeping"), true);
  assert.equal(applied.mode, "sleeping");
  assert.equal(applied.detail.source, "face-playground");
  assert.equal(window.FacePlayground.setState("not-a-state"), false);
});
test("stipple module boots and builds from the canonical idle profile", () => {
  let coarsePointer = false;
  let narrowViewport = false;
  let hardwareCores = 8;
  let prefersReducedMotion = false;
  let faceState = {};
  const window = {
    location: { search: "" },
    MASTER_FACE_CONTRACT: {
      state: { activity: 0.14, arousal: 0.22, focus: 0.86, confidence: 0.86, risk: 0 },
      spatial: { budget: {
        desktop_points: 1200, mobile_points: 420, desktop_particles: 200, mobile_particles: 120,
        reduced_motion_particles: 64, point_allocation: { stipple_fraction: 0.75, world_fraction: 0.25 }
      } },
      stipple_force: { idle: "residual" },
      swarm: {
        enabled: true, particle_budget: 240, damping: 0.86, cohesion_radius: 0.11, cohesion_strength: 0.045,
        residual: { fraction: 1, strength: 0.12 },
        separation_radius: 0.035, separation_strength: 0.08, noise_scale: 0.014,
        glyph_ramp: ["·", "˙", "∘", "•", "○", "●"],
        target_field: {
          head: { center: [0, 0.05, 0], scale: [1.18, 1.02, 0.82], weight: 1 },
          eyes: {
            left: { pos: [-0.29, 0.21, 0.58], radius: 0.17, weight: 1.4 },
            right: { pos: [0.29, 0.21, 0.58], radius: 0.17, weight: 1.4 }
          },
          mouth: { pos: [0, -0.31, 0.5], radius: 0.34, weight: 1.12 }, softness: 0.72
        },
        mode_multipliers: {
          idle: { eyes: 1, core: 1, noise: 0.14 },
          attentive: { eyes: 1.35, core: 1.05, noise: 0.07 },
          thinking: { eyes: 1.15, core: 1.3, noise: 0.22 }
        }
      },
      stipple: {
        depth_response: { reference_distance: 5.0, scale_min: 0.75, scale_max: 1.25 },
        dial_modulation: {
          activity: { density: 0.05, ripple: 0.08, turbulence: 0.12, luminosity: 0.03, attract: 0.04 },
          arousal: { ripple: 0.10, turbulence: 0.06, luminosity: 0.04 },
          focus: { density: 0.02, attract: 0.12 },
          confidence: { density: 0.02, luminosity: 0.04 },
          risk: { ripple: 0.08, turbulence: 0.16, attract: -0.08 }
        },
        profiles: {
          idle: { density: 0.44, ripple: 0.03, turbulence: 0.04, luminosity: 0.76, attract: 0.14 },
          thinking: { density: 0.72, ripple: 0.16, turbulence: 0.28, luminosity: 0.91, attract: 0.74 }
        }
      }
    },
    navigator: { get hardwareConcurrency() { return hardwareCores; } },
    MASTER_FACE_STATE: {
      snapshot: () => faceState,
      renderBudget: () => {
        const points = (coarsePointer || narrowViewport || hardwareCores <= 4) ? 420 : 1200;
        const stipple_points = Math.floor(points * 0.75);
        return { points, stipple_points, world_points: points - stipple_points };
      }
    },
    matchMedia: (query) => ({
      matches: (query === "(pointer: coarse)" && coarsePointer) ||
        (query === "(max-width: 767px)" && narrowViewport) ||
        (query === "(prefers-reduced-motion: reduce)" && prefersReducedMotion)
    }),
    addEventListener() {},
    dispatchEvent() {}
  };
  const document = {
    body: { classList: { contains: () => false } },
    documentElement: { dataset: {} },
    hidden: false,
    addEventListener() {},
    removeEventListener() {}
  };
  runInNewContext(system, {
    window,
    document,
    URLSearchParams,
    Math,
    Number,
    Object,
    Array,
    String,
    CustomEvent: class CustomEvent { constructor(type, options = {}) { this.type = type; this.detail = options.detail; } },
    matchMedia: window.matchMedia,
    getComputedStyle: () => ({ getPropertyValue: () => "" }),
    performance: { now: () => 0 }
  });

  assert.equal(typeof window.MASTER_FACE_STIPPLE?.buildFromSamples, "function");
  assert.equal(typeof window.MASTER_FACE_STIPPLE?.snapshot, "function");
  assert.equal(typeof window.MASTER_FACE_STIPPLE?.uninstall, "function");
  assert.equal(window.MASTER_FACE_STIPPLE.profiles.idle.density, 0.44);
  assert.equal(window.MASTER_FACE_STIPPLE.snapshot().pointCeiling, 240);
  assert.equal(window.MASTER_FACE_STIPPLE.snapshot().context, "ready");
  const initialDiagnostics = window.MASTER_FACE_STIPPLE.snapshot();
  assert.equal(initialDiagnostics.semantic.force, "residual");
  assert.equal(initialDiagnostics.semantic.residual.active, true);
  assert.equal(initialDiagnostics.semantic.residual.carrierCount, 0);
  assert.equal(initialDiagnostics.semantic.residual.selectedCarriers, 0);
  assert.equal(initialDiagnostics.semantic.dialInputs.activity, null);
  assert.equal(initialDiagnostics.semantic.dialAdjustments.density, 0);
  faceState = { mode: "idle", activity: null, arousal: "", focus: null, confidence: null, risk: null };
  const absentDialDiagnostics = window.MASTER_FACE_STIPPLE.snapshot().semantic;
  assert.equal(absentDialDiagnostics.dialInputs.activity, null);
  assert.equal(absentDialDiagnostics.dialInputs.arousal, null);
  assert.equal(absentDialDiagnostics.dialAdjustments.density, 0);
  assert.equal(absentDialDiagnostics.dialAdjustments.ripple, 0);
  faceState = { mode: "idle", activity: 1, arousal: 1, focus: 1, confidence: 1, risk: 1 };
  const dialDiagnostics = window.MASTER_FACE_STIPPLE.snapshot().semantic;
  assert.equal(dialDiagnostics.dialInputs.activity, 1);
  assert.ok(Math.abs(dialDiagnostics.dialAdjustments.density - 0.0486) < 0.000001);
  assert.ok(Math.abs(dialDiagnostics.dialAdjustments.turbulence - 0.31) < 0.000001);
  faceState = {};

  class BufferAttribute {
    constructor(array, itemSize) { this.array = array; this.itemSize = itemSize; }
  }
  class BufferGeometry {
    constructor() { this.attributes = {}; }
    setAttribute(name, attribute) { this.attributes[name] = attribute; }
  }
  class Color {
    constructor(...rgb) { this.rgb = rgb.length ? rgb : null; this.hex = null; }
    setRGB(...rgb) { this.rgb = rgb; this.hex = null; return this; }
    set(color) { this.hex = color; return this; }
  }
  class ShaderMaterial {
    constructor(options) { Object.assign(this, options); }
  }
  class Points {
    constructor(geometry, material) { this.geometry = geometry; this.material = material; this.type = "Points"; }
  }

  const THREE = { BufferAttribute, BufferGeometry, Color, ShaderMaterial, Points };
  const api = window.MASTER_FACE_STIPPLE;
  assert.equal(api.isFaceScene({ children: [{ type: "Group", children: [{ type: "Points" }] }] }), true);
  assert.equal(api.isFaceScene({ children: [{ type: "Object3D", children: [{ type: "Points" }] }] }), true);
  assert.equal(api.isFaceScene({ children: [{ type: "Group", children: [] }] }), false);
  const stipple = api.buildFromSamples(THREE, [{ x: 0, y: 0, z: 0, zone: 0, bias: 1 }]);
  assert.equal(stipple.count, 1);
  assert.equal(stipple.material.uniforms.uDepthFromRank.value, 1);
  assert.equal(stipple.material.uniforms.uDepthSteps.value, 6);
  assert.equal(stipple.material.uniforms.uDensity.value, 0.44);
  window.MASTER_FACE_CONTRACT.swarm.size_from_depth = false;
  const flatDepth = api.buildFromSamples(THREE, [{ x: 0, y: 0, z: 0, zone: 0, bias: 1 }]);
  assert.equal(flatDepth.material.uniforms.uDepthFromRank.value, 0);
  window.MASTER_FACE_CONTRACT.swarm.size_from_depth = true;
  assert.equal(stipple.material.uniforms.uRipple.value, 0.03);
  assert.equal(stipple.material.uniforms.uTurbulence.value, 0.04);
  assert.equal(stipple.material.uniforms.uLuminosity.value, 0.76);
  assert.equal(stipple.material.uniforms.uAttract.value, 0.14);
  assert.equal(stipple.material.uniforms.uDepthReferenceDistance.value, 5.0);
  assert.equal(stipple.material.uniforms.uDepthScaleMin.value, 0.75);
  assert.equal(stipple.material.uniforms.uDepthScaleMax.value, 1.25);
  assert.equal("uPointSizeBase" in stipple.material.uniforms, false);
  assert.equal("uPointSizeOutputMax" in stipple.material.uniforms, false);

  // Shared token ramp and semantic modes are visible to the runtime, not redefined here.
  assert.equal(api.glyphForDepth(0), "·");
  assert.equal(api.glyphForDepth(1), "●");
  assert.equal(api.canonicalSwarmMode({ mode: "listening" }), "attentive");
  assert.equal(api.modeMultipliersFor({ mode: "thinking" }).noise, 0.22);
  assert.match(system, /gl_PointSize = 1\.0;/);

  const moving = api.buildFromSamples(THREE, [
    { x: 0.8, y: 0, z: 0, zone: 0, bias: 1 },
    { x: 0.7, y: 0.03, z: 0.1, zone: 0, bias: 1 }
  ]);
  const residualSystem = api.buildFromSamples(THREE, [
    { x: 0.8, y: 0, z: 0, zone: 0, bias: 1 },
    { x: 0.7, y: 0.03, z: 0.1, zone: 0, bias: 1 }
  ]);
  window.MASTER_FACE_CONTRACT.stipple_force.idle = "none";
  const collectiveSystem = api.buildFromSamples(THREE, [
    { x: 0.8, y: 0, z: 0, zone: 0, bias: 1 },
    { x: 0.7, y: 0.03, z: 0.1, zone: 0, bias: 1 }
  ]);
  window.MASTER_FACE_CONTRACT.stipple_force.idle = "residual";
  api.updateSwarm(residualSystem, { mode: "idle", reducedMotion: false }, 0.05, 1);
  window.MASTER_FACE_CONTRACT.stipple_force.idle = "none";
  api.updateSwarm(collectiveSystem, { mode: "idle", reducedMotion: false }, 0.05, 1);
  assert.notDeepEqual(
    Array.from(residualSystem.geometry.attributes.position.array),
    Array.from(collectiveSystem.geometry.attributes.position.array),
    "residual carriers retain a deterministic pull toward their original positions"
  );
  window.MASTER_FACE_CONTRACT.stipple_force.idle = "residual";
  const beforeMove = Array.from(moving.geometry.attributes.position.array);
  assert.equal(api.updateSwarm(moving, { mode: "idle", reducedMotion: false }, 0.05, 1), true);
  assert.notDeepEqual(Array.from(moving.geometry.attributes.position.array), beforeMove);
  assert.equal(moving.geometry.attributes.aDepthRank.needsUpdate, true);
  const frozen = Array.from(moving.geometry.attributes.position.array);
  assert.equal(api.updateSwarm(moving, { mode: "idle", reducedMotion: true }, 0.05, 2), false);
  assert.deepEqual(Array.from(moving.geometry.attributes.position.array), frozen);

  // An absent pressure event must preserve the mode's canonical density.
  api.tick(stipple, { mode: "idle", reducedMotion: false }, 0);
  assert.equal(stipple.material.uniforms.uDensity.value, 0.44);
  assert.deepEqual(stipple.material.uniforms.uColor.value.rgb, [1, 1, 1]);

  // Continuous state dials make bounded changes without replacing the named mode profile.
  api.tick(stipple, {
    mode: "idle", activity: 1, arousal: 1, focus: 1, confidence: 1, risk: 1,
    reducedMotion: false
  }, 0.5);
  assert.ok(stipple.material.uniforms.uDensity.value > 0.44);
  assert.ok(stipple.material.uniforms.uRipple.value > 0.03);
  assert.ok(stipple.material.uniforms.uTurbulence.value > 0.0724);
  assert.ok(stipple.material.uniforms.uLuminosity.value > 0.76);
  assert.ok(stipple.material.uniforms.uAttract.value < 0.14);
  api.tick(stipple, {
    mode: "idle", activity: 0.14, arousal: 0.22, focus: 0.86, confidence: 0.86, risk: 0,
    reducedMotion: false
  }, 0.75);
  assert.equal(stipple.material.uniforms.uDensity.value, 0.44);
  assert.equal(stipple.material.uniforms.uRipple.value, 0.03);
  assert.equal(api.applyPalette(stipple, { accent: "#C8F55F" }), false);
  assert.deepEqual(stipple.material.uniforms.uColor.value.rgb, [1, 1, 1]);

  // State changes reuse the one contract; pressure can modulate density without
  // replacing the named profile, and reduced motion removes animation only.
  api.tick(stipple, {
    mode: "thinking",
    pressureFields: { pct: 50, entropy: 0.28 },
    reducedMotion: false
  }, 1);
  assert.equal(stipple.material.uniforms.uDensity.value, 0.72);
  assert.equal(stipple.material.uniforms.uRipple.value, 0.16);
  assert.ok(Math.abs(stipple.material.uniforms.uTurbulence.value - 0.3304) < 0.00001);
  assert.equal(stipple.material.uniforms.uLuminosity.value, 0.91);
  assert.equal(stipple.material.uniforms.uAttract.value, 0.74);
  assert.equal(stipple.material.uniforms.uTime.value, 1);

  api.tick(stipple, {
    mode: "thinking",
    pressureFields: { pct: 50, entropy: 0.28 },
    reducedMotion: true
  }, 2);
  assert.equal(stipple.material.uniforms.uTime.value, 0);
  assert.equal(stipple.material.uniforms.uRipple.value, 0);
  assert.equal(stipple.material.uniforms.uTurbulence.value, 0);
  assert.equal(stipple.material.uniforms.uMotionScale.value, 0);

  // OS and document-level preferences work even when the face-state bit is stale.
  prefersReducedMotion = true;
  api.tick(stipple, { mode: "idle", reducedMotion: false }, 3);
  assert.equal(stipple.material.uniforms.uTime.value, 0);
  assert.equal(stipple.material.uniforms.uMotionScale.value, 0);
  assert.equal(api.snapshot().reducedMotion, true);
  prefersReducedMotion = false;
  document.documentElement.dataset.reducedMotion = "1";
  api.tick(stipple, { mode: "idle", reducedMotion: false }, 4);
  assert.equal(stipple.material.uniforms.uTime.value, 0);
  assert.equal(api.snapshot().reducedMotion, true);
  document.documentElement.dataset.reducedMotion = "0";
  window.MASTER_FACE = { State: { reducedMotion: true } };
  api.tick(stipple, { mode: "thinking", reducedMotion: false }, 5);
  assert.equal(stipple.material.uniforms.uTime.value, 0);
  assert.equal(stipple.material.uniforms.uRipple.value, 0);
  assert.equal(stipple.material.uniforms.uTurbulence.value, 0);
  assert.equal(api.snapshot().reducedMotion, true);
  window.MASTER_FACE.State.reducedMotion = false;

  // The layer never exceeds the canonical desktop/mobile point ceiling.
  assert.equal(api.createDefault(THREE, 5000).count, 240);
  coarsePointer = true;
  assert.equal(api.createDefault(THREE, 5000).count, 240);
  coarsePointer = false;
  narrowViewport = true;
  assert.equal(api.createDefault(THREE, 5000).count, 240);
  narrowViewport = false;
  hardwareCores = 4;
  assert.equal(api.createDefault(THREE, 5000).count, 240);
  faceState = { mode: "idle", reducedMotion: true };
  assert.equal(api.createDefault(THREE, 5000).count, 240);
  faceState = {};
});

test("stipple lifecycle is observable and reversible", () => {
  assert.match(system, /webglcontextlost/);
  assert.match(system, /webglcontextrestored/);
  assert.match(system, /event\?\.preventDefault\?\.\(\)/);
  assert.match(system, /if \(!enabled \|\| wrappedRenderer \|\| installing\) return/);
  assert.match(system, /finally \{\s+installing = false;/);
  assert.match(system, /visibilitychange/);
  assert.match(system, /function uninstall\(\)/);
  assert.match(system, /active\?\.geometry\?\.dispose\?\./);
  assert.match(system, /active\?\.material\?\.dispose\?\./);
  assert.match(system, /lastRenderIntervalMs/);
  assert.match(system, /FRAME_SAMPLE_LIMIT = 60/);
  assert.match(system, /renderTiming: \{/);
  assert.match(system, /MASTER_FACE_STATE\?\.reducedMotion/);
  assert.match(system, /window\.MASTER_FACE\?\.State\?\.reducedMotion/);
  assert.match(system, /p50RenderIntervalMs: percentile\(0\.50\)/);
  assert.match(system, /p95RenderIntervalMs: percentile\(0\.95\)/);
  assert.match(system, /approximateRenderCallsPerSecond/);
  assert.match(system, /depthResponse\(\)/);
  assert.match(system, /pointCeiling: pointBudget\(\)/);
  assert.match(system, /currentFaceState\(\)/);
  assert.match(system, /installing,/);
});

