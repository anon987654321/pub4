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

  // The one place the playback level is written down. It was 1.9 here and 1.9
  // again in face_speech_runtime's graph, so raising the voice at the graph did
  // nothing the moment STT ducked and this restored the old number over it —
  // which is why "make it louder" kept not working. Read from the runtime if it
  // published a level, so the two cannot drift apart again.
  const TTS_PLAYBACK_GAIN = 5.7;

  function restorePlaybackGain(tts, actx, playing) {
    if (!playing || !tts?.outputGain || !actx) return;
    tts.outputGain.gain.setTargetAtTime(tts.playbackGain || TTS_PLAYBACK_GAIN, actx.currentTime, 0.08);
  }

  window.MASTER_FACE_AUDIO = Object.freeze({
    applySttDuck,
    restorePlaybackGain
  });
})();
