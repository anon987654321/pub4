import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

// The face builds data/voice.yml's post_chain as WebAudio nodes, so this test
// reads the declaration from the yml and the builder from the shipped source.
// A paraphrase of either would let the two drift, which is the defect the port
// closed: the page had its own invented chain while the terminal used dilla's.
const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "..", "public", "face_speech_runtime.js"), "utf8");
const voiceYml = readFileSync(join(here, "..", "..", "data", "voice.yml"), "utf8");

const declaredChain = (() => {
  const match = voiceYml.match(/^\s*post_chain:\s*(?:>-?|\|-?)?\s*"?([^"\n]+)"?\s*$/m);
  assert.ok(match, "post_chain not found in data/voice.yml");
  return match[1].trim();
})();

function extract(name, pattern) {
  const match = source.match(pattern);
  assert.ok(match, `${name} not found in face_speech_runtime.js`);
  return match[0];
}

const code = [
  extract("parseFilterArgs", /function parseFilterArgs\(argText\) \{[\s\S]*?\n\}/),
  extract("dbToGain", /function dbToGain\(text\) \{[\s\S]*?\n\}/),
  extract("buildChorus", /function buildChorus\(ctx, args\) \{[\s\S]*?\n\}/),
  extract("buildPhaser", /function buildPhaser\(ctx, args\) \{[\s\S]*?\n\}/),
  extract("buildChainNode", /function buildChainNode\(ctx, name, args\) \{[\s\S]*?\n\}/),
  extract("buildVoiceChain", /function buildVoiceChain\(ctx, chainText\) \{[\s\S]*?\n\}/),
].join("\n");

// Enough of an AudioContext to record what was built and how it was wired.
// Every node keeps the parameters the builder set, so an assertion can name a
// frequency rather than a node count.
function stubContext() {
  const created = [];
  const param = (value) => ({ value, connectedFrom: [] });
  const node = (kind, extra = {}) => {
    const made = { kind, outputs: [], connect(target) { this.outputs.push(target); }, ...extra };
    created.push(made);
    return made;
  };
  const ctx = {
    created,
    createGain: () => node("gain", { gain: param(1) }),
    createBiquadFilter: () => node("biquad", { type: "", frequency: param(350), Q: param(1), gain: param(0) }),
    createDelay: () => node("delay", { delayTime: param(0) }),
    createOscillator: () => node("oscillator", { frequency: param(440), started: false, start() { this.started = true; } }),
    createDynamicsCompressor: () => node("compressor", {
      threshold: param(-24), knee: param(30), ratio: param(12), attack: param(0.003), release: param(0.25),
    }),
  };
  return ctx;
}

function build(chainText) {
  const ctx = stubContext();
  const buildVoiceChain = runInNewContext(`${code}\nbuildVoiceChain`, { console });
  return { ctx, chain: buildVoiceChain(ctx, chainText) };
}

test("every filter the declared chain names has a node", () => {
  const { chain } = build(declaredChain);
  assert.ok(chain, "the declared chain built nothing");
  assert.equal(chain.skipped.join(","), "", "a filter was dropped silently");
  assert.equal(chain.stages, declaredChain.split(",").length);
});

test("the formant peaks carry the declared frequencies and gains", () => {
  const { ctx } = build(declaredChain);
  const peaks = ctx.created.filter((n) => n.kind === "biquad" && n.type === "peaking");
  assert.deepEqual(peaks.map((p) => p.frequency.value), [520, 1480, 2520]);
  assert.deepEqual(peaks.map((p) => p.gain.value), [4.5, 3.6, 2.8]);
  assert.deepEqual(peaks.map((p) => p.Q.value), [1.1, 1.3, 1.5]);
});

// The expected band is read from the declaration, so the test holds the face
// to voice.yml rather than to whatever numbers voice.yml carried once.
test("the band is the declared highpass and lowpass", () => {
  const { ctx } = build(declaredChain);
  const band = ctx.created.filter((n) => n.kind === "biquad" && ["highpass", "lowpass"].includes(n.type));
  const declared = [...declaredChain.matchAll(/(highpass|lowpass)=f=([\d.]+)/g)].map((m) => [m[1], parseFloat(m[2])]);
  assert.ok(declared.length > 0, "voice.yml declares no band");
  assert.deepEqual(band.map((n) => [n.type, n.frequency.value]), declared);
});

test("the compressor carries the declared threshold, ratio and times", () => {
  const { ctx } = build("acompressor=threshold=-18dB:ratio=2.2:attack=8:release=100:makeup=1");
  const comp = ctx.created.find((n) => n.kind === "compressor");
  assert.ok(comp, "acompressor built no compressor");
  assert.equal(comp.threshold.value, -18);
  assert.equal(comp.ratio.value, 2.2);
  assert.equal(comp.attack.value, 0.008);
  assert.equal(comp.release.value, 0.1);
});

// volume=23dB is a level, not a number to be copied: read as a plain float it
// would be a gain of 23 rather than 14.1, which is 4 dB of clipping.
test("a dB volume becomes the matching linear gain", () => {
  const { ctx } = build("volume=23dB");
  const gain = ctx.created.find((n) => n.kind === "gain");
  assert.ok(Math.abs(gain.gain.value - Math.pow(10, 23 / 20)) < 1e-9);
});

test("the chorus builds one delay per declared voice, each swept", () => {
  const { ctx } = build("chorus=0.5:0.7:19|27:0.3|0.26:0.24|0.2:0.9|1.4");
  const delays = ctx.created.filter((n) => n.kind === "delay");
  assert.deepEqual(delays.map((d) => Math.round(d.delayTime.value * 1000)), [19, 27]);
  const oscillators = ctx.created.filter((n) => n.kind === "oscillator");
  assert.deepEqual(oscillators.map((o) => o.frequency.value), [0.24, 0.2]);
  assert.ok(oscillators.every((o) => o.started), "an LFO was built but never started");
});

test("the phaser sweeps allpass stages at the declared speed", () => {
  const { ctx } = build("aphaser=type=t:speed=0.12:decay=0.3:delay=2.4");
  const allpass = ctx.created.filter((n) => n.kind === "biquad" && n.type === "allpass");
  assert.equal(allpass.length, 4);
  assert.equal(ctx.created.find((n) => n.kind === "oscillator").frequency.value, 0.12);
});

// A filter with no node must be named rather than dropped, because a chain that
// quietly builds seven of its eight filters is a voice that differs from the
// server's without saying so.
test("an unsupported filter is reported, not swallowed", () => {
  const { chain } = build("highpass=f=200,acrusher=bits=8");
  assert.equal(chain.skipped.join(","), "acrusher");
  assert.equal(chain.stages, 1);
});

test("an empty chain builds nothing so the caller can fall back", () => {
  assert.equal(build("").chain, null);
});
