// Canonical audio signal model. Visuals consume AudioField, not raw analyser internals.
(() => {
  "use strict";

  const TAU = Math.PI * 2;
  const state = {
    rms: 0, peak: 0, bass: 0, mid: 0, high: 0, centroid: 0, onset: 0,
    speechActivity: 0, speaker: "unknown", playback: "closed",
    sentencePosition: 0, sampleRate: 0, channels: 0, analyserWindow: 0,
    latencyMs: null, playbackBufferMs: null, underruns: 0,
    updatedAt: 0, version: 0
  };
  const previous = { rms: 0, bass: 0, mid: 0, high: 0 };
  const alpha = 0.22;
  const transientDecay = 0.12;

  function number(value, fallback = 0) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
  }
  function clamp(value, min = 0, max = 1) {
    return Math.max(min, Math.min(max, number(value)));
  }
  function smooth(key, value, weight = alpha) {
    const next = previous[key] + (clamp(value) - previous[key]) * weight;
    previous[key] = next;
    return next;
  }
  function ingestFrequency(bytes, sampleRate = state.sampleRate, fftSize = bytes?.length * 2) {
    if (!bytes?.length) return snapshot();
    let total = 0;
    let weighted = 0;
    let bass = 0, mid = 0, high = 0;
    bytes.forEach((value, index) => {
      const level = number(value) / 255;
      const frequency = index * sampleRate / Math.max(1, fftSize);
      total += level;
      weighted += frequency * level;
      if (index < bytes.length * 0.10) bass += level;
      else if (index < bytes.length * 0.45) mid += level;
      else high += level;
    });
    const centroid = total ? weighted / total : 0;
    const nextBass = bass / Math.max(1, bytes.length * 0.10);
    const nextMid = mid / Math.max(1, bytes.length * 0.35);
    const nextHigh = high / Math.max(1, bytes.length * 0.55);
    state.bass = smooth("bass", nextBass);
    state.mid = smooth("mid", nextMid);
    state.high = smooth("high", nextHigh);
    state.centroid = number(centroid);
    state.onset = clamp(
      Math.max(0, state.bass - previous.rms) * 0.8 +
      Math.max(0, state.mid - previous.rms) * 0.4 +
      Math.max(0, state.high - previous.rms) * 0.2
    );
    previous.rms = (state.bass + state.mid + state.high) / 3;
    state.updatedAt = performance.now ? performance.now() : Date.now();
    state.version += 1;
    publish();
    return snapshot();
  }
  function ingestTimeDomain(bytes) {
    if (!bytes?.length) return snapshot();
    let sum = 0;
    let peak = 0;
    for (let i = 0; i < bytes.length; i += 1) {
      const sample = (number(bytes[i]) - 128) / 128;
      const abs = Math.abs(sample);
      sum += sample * sample;
      peak = Math.max(peak, abs);
    }
    state.rms = smooth("rms", Math.sqrt(sum / bytes.length));
    state.peak = Math.max(state.peak * (1 - transientDecay), peak);
    state.updatedAt = performance.now ? performance.now() : Date.now();
    state.version += 1;
    publish();
    return snapshot();
  }
  function ingestMicrophone({ rms, peak, speechActivity, sampleRate, channels, latencyMs } = {}) {
    state.rms = smooth("rms", clamp(rms));
    state.peak = Math.max(state.peak * (1 - transientDecay), clamp(peak));
    state.speechActivity = smooth("rms", clamp(speechActivity));
    if (sampleRate) state.sampleRate = number(sampleRate);
    if (channels) state.channels = number(channels);
    if (latencyMs != null) state.latencyMs = number(latencyMs);
    state.playback = "capture";
    state.updatedAt = performance.now ? performance.now() : Date.now();
    state.version += 1;
    publish();
    return snapshot();
  }
  function ingestPlayback({ playback = "playing", sentencePosition = 0, speaker = "master", playbackBufferMs, underruns } = {}) {
    state.playback = String(playback);
    state.sentencePosition = clamp(sentencePosition);
    state.speaker = String(speaker || "unknown");
    if (playbackBufferMs != null) state.playbackBufferMs = number(playbackBufferMs);
    if (underruns != null) state.underruns = Math.max(0, number(underruns));
    state.updatedAt = performance.now ? performance.now() : Date.now();
    state.version += 1;
    publish();
    return snapshot();
  }
  function attachAnalyser(analyser) {
    if (!analyser) return () => {};
    const time = new Uint8Array(analyser.fftSize || 2048);
    const freq = new Uint8Array(analyser.frequencyBinCount || 1024);
    state.analyserWindow = analyser.fftSize || time.length;
    return () => {
      analyser.getByteTimeDomainData?.(time);
      analyser.getByteFrequencyData?.(freq);
      ingestTimeDomain(time);
      ingestFrequency(freq, analyser.context?.sampleRate || 44100, analyser.fftSize || freq.length * 2);
    };
  }
  function publish() {
    state.speechActivity = clamp(state.speechActivity);
    window.MasterInteraction?.setAudio?.({ ...state });
    window.dispatchEvent(new CustomEvent("audio:update", { detail: snapshot() }));
  }
  function snapshot() {
    return Object.freeze({ ...state });
  }

  // Developer-only lab. It creates no production chrome unless explicitly enabled.
  function enableLab() {
    if (!new URLSearchParams(location.search).has("audio_lab")) return false;
    if (document.getElementById("master-audio-lab")) return true;
    const panel = document.createElement("output");
    panel.id = "master-audio-lab";
    panel.className = "master-audio-lab";
    panel.setAttribute("aria-live", "off");
    panel.textContent = "audio idle";
    document.body.appendChild(panel);
    const render = () => {
      if (!panel.isConnected) return;
      const s = snapshot();
      panel.textContent = [
        "rms " + s.rms.toFixed(3), "peak " + s.peak.toFixed(3),
        "lo " + s.bass.toFixed(3), "mid " + s.mid.toFixed(3), "hi " + s.high.toFixed(3),
        "cent " + Math.round(s.centroid), "speech " + s.speechActivity.toFixed(2),
        "sr " + s.sampleRate, "ch " + s.channels, "xruns " + s.underruns
      ].join(" · ");
      requestAnimationFrame(render);
    };
    requestAnimationFrame(render);
    return true;
  }

  window.MASTER_AUDIO_FIELD = Object.freeze({
    snapshot, attachAnalyser, ingestFrequency, ingestTimeDomain, ingestMicrophone, ingestPlayback, enableLab
  });
  window.MasterAudioField = window.MASTER_AUDIO_FIELD;

  window.addEventListener("tts:playback:start", (event) => {
    const d = event.detail || {};
    ingestPlayback({ playback: "playing", sentencePosition: 0, speaker: "master" });
    window.MasterInteraction?.setInteraction?.("speaking", { source: "tts" });
  });
  window.addEventListener("tts:playback:end", (event) => {
    const d = event.detail || {};
    ingestPlayback({ playback: "closed", sentencePosition: 1, speaker: d.interrupted ? "master-interrupted" : "master" });
    window.MasterInteraction?.setInteraction?.("idle", { source: "tts" });
  });
  enableLab();
})();
