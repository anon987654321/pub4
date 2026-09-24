// Whisper log-Mel features, in the browser.
//
// Smart Turn v3 is a Whisper Tiny encoder with a linear head, so its ONNX input
// is `input_features` — an (1, 80, 800) log-Mel spectrogram, not the waveform.
// The reference implementation gets these from
// `WhisperFeatureExtractor(chunk_length=8)`; this is that pipeline, and it has
// to match it closely, because a mel spectrogram that is merely plausible
// produces a confident number that means nothing.
//
// The steps, in the order the extractor applies them:
//
//   1. keep the last 8s and zero-pad at the BEGINNING (audio_utils.py — the end
//      of the utterance is the part the decision is about, so it is the part
//      that must survive)
//   2. zero-mean unit-variance the waveform (do_normalize=True)
//   3. STFT, n_fft 400, hop 160, Hann, centred with reflect padding
//   4. power spectrum, drop the final frame -> 800 frames
//   5. 80 mel filters, Slaney scale and Slaney normalisation
//   6. log10, floor at (max - 8), then (x + 4) / 4
//
// Steps 5 and 6 are Whisper's own, not librosa defaults, and the floor in 6 is
// computed over the WHOLE spectrogram rather than per frame.

export const SAMPLE_RATE = 16000;
export const CHUNK_SECONDS = 8;
export const N_SAMPLES = SAMPLE_RATE * CHUNK_SECONDS; // 128000
export const N_FFT = 400;
export const HOP_LENGTH = 160;
export const N_MELS = 80;
export const N_FRAMES = N_SAMPLES / HOP_LENGTH; // 800
const N_FREQS = N_FFT / 2 + 1; // 201

// --- mel filterbank ---------------------------------------------------------
// Slaney-scale mel, which is what Whisper ships in mel_filters.npz. Generating
// it costs ~16k multiplies once, and saves vendoring a binary whose provenance
// would then need explaining.

function hzToMel(hz) {
  // Slaney: linear below 1kHz, log above.
  const minLogHz = 1000.0;
  const minLogMel = 15.0;
  const logstep = 27.0 / Math.log(6.4);
  if (hz >= minLogHz) return minLogMel + Math.log(hz / minLogHz) * logstep;
  return 3.0 * hz / 200.0;
}

function melToHz(mel) {
  const minLogHz = 1000.0;
  const minLogMel = 15.0;
  const logstep = Math.log(6.4) / 27.0;
  if (mel >= minLogMel) return minLogHz * Math.exp(logstep * (mel - minLogMel));
  return 200.0 * mel / 3.0;
}

export function melFilterBank(nMels = N_MELS, nFreqs = N_FREQS, sampleRate = SAMPLE_RATE) {
  const fMin = 0.0;
  const fMax = sampleRate / 2.0;
  const melMin = hzToMel(fMin);
  const melMax = hzToMel(fMax);

  const melPoints = new Float64Array(nMels + 2);
  for (let i = 0; i < nMels + 2; i += 1) {
    melPoints[i] = melToHz(melMin + ((melMax - melMin) * i) / (nMels + 1));
  }

  const fftFreqs = new Float64Array(nFreqs);
  for (let i = 0; i < nFreqs; i += 1) fftFreqs[i] = (sampleRate / 2.0) * (i / (nFreqs - 1));

  // Row-major (nMels, nFreqs).
  const filters = new Float32Array(nMels * nFreqs);
  for (let m = 0; m < nMels; m += 1) {
    const left = melPoints[m];
    const centre = melPoints[m + 1];
    const right = melPoints[m + 2];
    // Slaney normalisation: each filter integrates to the same area, so wide
    // high-frequency filters do not dominate the narrow low ones.
    const enorm = 2.0 / (right - left);
    for (let k = 0; k < nFreqs; k += 1) {
      const f = fftFreqs[k];
      const lower = (f - left) / (centre - left);
      const upper = (right - f) / (right - centre);
      const w = Math.max(0.0, Math.min(lower, upper));
      filters[m * nFreqs + k] = w * enorm;
    }
  }
  return filters;
}

// --- FFT --------------------------------------------------------------------
// n_fft is 400, which is not a power of two. Zero-padding the frame to 512 and
// reading back 201 bins does NOT give a 400-point DFT: it gives a 512-point one,
// whose bin k is k*sr/512 rather than k*sr/400, so every frequency lands 28%
// high — 512/400. A 1kHz tone came out in the mel filter centred on 1280Hz.
//
// Bluestein turns a DFT of any length into convolutions that a power-of-two FFT
// can do, using nk = (n² + k² − (k−n)²)/2. The chirp b[] and its transform are
// constant, so a frame costs one forward and one inverse 1024-point FFT.

