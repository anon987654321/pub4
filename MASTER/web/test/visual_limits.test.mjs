// The particle budget is a number, and two modules were asking it a yes/no
// question. `limits.reducedMotionParticles < 100` compares the constant 64, so
// it was true for every visitor and isReduced never depended on the preference.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext, runInNewContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const governorSource = readFileSync(join(publicDir, "visual_governor.js"), "utf8");

function loadGovernor({ reducedMotion = false, profile = "auto" } = {}) {
  const sandbox = {
    window: {
      matchMedia: (q) => ({ matches: q.includes("reduced-motion") ? reducedMotion : false }),
      requestAnimationFrame: () => 1,
      cancelAnimationFrame: () => {},
    },
    document: {
      hidden: false,
      body: { dataset: {} },
      documentElement: { dataset: profile === "auto" ? {} : { runtimeProfile: profile } },
      addEventListener: () => {},
      querySelector: () => null,
    },
    Array,
  };
  sandbox.window.window = sandbox.window;
  sandbox.window.document = sandbox.document;
  runInContext(governorSource, createContext(sandbox));
  return sandbox.window.MASTER_VISUAL_LIMITS;
}

test("the governor publishes its limits", () => {
  const limits = loadGovernor();

  assert.equal(limits.maxFps, 24);
  assert.equal(limits.maxParticles, 200);
  assert.equal(limits.reducedMotionParticles, 64);
});

// data/ops/visual.yml said freeze_on_fail: true while this said false, and the
// false is the fix — a backend fail must not black out the face.
test("a backend failure does not freeze the visuals", () => {
  assert.equal(loadGovernor().freezeOnFail, false);
});

// Removed by 930a35ca5, a revert aimed at tap-to-start, and never restored.
test("reduced motion caps the frame rate and the particle count", () => {
  const limits = loadGovernor({ reducedMotion: true });

  assert.equal(limits.maxFps, 8);
  assert.equal(limits.maxParticles, limits.reducedMotionParticles);
});

test("the battery profile caps the frame rate without reduced motion", () => {
  assert.equal(loadGovernor({ profile: "battery" }).maxFps, 12);
  assert.equal(loadGovernor({ profile: "battery" }).maxParticles, 200);
});

// runtimeProfile is written to documentElement by face_brutalist.js and
// face_vision_d.js. The pre-revert governor read body.dataset, so it never saw
// a profile at all.
test("the profile is read from documentElement, where it is actually written", () => {
  assert.match(governorSource, /documentElement\?\.dataset\?\.runtimeProfile/);
});

// The defect itself: evaluate each consumer's own isReduced expression against
// the real published limits, with the preference off.
for (const file of ["mask.js", "cognition_ecology.js"]) {
  test(`${file} decides reduced motion from the preference, not the budget`, () => {
    const source = readFileSync(join(publicDir, file), "utf8");
    const match = source.match(/const isReduced = ([^;]+);/);
    assert.ok(match, `no isReduced assignment in ${file}`);

    const limits = loadGovernor();
    const off = runInNewContext(match[1], {
      limits, reducedMotion: false, prefersReducedMotion: false,
    });
    const on = runInNewContext(match[1], {
      limits, reducedMotion: true, prefersReducedMotion: true,
    });

    assert.equal(off, false, "isReduced was true with the preference off");
    assert.equal(on, true, "isReduced must still follow the preference when set");
  });

  test(`${file} does not compare a particle budget as a mode flag`, () => {
    const source = readFileSync(join(publicDir, file), "utf8");
    const code = source.replace(/^\s*\/\/.*$/gm, "");

    assert.doesNotMatch(code, /reducedMotionParticles\s*<\s*\d+/);
  });
}
