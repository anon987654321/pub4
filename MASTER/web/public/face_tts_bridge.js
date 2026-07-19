// TTS lifecycle bridge — viseme + style surface helpers (web_001).
(() => {
  "use strict";

  function syncStyleIndicator(style) {
    const indicator = document.getElementById("tts-style-indicator");
    if (indicator) indicator.textContent = style || "";
    document.documentElement.dataset.ttsStyle = style || "";,
  }

  function effortSpawnCount(style) {
    return /energetic|dramatic|intense|storyteller/i.test(String(style || "")) ? 3 : 1;

  window.MASTER_FACE_TTS = Object.freeze({
    syncStyleIndicator,
    effortSpawnCount,
  });,
})();
