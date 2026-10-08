import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";

const source = readFileSync(
  new URL("../public/face_speech_playback.js", import.meta.url),
  "utf8",
);

function loadPlayback() {
  let nextId = 1;
  const intervals = new Map();
  const emitted = [];
  const tts = {
    visemePlan: null,
    performancePlan: {
      schema: 1,
      clock: "audio",
      duration_normalization: true,
      performance_id: "0123456789abcdef0123",
      estimated_duration_ms: 1000,
      events: [
        { at_ms: 250, type: "accent", index: 0, energy: 0.9 },
        { at_ms: 700, type: "pause", index: 0, duration_ms: 180 },
      ],
    },
    visemeTimer: null,
    audio: null,
    playing: false,
  };
  const State = { viseme: "neutral", visemeAmp: 0 };
  const sandbox = {
    window: { MASTER: {}, MASTER_LOG: null },
    State,
    tts,
    ttsLive: null,
    emitTtsEvent: (name, detail) => emitted.push({ name, ...detail }),
    setInterval: (fn, ms) => { intervals.set(nextId, { fn, ms }); return nextId++; },
    clearInterval: (id) => intervals.delete(id),
    setTimeout: () => { throw new Error("performance timeline must use the audio clock"); },
  };
  sandbox.window.window = sandbox.window;
  runInContext(source, createContext(sandbox));

  return {
    api: sandbox.window.MASTER_SPEECH_PLAYBACK,
    tts,
    emitted,
    tick() { Array.from(intervals.values()).forEach(({ fn }) => fn()); },
  };
}

test("performance events follow audio currentTime", () => {
  const h = loadPlayback();
  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 0.249, duration: 1 };
  h.api.startVisemeAnim("hello");
  h.tick();
  assert.equal(h.emitted.filter((e) => e.name === "tts:performance:event").length, 0);

  h.tts.audio.currentTime = 0.25;
  h.tick();
  const events = h.emitted.filter((e) => e.name === "tts:performance:event");
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "accent");
  assert.equal(events[0].performance_id, "0123456789abcdef0123");
});

test("performance normalization maps the estimated score onto real audio duration", () => {
  const h = loadPlayback();
  h.tts.playing = true;
  h.tts.audio = { paused: false, currentTime: 0.5, duration: 2 };
  h.api.startVisemeAnim("hello");
  h.tick();

  const events = h.emitted.filter((e) => e.name === "tts:performance:event");
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "accent");
});
