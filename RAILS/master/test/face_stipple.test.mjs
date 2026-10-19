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

test("stipple assets are declared after existing face modules", () => {
  assert.match(manifest, /- master_namespace\s+- face_stipple_system\s+- face_playground/);
  assert.match(system, /window\.MASTER_FACE_STIPPLE/);
  assert.match(system, /renderer\.render = function/);
  assert.match(system, /active\.root\.add\(active\.points\)/);
});

test("stipple shares face state and obeys point and motion budgets", () => {
  assert.match(system, /state\.pressureFields\?\.pct/);
  assert.match(system, /state\.pressureFields\?\.entropy/);
  assert.match(system, /state\.reducedMotion/);
  assert.match(system, /budget\.mobile_points/);
  assert.match(system, /budget\.desktop_points/);
  assert.doesNotMatch(system, /budget\.desktop_particles/);
  assert.match(system, /buildFromSamples/);
  assert.match(system, /gl_PointSize = 1\.0/);
  assert.match(system, /vThreshold = aThreshold/);
  assert.match(system, /vThreshold > uDensity/);
});

test("stipple moods come from the face contract, not a second table", () => {
  const tokens = readFileSync(join(root, "..", "..", "MASTER", "data", "tokens.yml"), "utf8");
  assert.match(system, /MASTER_FACE_CONTRACT\?\.stipple\?\.profiles/);
  assert.doesNotMatch(system, /speaking:\s*\{ density/);
  const modes = tokens.match(/modes: \[([^\]]+)\]/)[1].split(",").map((name) => name.trim());
  for (const mode of modes) assert.match(tokens, new RegExp(`^        ${mode}:\\s+\\{ density:`, "m"));
});

test("playground is opt-in and supplies seven semantic states", () => {
  assert.match(playground, /get\("playground"\) !== "1"/);
  for (const mode of ["idle", "thinking", "listening", "working", "speaking", "warning", "error"]) assert.match(playground, new RegExp(mode));
  assert.match(playground, /FacePlayground/);
  assert.match(css, /\.master-face-stipple-playground/);
});

test("stipple module boots and builds from the canonical idle profile", () => {
  const window = {
    location: { search: "" },
    MASTER_FACE_CONTRACT: {
      stipple: {
        profiles: {
          idle: { density: 0.44, ripple: 0.03, turbulence: 0.04, luminosity: 0.76, attract: 0.14 },
          thinking: { density: 0.72, ripple: 0.16, turbulence: 0.28, luminosity: 0.91, attract: 0.74 }
        }
      }
    },
    addEventListener() {}
  };
  const document = { body: { classList: { contains: () => false } } };
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
    matchMedia: () => ({ matches: false }),
    performance: { now: () => 0 }
  });

  assert.equal(typeof window.MASTER_FACE_STIPPLE?.buildFromSamples, "function");
  assert.equal(window.MASTER_FACE_STIPPLE.profiles.idle.density, 0.44);

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

  const stipple = window.MASTER_FACE_STIPPLE.buildFromSamples({
    BufferAttribute, BufferGeometry, Color, ShaderMaterial, Points
  }, [{ x: 0, y: 0, z: 0, zone: 0, bias: 1 }]);
  assert.equal(stipple.count, 1);
  assert.equal(stipple.material.uniforms.uDensity.value, 0.44);
  assert.equal(stipple.material.uniforms.uRipple.value, 0.03);
  assert.equal(stipple.material.uniforms.uTurbulence.value, 0.04);
  assert.equal(stipple.material.uniforms.uLuminosity.value, 0.76);
  assert.equal(stipple.material.uniforms.uAttract.value, 0.14);
});
