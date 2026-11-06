// Browser-side TTS polish that stays outside the speech engine.
// One voice, one queue, one synthesis path; this only tunes the playback surface.
(() => {
  "use strict";

  const PITCH_KEYS = ["preservesPitch", "webkitPreservesPitch", "mozPreservesPitch"];

  function tuneAudio(audio) {
    if (!audio) return;
    for (const key of PITCH_KEYS) {
      if (key in audio) {
        try { audio[key] = true; } catch (_) {}
      }
    }
    try { audio.preload = "auto"; } catch (_) {}
  }

  function sync() {
    const audio = window.MASTER_SPEECH_RUNTIME?.tts?.audio;
    if (!audio) return;
    tuneAudio(audio);
    document.documentElement.dataset.ttsNaturalPitch = "1";
  }

  window.addEventListener("tts:playback:start", sync, { passive: true });
  window.addEventListener("tts:viseme:plan", sync, { passive: true });

  window.MASTER_TTS_POLISH = Object.freeze({ tuneAudio, sync });
})();
