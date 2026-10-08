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

  // Fallback only, and unity because the level belongs to the voice chain the
  // speech runtime builds, not to a number kept in step here. The copy that
  // used to sit at this line held 1.9, and a second copy of a level is why
  // every previous attempt to raise the voice was undone the first time
  // speech recognition ducked it. tts.playbackGain is the live value; this is
  // reached only when the graph exists without one.
  const TTS_PLAYBACK_GAIN = 1;

  // Both branches of applySttDuck need an undo, and only the WebAudio one had
  // it: this returned early unless outputGain and actx were both present, so on
  // the element path — AudioContext suspended, not yet created, or speech
  // starting before connectTTSAudio runs — ducking set tts.audio.volume to
  // 0.12 and nothing ever put it back. Math.min meant it could only fall, so
  // one pass of speech recognition left the voice at 12% for the life of that
  // element, which is inaudible on a laptop speaker rather than merely quiet.
  //
  // The element path restores to 1, not TTS_PLAYBACK_GAIN: HTMLMediaElement
  // .volume is a 0..1 scalar and anything above 1 throws IndexSizeError. The
  // gain figure belongs to the graph, which is the other branch.
  function restorePlaybackGain(tts, actx, playing) {
    if (!playing) return;
    if (tts?.outputGain && actx) {
      tts.outputGain.gain.setTargetAtTime(tts.playbackGain || TTS_PLAYBACK_GAIN, actx.currentTime, 0.08);
    } else if (tts?.audio) {
      tts.audio.volume = 1;
    }
  }

  window.MASTER_FACE_AUDIO = Object.freeze({
    applySttDuck,
    restorePlaybackGain
  });
})();
