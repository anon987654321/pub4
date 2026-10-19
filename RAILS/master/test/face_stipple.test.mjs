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
const sparseField = readFileSync(join(publicDir, "face_sparse_field.js"), "utf8");

test("shared face budgets classify coarse pointers and declared reduced motion", () => {
  assert.match(faceStateSource, /mediaMatches\("\(pointer: coarse\)"\)/);
  assert.match(faceStateSource, /dataset\?\.reducedMotion === "1"/);
  assert.match(sparseField, /function reducedMotionEnabled\(state = \{\}\)/);
  assert.match(sparseField, /window\.matchMedia\?\.\("\(pointer: coarse\)"\)/);
  assert.match(sparseField, /const reduced = reducedMotionEnabled\(state\)/);
});

test("stipple discovery accepts Group containers with point children", () => {
  assert.match(system, /function hasFacePoints\(node\)/);
  assert.match(system, /scene\.children\.some\(hasFacePoints\)/);
  assert.match(system, /scene\.children\.find\(hasFacePoints\)/);
});

function loadFaceStateBudget({ coarsePointer = false, narrowViewport = false, cores = 8, reducedMotion = false, hidden = false } = {}) {
  const window = {
    MASTER_FACE_CONTRACT: {
      state: {
        modes: ["idle", "listening", "thinking", "working", "speaking", "warning", "error", "sleeping", "ready"],
        default_mode: "idle", default_topology: "face", entropy: 0.18, confidence: 0.86,
        attention: 1, arousal: 0.22, valence: 0.18, focus: 0.86, activity: 0.14, risk: 0
      },
      spatial: { budget: {
        desktop_points: 1200, mobile_points: 420, desktop_particles: 200, mobile_particles: 120,
        reduced_motion_particles: 64, max_device_pixel_ratio: 2, active_fps: 24, idle_fps: 12,
        hidden_fps: 0, reduced_motion_fps: 8, battery_fps: 12, pulse_limit: 24, hud_labels: 5
      } }
    },
    addEventListener() {},
  };
  const document = {
    documentElement: { dataset: { reducedMotion: reducedMotion ? "1" : "0", runtimeProfile: "" }, style: { setProperty() {} } },
    body: { dataset: {} }, hidden, addEventListener() {}, getElementById() { return null; }
  };
  const matchMedia = (query) => ({ matches:
    query === "(pointer: coarse)" ? coarsePointer :
    query === "(max-width: 767px)" ? narrowViewport : false
  });
  runInNewContext(faceStateSource, {
    window, document, matchMedia, navigator: { hardwareConcurrency: cores }, devicePixelRatio: 2,
    performance: { now: () => 100 },
    CustomEvent: class CustomEvent { constructor(type, options = {}) { this.type = type; this.detail = options.detail; } }
  });
  return window.MASTER_FACE_STATE;
}

test("shared render budget gives coarse-pointer devices the mobile ceiling", () => {
  assert.equal(loadFaceStateBudget({ coarsePointer: true, narrowViewport: false, cores: 8 }).renderBudget().points, 420);
  assert.equal(loadFaceStateBudget({ coarsePointer: true, narrowViewport: false, cores: 8 }).renderBudget().particles, 120);
  assert.equal(loadFaceStateBudget({ narrowViewport: true, cores: 8 }).renderBudget().points, 420);
  assert.equal(loadFaceStateBudget({ cores: 4 }).renderBudget().points, 420);
  assert.equal(loadFaceStateBudget({}).renderBudget().points, 1200);
});

