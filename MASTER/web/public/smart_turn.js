// Smart Turn v3: semantic endpointing from the waveform.
//
// The linguistic endpointer in face.part5.txt decides from the words — someone
// who just said "og" is still going. This decides from how they sounded, which
// is the half a transcript cannot see: pitch falling, final lengthening, the
// difference between a pause for breath and a finished sentence.
//
// It is opt-in and it is allowed to fail. Every entry point returns null rather
// than throwing, and the caller keeps the linguistic answer when it does, so a
// blocked microphone, an absent model or a browser without AudioWorklet costs
// nothing but the feature. This runs entirely in the page — the VPS is not in
// the loop, which is the point, since its latency floor is what we are avoiding.
//
// Cost, so it is not a surprise: ~21MB fetched once and then cached — a 12.9MB
// WASM runtime and an 8.3MB int8 model. That is why it is not on by default.
//
// Model: pipecat-ai/smart-turn-v3.2-cpu, BSD-2-Clause, a Whisper Tiny encoder
// with a linear head. Input is an (1, 80, 800) log-Mel spectrogram of the last
// 8 seconds; output is one already-sigmoid probability that the speaker has
// finished. See whisper_mel.js for the feature pipeline it expects.

import { logMelSpectrogram, N_MELS, N_FRAMES, SAMPLE_RATE, N_SAMPLES } from "./whisper_mel.js";

const ORT_URL = "/vendor/onnxruntime/ort.wasm.min.mjs";
const ORT_WASM_DIR = "/vendor/onnxruntime/";
const MODEL_URL = "/models/smart-turn-v3.2-cpu.onnx";
const WORKLET_URL = "/mic_capture_processor.js";

// Above this the model says the turn ended. 0.5 is the reference threshold;
// raised a little because the cost of the two mistakes is not symmetric — a
// false "finished" cuts someone off, a false "still going" only waits.
export const COMPLETE_THRESHOLD = 0.6;

const state = {
  session: null,
  loading: null,
  capture: null,
  captureLoading: null,
  failed: false,
};

export function smartTurnEnabled() {
  try {
    if (new URLSearchParams(window.location.search).get("smart_turn") === "1") return true;
    return localStorage.getItem("master:smart-turn") === "1";
  } catch (err) {
    return false;
  }
}

export function setSmartTurn(on) {
  try { localStorage.setItem("master:smart-turn", on ? "1" : "0"); } catch (err) { /* private mode */ }
}

function note(stage, err) {
  window.MASTER_LOG?.warn?.(`smart_turn:${stage}`, err);
}

// --- model ------------------------------------------------------------------

async function loadSession() {
  if (state.session) return state.session;
  if (state.failed) return null;
  if (state.loading) return state.loading;

  state.loading = (async () => {
    const ort = await import(ORT_URL);
    // Self-hosted: a strict CSP has no CDN, and the default wasm paths point at
    // one. Single-threaded because cross-origin isolation is a server-wide
    // change and 14ms is already well inside the budget.
    ort.env.wasm.wasmPaths = ORT_WASM_DIR;
    ort.env.wasm.numThreads = 1;
    ort.env.logLevel = "error";
    const session = await ort.InferenceSession.create(MODEL_URL, {
      executionProviders: ["wasm"],
      graphOptimizationLevel: "all",
    });
    state.session = { ort, session };
    return state.session;
  })().catch((err) => {
    note("session", err);
    state.failed = true;
    state.loading = null;
    return null;
  });

  return state.loading;
}

// --- microphone -------------------------------------------------------------

async function loadCapture() {
  if (state.capture) return state.capture;
  if (state.failed) return null;
  if (state.captureLoading) return state.captureLoading;

  state.captureLoading = (async () => {
    // Asking for 16kHz directly avoids resampling in JS. Browsers that refuse
    // give their own rate and resample() handles it.
    const ctx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: SAMPLE_RATE });
    await ctx.audioWorklet.addModule(WORKLET_URL);
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
    const source = ctx.createMediaStreamSource(stream);
    const node = new AudioWorkletNode(ctx, "mic-capture", {
      numberOfInputs: 1,
      numberOfOutputs: 0,
      processorOptions: { seconds: 8 },
    });
    source.connect(node);
    state.capture = { ctx, stream, node };
    return state.capture;
  })().catch((err) => {
    note("capture", err);
    state.failed = true;
    state.captureLoading = null;
    return null;
  });

  return state.captureLoading;
}

export function releaseMic() {
  const capture = state.capture;
  state.capture = null;
  state.captureLoading = null;
  if (!capture) return;
  try { capture.stream.getTracks().forEach((t) => t.stop()); } catch (err) { note("release_tracks", err); }
  try { capture.node.disconnect(); } catch (err) { note("release_node", err); }
  try { capture.ctx.close(); } catch (err) { note("release_ctx", err); }
}

function snapshot(capture, timeoutMs = 250) {
  return new Promise((resolve) => {
    let settled = false;
    const done = (value) => { if (!settled) { settled = true; resolve(value); } };
    const timer = setTimeout(() => done(null), timeoutMs);
    capture.node.port.onmessage = (event) => {
      if (event.data?.type !== "snapshot") return;
      clearTimeout(timer);
      done(event.data);
    };
    try { capture.node.port.postMessage({ type: "snapshot" }); } catch (err) { note("snapshot", err); done(null); }
  });
}

// Linear resample. Only runs where the browser refused a 16kHz context; the
// model is not sensitive enough for the difference from a windowed sinc to
// matter, and a wrong sample rate would matter enormously.
function resample(samples, fromRate, toRate = SAMPLE_RATE) {
  if (fromRate === toRate) return samples;
  const ratio = fromRate / toRate;
  const out = new Float32Array(Math.floor(samples.length / ratio));
  for (let i = 0; i < out.length; i += 1) {
    const pos = i * ratio;
    const idx = Math.floor(pos);
    const frac = pos - idx;
    const a = samples[idx] || 0;
    const b = samples[idx + 1] !== undefined ? samples[idx + 1] : a;
    out[i] = a + (b - a) * frac;
  }
  return out;
}

// --- public -----------------------------------------------------------------

// Warm both halves so the first real decision is not the one that pays for the
// download. Safe to call repeatedly.
export async function warmUp() {
  if (!smartTurnEnabled()) return false;
  const [session, capture] = await Promise.all([loadSession(), loadCapture()]);
  return Boolean(session && capture);
}

// Returns the probability the speaker has finished, or null when unavailable —
// never throws, because the caller has a working answer without this one.
export async function predictEndpoint() {
  if (!smartTurnEnabled() || state.failed) return null;
  const session = await loadSession();
  const capture = await loadCapture();
  if (!session || !capture) return null;

  const snap = await snapshot(capture);
  if (!snap || !snap.samples?.length) return null;

  const samples = resample(snap.samples, snap.sampleRate || SAMPLE_RATE);
  // Under a quarter second of audio is not an utterance to judge.
  if (samples.length < SAMPLE_RATE / 4) return null;

  try {
    const mel = logMelSpectrogram(samples);
    const tensor = new session.ort.Tensor("float32", mel, [1, N_MELS, N_FRAMES]);
    const out = await session.session.run({ input_features: tensor });
    const first = out[Object.keys(out)[0]];
    const value = Number(first?.data?.[0]);
    return Number.isFinite(value) ? value : null;
  } catch (err) {
    note("predict", err);
    return null;
  }
}

export const _internals = { resample, MODEL_URL, ORT_URL, N_SAMPLES };
