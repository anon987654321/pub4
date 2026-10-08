// A viseme plan is a timeline in utterance milliseconds, so it has to be read
// against the clock of the thing speaking. It was one setTimeout per frame from
// whenever startVisemeAnim was called, and nothing could cancel it once armed.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const source = readFileSync(join(publicDir, "face_speech_playback.js"), "utf8");

// face_speech_playback.js is concatenated into face.runtime.js, so State, tts,
// emitTtsEvent and ttsLive are free variables from the enclosing runtime.
function loadPlayback(plan) {
  let clock = 0;
  let nextId = 1;
  const intervals = new Map();
  const emitted = [];
  const tts = { visemePlan: plan, visemeTimer: null, audio: null, playing: false };
  const State = { viseme: "neutral", visemeAmp: 0 };

  const sandbox = {
    window: { MASTER: {}, MASTER_LOG: null },
    State,
    tts,
    ttsLive: null,
    emitTtsEvent: (name, detail) => emitted.push({ name, ...detail }),
    setInterval: (fn, ms) => { intervals.set(nextId, { fn, ms }); return nextId++; },
    clearInterval: (id) => intervals.delete(id),
    setTimeout: () => { throw new Error("plan playback must not schedule wall-clock timeouts"); },
    performance: { now: () => clock },
  };
  sandbox.window.window = sandbox.window;
  runInContext(source, createContext(sandbox));

  return {
    api: sandbox.window.MASTER_SPEECH_PLAYBACK,
    tts,
    State,
    emitted,
    liveTimers: () => intervals.size,
    // One pass of every armed interval, as the browser would at its period.
    tick(ms = 90) {
      clock += ms;
      Array.from(intervals.values()).forEach(({ fn }) => fn());
    },
  };
}

const PLAN = [
  { t: 0, shape: "A", amp: 1 },
  { t: 200, shape: "M", amp: 0.5 },
  { t: 400, shape: "O", amp: 0.8 },
];

test("plan frames are applied on the audio clock, not on elapsed wall time", () => {
  const h = loadPlayback(PLAN);
  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 0, duration: 1 };
  h.api.startVisemeAnim("hello");

  h.tick();
  assert.equal(h.State.viseme, "A");

  // Wall clock advances with every tick; the audio does not.
  h.tick();
  h.tick();
  assert.equal(h.State.viseme, "A", "frames advanced without the audio advancing");

  h.tts.audio.currentTime = 0.25;
  h.tick();
  assert.equal(h.State.viseme, "M");
});

// forwardEarlyVisemePlan arms playback the moment the plan header arrives,
// before the audio element exists. The plan used to run out against wall time
// while the utterance was still being synthesized.
test("the cursor holds at the first frame until playback actually starts", () => {
  const h = loadPlayback(PLAN);
  h.tts.playing = true;
  h.api.startVisemeAnim("hello");

  h.tick();
  h.tick();
  h.tick();
  assert.equal(h.State.viseme, "neutral");
  assert.equal(h.emitted.length, 0);

  h.tts.audio = { paused: false, currentTime: 0, duration: 1 };
  h.tick();
  assert.equal(h.State.viseme, "A");
});

// audio.onplay arms a second run for the same utterance. stopVisemeAnim cleared
// only tts.visemeTimer, so the setTimeout chain from the first survived it and
// both drove the mouth, offset by however long synthesis took.
test("a second start replaces the first rather than stacking on it", () => {
  const h = loadPlayback(PLAN);
  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 0, duration: 1 };

  h.api.startVisemeAnim("hello");
  h.api.startVisemeAnim("hello");

  assert.equal(h.liveTimers(), 1);
  h.tick();
  assert.equal(h.emitted.length, 1, "one driver, one frame emitted");
});

test("stopVisemeAnim ends plan playback", () => {
  const h = loadPlayback(PLAN);
  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 0, duration: 1 };
  h.api.startVisemeAnim("hello");

  h.api.stopVisemeAnim();
  h.tts.audio.currentTime = 0.5;
  h.tick();

  assert.equal(h.liveTimers(), 0);
  assert.equal(h.emitted.length, 0);
});

// Frames from a cancelled utterance kept firing through the next one, because
// their only guard was `tts.playing || tts.audio`, which the next one satisfies.
test("plan playback stops when the utterance is no longer playing", () => {
  const h = loadPlayback(PLAN);
  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 0, duration: 1 };
  h.api.startVisemeAnim("hello");

  h.tts.playing = false;
  h.tts.audio = null;
  h.tick();

  assert.equal(h.liveTimers(), 0);
});

test("the browser speech path runs the plan on the wall clock it starts on", () => {
  const h = loadPlayback(PLAN);
  h.tts.playing = true;
  h.api.startVisemeAnim("hello", { clock: "wall" });

  h.tick();
  assert.equal(h.State.viseme, "A");
  h.tick(120);
  assert.equal(h.State.viseme, "A");
  h.tick(120);
  assert.equal(h.State.viseme, "M");
});

test("plan playback releases its timer once the last frame is applied", () => {
  const h = loadPlayback(PLAN);
  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 1, duration: 1 };
  h.api.startVisemeAnim("hello");

  h.tick();

  assert.equal(h.State.viseme, "O");
  assert.equal(h.liveTimers(), 0);
});

test("an absent or empty plan falls through to the character walk", () => {
  const h = loadPlayback(null);
  assert.equal(h.api.planFrames(), null);

  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 0, duration: 2 };
  h.api.startVisemeAnim("hello");
  h.tick();

  assert.notEqual(h.State.viseme, "neutral");
});