test("shared render budget honors declared reduced motion and hidden-tab ceilings", () => {
  const reduced = loadFaceStateBudget({ reducedMotion: true }).renderBudget();
  assert.equal(reduced.particles, 64);
  assert.equal(reduced.fps, 8);
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
  assert.match(system, /MASTER_FACE_STATE\?\.renderBudget\?\.\(\)\.points/);
  assert.match(system, /max-width: 767px/);
  assert.match(system, /hardwareConcurrency/);
  assert.doesNotMatch(system, /budget\.desktop_particles/);
  assert.match(readFileSync(join(publicDir, "face_world.js"), "utf8"), /effectiveBudget\?\.points/);
  assert.match(system, /buildFromSamples/);
  assert.match(system, /uPointSizeReferenceDepth: \{ value: clamp\(pointSize\.reference_depth/);
  assert.match(system, /gl_PointSize = clamp\(biasedSize \* distanceScale,\s+uPointSizeOutputMin, uPointSizeOutputMax\)/);
  assert.match(system, /vThreshold = aThreshold/);
  assert.match(system, /vThreshold > uDensity/);
});

test("stipple moods come from the face contract, not a second table", () => {
  const tokens = readFileSync(join(root, "..", "..", "MASTER", "data", "tokens.yml"), "utf8");
  assert.match(system, /MASTER_FACE_CONTRACT\?\.stipple\?\.profiles/);
  assert.doesNotMatch(system, /speaking:\s*\{ density/);
  assert.match(tokens, /point_size:\s*\n\s+base: 0\.90/);
  assert.match(tokens, /reference_depth: 5\.0/);
  assert.match(tokens, /output_min: 1\.0/);
  assert.match(tokens, /output_max: 1\.5/);
  const modes = tokens.match(/modes: \[([^\]]+)\]/)[1].split(",").map((name) => name.trim());
  for (const mode of modes) assert.match(tokens, new RegExp(`^        ${mode}:\\s+\\{ density:`, "m"));
});

test("playground is opt-in and supplies seven semantic states", () => {
  assert.match(playground, /get\("playground"\) !== "1"/);
  for (const mode of ["idle", "thinking", "listening", "working", "speaking", "warning", "error"]) assert.match(playground, new RegExp(mode));
  assert.match(playground, /FacePlayground/);
  assert.match(playground, /Refresh diagnostics/);
  assert.match(playground, /MASTER_FACE_STIPPLE\?\.snapshot/);
  assert.match(css, /\.master-face-stipple-playground/);
  assert.match(css, /\.master-stipple-diagnostics/);
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
      spatial: { budget: { desktop_points: 1200, mobile_points: 420 } },
      stipple: {
        point_size: {
          base: 0.90, bias_scale: 0.35, bias_min: 0.25, bias_max: 1.50,
          reference_depth: 5.0, distance_min: 0.75, distance_max: 1.25,
          output_min: 1.0, output_max: 1.5
        },
        profiles: {
          idle: { density: 0.44, ripple: 0.03, turbulence: 0.04, luminosity: 0.76, attract: 0.14 },
          thinking: { density: 0.72, ripple: 0.16, turbulence: 0.28, luminosity: 0.91, attract: 0.74 }
        }
      }
    },
    navigator: { hardwareConcurrency: hardwareCores },
    MASTER_FACE_STATE: {
      snapshot: () => faceState,
      renderBudget: () => ({ points: (coarsePointer || narrowViewport || hardwareCores <= 4) ? 420 : 1200 })
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
  assert.equal(window.MASTER_FACE_STIPPLE.snapshot().pointCeiling, 1200);
  assert.equal(window.MASTER_FACE_STIPPLE.snapshot().context, "ready");

  class BufferAttribute {
    constructor(array, itemSize) { this.array = array; this.itemSize = itemSize; }
  }
  class BufferGeometry {
    constructor() { this.attributes = {}; }
    setAttribute(name, attribute) { this.attributes[name] = attribute; }
  }
  class Color {
    setRGB() { return this; }
    set() { return this; }
  }
  class ShaderMaterial {
    constructor(options) { Object.assign(this, options); }
  }
  class Points {
    constructor(geometry, material) { this.geometry = geometry; this.material = material; this.type = "Points"; }
  }

  const THREE = { BufferAttribute, BufferGeometry, Color, ShaderMaterial, Points };
  const api = window.MASTER_FACE_STIPPLE;
  const stipple = api.buildFromSamples(THREE, [{ x: 0, y: 0, z: 0, zone: 0, bias: 1 }]);
  assert.equal(stipple.count, 1);
  assert.equal(stipple.material.uniforms.uDensity.value, 0.44);
  assert.equal(stipple.material.uniforms.uRipple.value, 0.03);
  assert.equal(stipple.material.uniforms.uTurbulence.value, 0.04);
  assert.equal(stipple.material.uniforms.uLuminosity.value, 0.76);
  assert.equal(stipple.material.uniforms.uAttract.value, 0.14);
  assert.equal(stipple.material.uniforms.uPointSizeBase.value, 0.90);
  assert.equal(stipple.material.uniforms.uPointSizeBiasScale.value, 0.35);
  assert.equal(stipple.material.uniforms.uPointSizeReferenceDepth.value, 5.0);
  assert.equal(stipple.material.uniforms.uPointSizeDistanceMin.value, 0.75);
  assert.equal(stipple.material.uniforms.uPointSizeDistanceMax.value, 1.25);
  assert.equal(stipple.material.uniforms.uPointSizeOutputMin.value, 1.0);
  assert.equal(stipple.material.uniforms.uPointSizeOutputMax.value, 1.5);

  // An absent pressure event must preserve the mode's canonical density.
  api.tick(stipple, { mode: "idle", reducedMotion: false }, 0);
  assert.equal(stipple.material.uniforms.uDensity.value, 0.44);

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

  // The layer never exceeds the canonical desktop/mobile point ceiling.
  assert.equal(api.createDefault(THREE, 5000).count, 1200);
  coarsePointer = true;
  assert.equal(api.createDefault(THREE, 5000).count, 420);
  coarsePointer = false;
  narrowViewport = true;
  assert.equal(api.createDefault(THREE, 5000).count, 420);
  narrowViewport = false;
  hardwareCores = 4;
  assert.equal(api.createDefault(THREE, 5000).count, 420);
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
  assert.match(system, /pointSizing\(\)/);
  assert.match(system, /pointCeiling: pointBudget\(\)/);
  assert.match(system, /currentFaceState\(\)/);
  assert.match(system, /installing,/);
});

