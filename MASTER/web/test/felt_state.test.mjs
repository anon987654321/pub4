// felt_state.js is the presence store the server splits into felt_sense, so the
// string has to be the same wherever it is read and a published value has to
// beat the DOM reflection of an older one.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const source = readFileSync(join(publicDir, "felt_state.js"), "utf8");

function loadFeltState({ cssVars = {}, dataset = {}, faceState = null, history = null } = {}) {
  const listeners = {};
  const sandbox = {
    window: {
      addEventListener(type, fn) { (listeners[type] ||= []).push(fn); },
      MASTER_FACE: faceState ? { State: faceState } : undefined,
      MASTER_FACE_BLEND: undefined,
      MASTER_LOG: null,
    },
    document: {
      body: { dataset },
      documentElement: { style: { getPropertyValue: (name) => cssVars[name] ?? "" } },
    },
    localStorage: {
      getItem: (key) => (key === "master:emotion_history" && history ? JSON.stringify(history) : null),
    },
  };
  sandbox.window.window = sandbox.window;
  sandbox.window.document = sandbox.document;
  sandbox.window.localStorage = sandbox.localStorage;

  runInContext(source, createContext(sandbox));
  const emit = (type, detail) => (listeners[type] || []).forEach((fn) => fn({ detail }));
  return { felt: sandbox.window.MASTERFeltState, emit, window: sandbox.window };
}

test("felt state is seven pipe-separated fields and validates itself", () => {
  const { felt } = loadFeltState();
  const state = felt.collectFeltState();

  assert.equal(state.split("|").length, felt.FIELD_COUNT);
  assert.ok(felt.validateFeltState(state));
});

// The old reader derived every number by reading back what visual_bridge had
// already written to the root style, which made a CSS custom property the
// transport for the value rather than a presentation of it.
test("published values win over the DOM reflection of older ones", () => {
  const { felt } = loadFeltState({ cssVars: { "--master-confidence": "0.10" } });
  assert.equal(felt.snapshot().confidence, 0.1);

  felt.publish({ confidence: 0.93 });

  assert.equal(felt.snapshot().confidence, 0.93);
  assert.equal(felt.collectFeltState().split("|")[3], "0.93");
});

test("the scrape survives as the fallback for fields nobody published", () => {
  const { felt } = loadFeltState({
    cssVars: { "--master-entropy": "0.44", "--master-confidence": "0.77" },
    dataset: { masterState: "listening", pipelineStage: "route" },
  });

  felt.publish({ confidence: 0.5 });
  const [mood, mode, entropy, confidence] = felt.collectFeltState().split("|");

  assert.equal(mood, "listening");
  assert.equal(mode, "route");
  assert.equal(entropy, "0.44");
  assert.equal(confidence, "0.50");
});

test("master:emotion and master:visual publish into the store", () => {
  const { felt, emit } = loadFeltState();

  emit("master:visual", { entropy: 0.62, confidence: 0.31, mode: "tool" });
  emit("master:emotion", { arousal: 0.81, valence: -0.24 });
  const [, mode, entropy, confidence, arousal, valence] = felt.collectFeltState().split("|");

  assert.equal(mode, "tool");
  assert.equal(entropy, "0.62");
  assert.equal(confidence, "0.31");
  assert.equal(arousal, "0.81");
  assert.equal(valence, "-0.24");
});

// publish() is called with partials by every publisher, and the face runtime
// hands it State fields that are undefined until the face is up.
test("publish ignores absent and non-finite fields instead of storing them", () => {
  const { felt } = loadFeltState({ cssVars: { "--master-confidence": "0.86" } });

  felt.publish({ confidence: undefined, entropy: Number.NaN, mood: "  " });

  assert.equal(felt.snapshot().confidence, 0.86);
  assert.equal(felt.snapshot().mood, "idle");
  assert.ok(felt.validateFeltState(felt.collectFeltState()));
});

test("hist entropy is averaged from the stored emotion history", () => {
  const { felt } = loadFeltState({ history: [{ entropy: 0.2 }, { entropy: 0.6 }] });

  assert.equal(felt.collectFeltState().split("|")[6], "0.40");
});
