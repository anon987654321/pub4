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

// blinkInterval is the gap BETWEEN blinks, so a smaller number is a face that
// blinks more. People blink most while speaking and least while holding a
// thought, which is the order these intervals encode. Asserting the ordering
// rather than a single pair states the intent, and the numbers were set by
// measuring ten simulated minutes per mode against a 15-20/min human resting
// rate — so they are a finding, not a preference to be nudged.
test("attention model varies blink intervals by cognitive mode", () => {
  const { attn } = loadAttention();
  const thinking = attn.policyFor("thinking", false);
  const listening = attn.policyFor("listening", false);
  const speaking = attn.policyFor("speaking", false);
  assert.ok(speaking.blinkInterval[0] < listening.blinkInterval[0],
    "speaking should blink more often than listening");
  assert.ok(listening.blinkInterval[0] < thinking.blinkInterval[0],
    "listening should blink more often than holding a thought");
  assert.ok(thinking.fixationPitch < 0, "thinking should look down");
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

// Regression: VOICE_IDLE_SIGNATURES declares a per-persona `saccade` value
// (anchor: 0.10, the most composed; ezinne: 0.26, the most fidgety) meant to
// read as a "future-human, unhurried" temperament -- but it was only ever
// wired into breath/blink timing, never into gaze jitter amplitude itself,
// so every persona actually had identical eye/head restlessness. `saccade`
// in tick()'s ctx must now scale the resulting jitter magnitude.
test("attention tick scales jitter magnitude by the persona composure dial", () => {
  function averageJitterMagnitude(saccade) {
    const { attn, advance } = loadAttention(0);
    attn.reset({ blinkMs: 4200 });
    let total = 0, samples = 0;
    for (let i = 0; i < 600; i += 1) {
      advance(50);
      const out = attn.tick({ t: i * 50, mode: "idle", reducedMotion: false, frameIndex: i, saccade });
      total += Math.abs(out.saccadeX) + Math.abs(out.microJitter);
      samples += 1;
    }
    return total / samples;
  }

  const still = averageJitterMagnitude(0.10); // anchor
  const fidgety = averageJitterMagnitude(0.26); // ezinne
  assert.ok(still < fidgety, `expected still persona (${still}) to jitter less than fidgety (${fidgety})`);
  assert.ok(still < averageJitterMagnitude(0.20) * 0.8, "still persona should be meaningfully below the 0.2 baseline");
});
