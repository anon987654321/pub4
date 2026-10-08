import test from "node:test";
import assert from "node:assert/strict";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFileSync, existsSync } from "node:fs";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const mel = await import(join(publicDir, "whisper_mel.js"));
const {
  logMelSpectrogram, melFilterBank, fitToChunk, zeroMeanUnitVar,
  N_MELS, N_FRAMES, N_FFT, SAMPLE_RATE, N_SAMPLES,
} = mel;

const N_FREQS = N_FFT / 2 + 1;

function tone(hz, n = N_SAMPLES) {
  const a = new Float32Array(n);
  for (let i = 0; i < n; i += 1) a[i] = Math.sin((2 * Math.PI * hz * i) / SAMPLE_RATE);
  return a;
}

function filterCentreHz(filters, m) {
  let peak = 0;
  let idx = 0;
  for (let k = 0; k < N_FREQS; k += 1) {
    const w = filters[m * N_FREQS + k];
    if (w > peak) { peak = w; idx = k; }
  }
  return (idx * SAMPLE_RATE) / 2 / (N_FREQS - 1);
}

function loudestMel(spectrogram) {
  let best = -Infinity;
  let bestM = -1;
  for (let m = 0; m < N_MELS; m += 1) {
    let sum = 0;
    for (let f = 200; f < 600; f += 1) sum += spectrogram[m * N_FRAMES + f];
    if (sum > best) { best = sum; bestM = m; }
  }
  return bestM;
}

test("mel filterbank is well formed and ascending", () => {
  const filters = melFilterBank();
  let previous = -1;
  for (let m = 0; m < N_MELS; m += 1) {
    let area = 0;
    for (let k = 0; k < N_FREQS; k += 1) area += filters[m * N_FREQS + k];
    assert.ok(area > 0 && Number.isFinite(area), `filter ${m} has no area`);
    const centre = filterCentreHz(filters, m);
    assert.ok(centre >= previous, `filter ${m} centre went backwards`);
    previous = centre;
  }
});

// The bug this exists for: n_fft is 400, and zero-padding the frame to a 512
// point FFT silently rescales every bin by 512/400, so a 1kHz tone landed in
// the filter centred on 1280Hz. The spectrogram still looked entirely
// reasonable — right shape, right range, no NaN — which is why the check has to
// be a frequency one.
test("a tone lands in the mel filter centred on it", () => {
  const filters = melFilterBank();
  for (const hz of [440, 1000, 3000]) {
    const m = loudestMel(logMelSpectrogram(tone(hz)));
    const centre = filterCentreHz(filters, m);
    const ratio = centre / hz;
    assert.ok(ratio > 0.9 && ratio < 1.1,
      `${hz}Hz tone peaked in a filter centred at ${Math.round(centre)}Hz (ratio ${ratio.toFixed(3)})`);
  }
});

test("spectrogram has the shape and dynamic range the model expects", () => {
  const spectrogram = logMelSpectrogram(tone(1000));
  assert.equal(spectrogram.length, N_MELS * N_FRAMES);
  assert.ok(spectrogram.every(Number.isFinite), "spectrogram has non-finite values");
  let lo = Infinity;
  let hi = -Infinity;
  for (const v of spectrogram) { if (v < lo) lo = v; if (v > hi) hi = v; }
  // Whisper floors at (max - 8) then maps by (x + 4) / 4, so the range is
  // exactly 2 whenever anything reaches the floor.
  assert.ok(Math.abs((hi - lo) - 2.0) < 1e-3, `range width ${(hi - lo).toFixed(4)}, expected 2`);
});

test("short audio is padded at the front so the ending survives", () => {
  const short = new Float32Array(1000).fill(0.5);
  const fitted = fitToChunk(short);
  assert.equal(fitted.length, N_SAMPLES);
  assert.equal(fitted[0], 0);
  assert.equal(fitted[N_SAMPLES - 1], 0.5);
});

test("long audio keeps its last 8 seconds", () => {
  const long = new Float32Array(N_SAMPLES * 2);
  long[long.length - 1] = 0.75;
  long[0] = 0.25;
  const fitted = fitToChunk(long);
  assert.equal(fitted.length, N_SAMPLES);
  assert.equal(fitted[N_SAMPLES - 1], 0.75);
  assert.equal(fitted[0], 0);
});

test("waveform normalisation is zero mean and unit variance", () => {
  const raw = new Float32Array(1000);
  for (let i = 0; i < raw.length; i += 1) raw[i] = 3 + Math.sin(i);
  const out = zeroMeanUnitVar(raw);
  let sum = 0;
  for (const v of out) sum += v;
  const mean = sum / out.length;
  let varSum = 0;
  for (const v of out) varSum += (v - mean) * (v - mean);
  assert.ok(Math.abs(mean) < 1e-5, `mean ${mean}`);
  assert.ok(Math.abs(varSum / out.length - 1) < 1e-3, `variance ${varSum / out.length}`);
});

test("silence produces a finite spectrogram rather than -Infinity", () => {
  const spectrogram = logMelSpectrogram(new Float32Array(N_SAMPLES));
  assert.ok(spectrogram.every(Number.isFinite));
});

test("the vendored model and runtime are present and are not error pages", () => {
  const model = join(publicDir, "models", "smart-turn-v3.2-cpu.onnx");
  const wasm = join(publicDir, "vendor", "onnxruntime", "ort-wasm-simd-threaded.wasm");
  for (const path of [model, wasm]) {
    assert.ok(existsSync(path), `${path} missing — run script/build_smart_turn.sh`);
  }
  // A 404 saved under a .onnx name is small and starts with '<'.
  const head = readFileSync(model).subarray(0, 8);
  assert.notEqual(head[0], 0x3c, "model looks like an HTML error page");
  assert.ok(readFileSync(wasm).subarray(0, 4).equals(Buffer.from([0x00, 0x61, 0x73, 0x6d])),
    "wasm magic missing");
});
