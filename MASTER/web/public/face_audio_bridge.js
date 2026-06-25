// TTS/STT audio ducking helpers — face audio module (web_001).
(() => {
  "use strict";

  function applySttDuck(State, tts, actx) {
    if (!State.sttActive || State.sttDuck <= 0.02) return false;
    State.sttDuck = Math.max(0, State.sttDuck - 0.06);
    const duckTarget = 0.12 + State.sttDuck * 0.18;
    if (tts?.outputGain && actx) {
      tts.outputGain.gain.setTargetAtTime(duckTarget, actx.currentTime, 0.04);
    } else if (tts?.audio) {
      tts.audio.volume = Math.min(tts.audio.volume, duckTarget);
    }
    return true;
  }

  function restorePlaybackGain(tts, actx, playing) {
    if (!playing || !tts?.outputGain || !actx) return;
    tts.outputGain.gain.setTargetAtTime(1.9, actx.currentTime, 0.08);
  }

  window.MASTER_FACE_AUDIO = Object.freeze({
    applySttDuck,
    restorePlaybackGain
  });
})();