const FFT_SIZE = 1024; // >= 2*N_FFT - 1 = 799

function bitReverseTable(n) {
  const table = new Uint16Array(n);
  const bits = Math.log2(n);
  for (let i = 0; i < n; i += 1) {
    let x = i;
    let r = 0;
    for (let b = 0; b < bits; b += 1) {
      r = (r << 1) | (x & 1);
      x >>= 1;
    }
    table[i] = r;
  }
  return table;
}

const REV = bitReverseTable(FFT_SIZE);
const COS = new Float64Array(FFT_SIZE / 2);
const SIN = new Float64Array(FFT_SIZE / 2);
for (let i = 0; i < FFT_SIZE / 2; i += 1) {
  COS[i] = Math.cos((-2 * Math.PI * i) / FFT_SIZE);
  SIN[i] = Math.sin((-2 * Math.PI * i) / FFT_SIZE);
}

// In-place radix-2 on caller-owned buffers, so a 800-frame pass allocates twice
// rather than 1600 times.
function fftInPlace(re, im) {
  for (let i = 0; i < FFT_SIZE; i += 1) {
    const j = REV[i];
    if (j > i) {
      let t = re[i]; re[i] = re[j]; re[j] = t;
      t = im[i]; im[i] = im[j]; im[j] = t;
    }
  }
  for (let size = 2; size <= FFT_SIZE; size <<= 1) {
    const half = size >> 1;
    const step = FFT_SIZE / size;
    for (let i = 0; i < FFT_SIZE; i += size) {
      for (let j = 0; j < half; j += 1) {
        const k = j * step;
        const tre = re[i + j + half] * COS[k] - im[i + j + half] * SIN[k];
        const tim = re[i + j + half] * SIN[k] + im[i + j + half] * COS[k];
        re[i + j + half] = re[i + j] - tre;
        im[i + j + half] = im[i + j] - tim;
        re[i + j] += tre;
        im[i + j] += tim;
      }
    }
  }
}

function ifftInPlace(re, im) {
  // conj -> forward -> conj -> scale
  for (let i = 0; i < FFT_SIZE; i += 1) im[i] = -im[i];
  fftInPlace(re, im);
  const inv = 1 / FFT_SIZE;
  for (let i = 0; i < FFT_SIZE; i += 1) {
    re[i] *= inv;
    im[i] = -im[i] * inv;
  }
}

// Chirp w[n] = exp(-i*pi*n^2/N), and the transform of its conjugate, both fixed.
const CHIRP_RE = new Float64Array(N_FFT);
const CHIRP_IM = new Float64Array(N_FFT);
for (let n = 0; n < N_FFT; n += 1) {
  // n^2 mod 2N keeps the angle exact for large n instead of losing bits.
  const angle = (-Math.PI * ((n * n) % (2 * N_FFT))) / N_FFT;
  CHIRP_RE[n] = Math.cos(angle);
  CHIRP_IM[n] = Math.sin(angle);
}

const BRE = new Float64Array(FFT_SIZE);
const BIM = new Float64Array(FFT_SIZE);
BRE[0] = CHIRP_RE[0];
BIM[0] = -CHIRP_IM[0];
for (let n = 1; n < N_FFT; n += 1) {
  BRE[n] = CHIRP_RE[n];
  BIM[n] = -CHIRP_IM[n];
  BRE[FFT_SIZE - n] = CHIRP_RE[n];
  BIM[FFT_SIZE - n] = -CHIRP_IM[n];
}
fftInPlace(BRE, BIM);

// Real DFT of a 400-point frame, first N_FREQS bins, into caller buffers.
function dft400(frame, outRe, outIm, workRe, workIm) {
  workRe.fill(0);
  workIm.fill(0);
  for (let n = 0; n < N_FFT; n += 1) {
    workRe[n] = frame[n] * CHIRP_RE[n];
    workIm[n] = frame[n] * CHIRP_IM[n];
  }
  fftInPlace(workRe, workIm);
  for (let i = 0; i < FFT_SIZE; i += 1) {
    const r = workRe[i] * BRE[i] - workIm[i] * BIM[i];
    const m = workRe[i] * BIM[i] + workIm[i] * BRE[i];
    workRe[i] = r;
    workIm[i] = m;
  }
  ifftInPlace(workRe, workIm);
  for (let k = 0; k < N_FREQS; k += 1) {
    outRe[k] = workRe[k] * CHIRP_RE[k] - workIm[k] * CHIRP_IM[k];
    outIm[k] = workRe[k] * CHIRP_IM[k] + workIm[k] * CHIRP_RE[k];
  }
}

