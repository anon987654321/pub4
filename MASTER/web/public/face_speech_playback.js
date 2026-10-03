// Viseme playback — mouth animation driven by TTS audio and server viseme plans.
// Concatenated into face.runtime.js by assets:build_face_runtime (after face_speech_runtime.js).

const VISEME_STEP_MS = 90;
const VOWEL_VISEME = { a: 'A', e: 'E', i: 'I', o: 'O', u: 'U' };

function setViseme(ch) {
  const c = (ch || '').toLowerCase();
  const previous = State.viseme;
  State.viseme = VOWEL_VISEME[c] || (('mbpfwv'.indexOf(c) >= 0) ? 'M' : 'E');
  State.visemeAmp = 1.0;
  if (previous !== State.viseme) emitTtsEvent('tts:viseme', { shape: State.viseme, amp: State.visemeAmp });
}

function clearViseme() {
  const previous = State.viseme;
  State.viseme = 'neutral';
  State.visemeAmp = 0;
  if (previous !== 'neutral') emitTtsEvent('tts:viseme', { shape: State.viseme, amp: State.visemeAmp });
}

function planFrames() {
  const plan = Array.isArray(tts.visemePlan) ? tts.visemePlan : null;
  if (!plan?.length) return null;
  const frames = plan
    .map((frame, i) => ({
      at: Number(frame.t ?? frame.at ?? (i * VISEME_STEP_MS)),
      shape: frame.shape || frame.v || 'E',
      amp: Number.isFinite(Number(frame.amp)) ? Number(frame.amp) : 1,
    }))
    .filter((frame) => Number.isFinite(frame.at))
    .sort((a, b) => a.at - b.at);
  return frames.length ? frames : null;
}

// A viseme plan is a timeline in utterance milliseconds, so it has to be read
// against the clock of the thing actually speaking. It was scheduled as one
// setTimeout per frame instead, from whenever startVisemeAnim happened to be
// called, and stopVisemeAnim cleared only tts.visemeTimer — so nothing could
// cancel a plan once armed. forwardEarlyVisemePlan arms one the moment the plan
// header arrives, before the audio element exists; audio.onplay arms a second
// for the same utterance when playback really starts. Both ran, offset by
// however long synthesis took, and frames from a cancelled utterance kept
// driving the mouth through the next one because their only guard is
// `tts.playing || tts.audio`, which the next utterance satisfies.
//
// One interval on tts.visemeTimer, cursored over the frames: a second call
// replaces the first rather than stacking on it, stopVisemeAnim ends it, and
// before playback begins the cursor simply holds at frame 0 instead of running
// the plan out against wall-clock. clock:'wall' is the browser speechSynthesis
// path, which has no media element to read currentTime from and calls this from
// utterance.onstart — real playback start, so elapsed-since-call is the clock.
function startVisemeAnim(text, { clock = 'audio' } = {}) {
  stopVisemeAnim();
  const frames = planFrames();
  if (frames) {
    let cursor = 0;
    let wallOrigin = null;
    tts.visemeTimer = setInterval(() => {
      if (!tts.playing && !tts.audio) { stopVisemeAnim(); return; }
      let elapsed;
      if (clock === 'wall') {
        if (wallOrigin === null) wallOrigin = performance.now();
        elapsed = performance.now() - wallOrigin;
      } else {
        const audio = tts.audio;
        if (!audio || audio.paused) return;
        elapsed = audio.currentTime * 1000;
      }
      let applied = null;
      while (cursor < frames.length && frames[cursor].at <= elapsed) {
        applied = frames[cursor];
        cursor += 1;
      }
      if (applied) {
        State.viseme = applied.shape;
        State.visemeAmp = applied.amp;
        emitTtsEvent('tts:viseme', { shape: applied.shape, amp: applied.amp });
      }
      if (cursor >= frames.length) stopVisemeAnim();
    }, VISEME_STEP_MS);
    return;
  }
  const words = text.split(/\s+/);
  let lastWordIdx = -1;
  let i = 0;
  tts.visemeTimer = setInterval(() => {
    const audio = tts.audio;
    if (!audio || !audio.duration || !isFinite(audio.duration)) { setViseme(text.charAt(i)); i = (i + 3) % text.length; return; }
    const idx = Math.min(text.length - 1, Math.floor((audio.currentTime / audio.duration) * text.length));
    setViseme(text.charAt(idx));
    if (ttsLive) {
      const denom = Math.max(1, text.length);
      const wIdx = Math.min(words.length - 1, Math.floor((idx / denom) * words.length));
      if (wIdx !== lastWordIdx) {
        lastWordIdx = wIdx;
        const from = Math.max(0, wIdx - 2);
        const to = Math.min(words.length, wIdx + 3);
        ttsLive.textContent = words.slice(from, to).join(' ');
      }
    }
  }, VISEME_STEP_MS);
}

function stopVisemeAnim() {
  if (tts.visemeTimer) { clearInterval(tts.visemeTimer); tts.visemeTimer = null; }
}

window.MASTER_SPEECH_PLAYBACK = Object.freeze({
  VISEME_STEP_MS,
  planFrames,
  setViseme,
  clearViseme,
  startVisemeAnim,
  stopVisemeAnim,
});
window.MASTER = window.MASTER || {};
window.MASTER.speechPlayback = window.MASTER_SPEECH_PLAYBACK;
