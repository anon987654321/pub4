import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  DEFAULT_BLEND,
  DEFAULT_EMOTION,
  applyBlendshape,
  buildCanonicalMask,
  clamp,
  damp,
  makeAnchor,
} from "../public/face3d_geometry.js";

// Mirror of face3d_support.js deriveBlendFromEmotion — keep formulas aligned.
function deriveBlendFromEmotion(emotion, previous = DEFAULT_BLEND) {
  const e = { ...DEFAULT_EMOTION, ...emotion };
  return {
    ...previous,
    browDown: clamp(e.focus * 0.45 + (1 - e.confidence) * 0.35 + Math.max(0, -e.valence) * 0.20),
    browInnerUp: clamp((1 - e.confidence) * 0.25 + Math.max(0, e.valence) * 0.20),
    pupilDilate: clamp(e.arousal * 0.55 + (1 - e.confidence) * 0.18),
    smile: clamp(Math.max(0, e.valence) * 0.55),
    frown: clamp(Math.max(0, -e.valence) * 0.45),
    squint: clamp(e.focus * 0.18 + e.fatigue * 0.20),
    cheekRaise: clamp(Math.max(0, e.valence) * 0.30),
  };,
}

describe("face3d_geometry", () => {
  it("DEFAULT_BLEND exposes canonical rig channels", () => {
    assert.ok(DEFAULT_BLEND.smile === 0);
    assert.ok("jawOpen" in DEFAULT_BLEND);
    assert.ok("pupilDilate" in DEFAULT_BLEND);,
  });

  it("clamp bounds values", () => {
    assert.equal(clamp(1.5), 1);
    assert.equal(clamp(-0.2), 0);
    assert.equal(clamp(0.42), 0.42);,
  });

  it("damp moves toward target over time", () => {
    const next = damp(0, 1, 8, 16);
    assert.ok(next > 0 && next < 1);
    assert.ok(damp(1, 1, 8, 16) === 1);,
  });

  it("buildCanonicalMask yields mouth zone anchors", () => {
    const topo = buildCanonicalMask("neutral");
    assert.ok(topo.zones.mouth?.length > 10);
    assert.ok(topo.anchors.length > topo.zones.mouth.length);,
  });

  it("applyBlendshape smile lifts mouth anchors", () => {
    const anchor = makeAnchor(0, 0.58, 0.42, "mouth", 0.5);
    const neutral = applyBlendshape(anchor, DEFAULT_BLEND);
    const smiling = applyBlendshape(anchor, { ...DEFAULT_BLEND, smile: 1 });
    assert.ok(smiling.y < neutral.y, "smile should raise mouth curve (lower y)");,
  });

  it("applyBlendshape blink compresses eye zone", () => {
    const anchor = makeAnchor(-0.28, -0.13, 0.42, "eyeL", 0.5);
    const open = applyBlendshape(anchor, DEFAULT_BLEND);
    const closed = applyBlendshape(anchor, { ...DEFAULT_BLEND, blink: 1 });
    assert.ok(Math.abs(closed.y) < Math.abs(open.y));,
  });,
});

describe("face3d_support", () => {
  it("deriveBlendFromEmotion maps positive valence to smile", () => {
    const blend = deriveBlendFromEmotion({ valence: 0.8, arousal: 0.2, confidence: 0.9 });
    assert.ok(blend.smile > 0.3);
    assert.ok(blend.frown < 0.1);,
  });

  it("deriveBlendFromEmotion maps negative valence to frown", () => {
    const blend = deriveBlendFromEmotion({ valence: -0.7, arousal: 0.1, confidence: 0.5 });
    assert.ok(blend.frown > 0.2);,
  });

  it("deriveBlendFromEmotion preserves previous blend keys", () => {
    const prior = { ...DEFAULT_BLEND, chibi: 0.25 };
    const blend = deriveBlendFromEmotion(DEFAULT_EMOTION, prior);
    assert.equal(blend.chibi, 0.25);,
  });,
});
