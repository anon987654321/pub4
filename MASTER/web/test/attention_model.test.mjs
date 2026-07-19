import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const source = readFileSync(join(publicDir, "attention_model.js"), "utf8");

function loadAttention(now = 0) {
  let clock = now;
  const sandbox = {
    window: { MASTER: {}, MASTER_ATTENTION: null },
    performance: { now: () => clock },
  };
  sandbox.window.window = sandbox.window;
  sandbox.window.performance = sandbox.performance;
  runInContext(source, createContext(sandbox));
  const attn = sandbox.window.MASTER.attention;
  return {
    attn,
    advance: (ms) => { clock += ms; },
  };
}

test("attention model varies blink intervals by cognitive mode", () => {
  const { attn } = loadAttention();
  const thinking = attn.policyFor("thinking", false);
  const listening = attn.policyFor("listening", false);
  assert.ok(listening.blinkInterval[0] > thinking.blinkInterval[0]);
  assert.ok(thinking.fixationPitch < 0);
});

test("attention tick returns gaze offsets and eye close envelope", () => {
  const { attn, advance } = loadAttention(0);
  attn.reset({ blinkMs: 1000 });
  let sawBlink = false;
  for (let i = 0; i < 400; i += 1) {
    advance(50);
    const out = attn.tick({
      t: i * 50,
      mode: "idle",
      reducedMotion: false,
      frameIndex: i,
    });
    assert.equal(typeof out.saccadeX, "number");
    assert.equal(typeof out.microJitter, "number");
    assert.equal(typeof out.eyeCloseTarget, "number");
    if (out.eyeCloseTarget > 0.2) sawBlink = true;
  }
  assert.ok(sawBlink, "expected at least one blink envelope in idle simulation");
});

test("attention suppresses saccades less in listening than thinking", () => {
  const { attn } = loadAttention();
  const listen = attn.policyFor("listening", false);
  const think = attn.policyFor("thinking", false);
  assert.ok(listen.saccadeAmp > think.saccadeAmp);
});
