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

  // Fallback only. The live level is tts.playbackGain, published by the
  // speech runtime (19.0 — ten times the 1.9 this used to hardcode). A second
  // copy here is why every previous attempt to raise the voice was undone the
  // first time speech recognition ducked it. Keep this number equal to the
  // runtime's published value so a missed publish still restores the new level.
  const TTS_PLAYBACK_GAIN = 19.0;

  function restorePlaybackGain(tts, actx, playing) {
    if (!playing || !tts?.outputGain || !actx) return;
    tts.outputGain.gain.setTargetAtTime(tts.playbackGain || TTS_PLAYBACK_GAIN, actx.currentTime, 0.08);
  }

  window.MASTER_FACE_AUDIO = Object.freeze({
    applySttDuck,
    restorePlaybackGain
  });
})();