const HANN = new Float64Array(N_FFT);
for (let i = 0; i < N_FFT; i += 1) {
  // torch.hann_window default is periodic, which divides by N and not N-1.
  HANN[i] = 0.5 * (1 - Math.cos((2 * Math.PI * i) / N_FFT));
}

// --- pipeline ---------------------------------------------------------------

// Keep the end, pad the front. The decision is about how the utterance ended.
export function fitToChunk(samples) {
  const out = new Float32Array(N_SAMPLES);
  if (samples.length >= N_SAMPLES) {
    out.set(samples.subarray(samples.length - N_SAMPLES));
  } else {
    out.set(samples, N_SAMPLES - samples.length);
  }
  return out;
}

export function zeroMeanUnitVar(samples) {
  let sum = 0;
  for (let i = 0; i < samples.length; i += 1) sum += samples[i];
  const mean = sum / samples.length;
  let varSum = 0;
  for (let i = 0; i < samples.length; i += 1) {
    const d = samples[i] - mean;
    varSum += d * d;
  }
  const scale = 1 / Math.sqrt(varSum / samples.length + 1e-7);
  const out = new Float32Array(samples.length);
  for (let i = 0; i < samples.length; i += 1) out[i] = (samples[i] - mean) * scale;
  return out;
}

// torch.stft(center=True) reflects the signal around its endpoints rather than
// padding with zeros, so the first and last frames are not artificially quiet.
function reflectPad(samples, pad) {
  const out = new Float32Array(samples.length + 2 * pad);
  out.set(samples, pad);
  for (let i = 0; i < pad; i += 1) {
    out[pad - 1 - i] = samples[i + 1];
    out[pad + samples.length + i] = samples[samples.length - 2 - i];
  }
  return out;
}

const FILTERS = melFilterBank();

// Returns Float32Array of N_MELS * N_FRAMES, row-major (mel, frame) — the
// layout the ONNX input wants once a batch dimension is added.
export function logMelSpectrogram(samples) {
  const fitted = fitToChunk(samples);
  const normed = zeroMeanUnitVar(fitted);
  const padded = reflectPad(normed, N_FFT / 2);

  const power = new Float32Array(N_FREQS * N_FRAMES);
  const windowed = new Float64Array(N_FFT);
  const outRe = new Float64Array(N_FREQS);
  const outIm = new Float64Array(N_FREQS);
  const workRe = new Float64Array(FFT_SIZE);
  const workIm = new Float64Array(FFT_SIZE);

  for (let frame = 0; frame < N_FRAMES; frame += 1) {
    const start = frame * HOP_LENGTH;
    for (let i = 0; i < N_FFT; i += 1) windowed[i] = padded[start + i] * HANN[i];
    dft400(windowed, outRe, outIm, workRe, workIm);
    for (let k = 0; k < N_FREQS; k += 1) {
      power[k * N_FRAMES + frame] = outRe[k] * outRe[k] + outIm[k] * outIm[k];
    }
  }

  const mel = new Float32Array(N_MELS * N_FRAMES);
  let maxLog = -Infinity;
  for (let m = 0; m < N_MELS; m += 1) {
    const fRow = m * N_FREQS;
    for (let frame = 0; frame < N_FRAMES; frame += 1) {
      let acc = 0;
      for (let k = 0; k < N_FREQS; k += 1) {
        const w = FILTERS[fRow + k];
        if (w !== 0) acc += w * power[k * N_FRAMES + frame];
      }
      const v = Math.log10(Math.max(acc, 1e-10));
      mel[m * N_FRAMES + frame] = v;
      if (v > maxLog) maxLog = v;
    }
  }

  // The dynamic-range floor is global, not per frame: a quiet frame inside a
  // loud utterance must stay quiet, which is most of what distinguishes a pause
  // from an ending.
  const floor = maxLog - 8.0;
  for (let i = 0; i < mel.length; i += 1) {
    mel[i] = (Math.max(mel[i], floor) + 4.0) / 4.0;
  }
  return mel;
}
