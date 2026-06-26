// TTS lifecycle bridge — viseme smoothing, UI sync, mouth-particle coupling (web_001).
(() => {
  "use strict";

  const VISEME_LERP = 0.22;
  const WAVE_DECAY = 0.88;
  let visemeTarget = { shape: "neutral", amp: 0 };
  let visemeSmooth = { shape: "neutral", amp: 0 };
  let visemeRaf = 0;
  let queueDepth = 0;

  function syncStyleIndicator(style) {
    const indicator = document.getElementById("tts-style-indicator");
    if (indicator) indicator.textContent = style || "";
    document.documentElement.dataset.ttsStyle = style || "";
  }

  function effortSpawnCount(style) {
    return /energetic|dramatic|intense|storyteller/i.test(String(style || "")) ? 3 : 1;
  }

  function faceState() {
    return window.MASTER_FACE?.State || window.State || {};
  }

  function applySmoothViseme() {
    const st = faceState();
    const ampDelta = visemeTarget.amp - visemeSmooth.amp;
    visemeSmooth.amp += ampDelta * VISEME_LERP;
    if (Math.abs(ampDelta) < 0.004) visemeSmooth.amp = visemeTarget.amp;
    if (visemeTarget.shape !== visemeSmooth.shape && visemeSmooth.amp < 0.08) {
      visemeSmooth.shape = visemeTarget.shape;
    }
    st.viseme = visemeSmooth.shape;
    st.visemeAmp = visemeSmooth.amp;
    visemeRaf = requestAnimationFrame(applySmoothViseme);
  }

  function setVisemeTarget(shape, amp) {
    visemeTarget = { shape: shape || "neutral", amp: Number.isFinite(amp) ? amp : 0 };
    if (!visemeRaf) visemeRaf = requestAnimationFrame(applySmoothViseme);
  }

  function stopVisemeSmooth() {
    if (visemeRaf) cancelAnimationFrame(visemeRaf);
    visemeRaf = 0;
    visemeTarget = { shape: "neutral", amp: 0 };
    visemeSmooth = { shape: "neutral", amp: 0 };
  }

  function syncQueueBadge() {
    const ui = document.querySelector(".ui-status");
    const tts = window.MASTER_FACE?.tts;
    if (!ui || !tts) return;
    const depth = (tts.queue?.length || 0) + (tts.lanes?.error?.length || 0)
      + (tts.lanes?.nudge?.length || 0) + (tts.lanes?.response?.length || 0);
    if (depth === queueDepth) return;
    queueDepth = depth;
    if (depth > 1 && tts.playing) ui.dataset.ttsQueue = String(depth);
    else delete ui.dataset.ttsQueue;
  }

  function decayWaveBars() {
    const wave = document.getElementById("zsh-wave");
    if (!wave) return;
    wave.querySelectorAll("span").forEach((bar) => {
      const h = parseFloat(bar.style.height || "4") || 4;
      bar.style.height = `${Math.max(3, h * WAVE_DECAY)}px`;
      const op = parseFloat(bar.style.opacity || "0.25") || 0.25;
      bar.style.opacity = String(Math.max(0.12, op * WAVE_DECAY));
    });
  }

  function onViseme(ev) {
    const { shape, amp } = ev.detail || {};
    setVisemeTarget(shape, amp);
    const pool = window.mouthPool || window.MASTER_FACE?.mouthPool;
    window.MASTER_FACE_PARTICLES?.burstViseme?.(pool, shape, amp);
  }

  function onPlaybackStart(ev) {
    const detail = ev.detail || {};
    document.body.dataset.ttsWave = "1";
    syncStyleIndicator(detail.style || document.documentElement.dataset.ttsStyle);
    const count = effortSpawnCount(detail.style);
    const pool = window.mouthPool || window.MASTER_FACE?.mouthPool;
    window.MASTER_FACE_PARTICLES?.anticipateSpeech?.(pool, count);
    syncQueueBadge();
  }

  function onPlaybackEnd() {
    document.body.dataset.ttsWave = "";
    stopVisemeSmooth();
    const st = faceState();
    st.viseme = "neutral";
    st.visemeAmp = 0;
    decayWaveBars();
    syncQueueBadge();
  }

  function onAnticipate(ev) {
    syncStyleIndicator(ev.detail?.style);
    syncQueueBadge();
  }

  ["tts:viseme", "master:tts:viseme"].forEach((name) => {
    window.addEventListener(name, onViseme);
  });
  ["tts:playback:start", "master:tts:playback:start"].forEach((name) => {
    window.addEventListener(name, onPlaybackStart);
  });
  ["tts:playback:end", "master:tts:playback:end"].forEach((name) => {
    window.addEventListener(name, onPlaybackEnd);
  });
  ["tts:anticipate", "master:tts:anticipate"].forEach((name) => {
    window.addEventListener(name, onAnticipate);
  });
  window.addEventListener("tts:style:active", (ev) => syncStyleIndicator(ev.detail?.style));

  window.MASTER_FACE_TTS = Object.freeze({
    syncStyleIndicator,
    effortSpawnCount,
    setVisemeTarget,
    stopVisemeSmooth,
    syncQueueBadge
  });
})();