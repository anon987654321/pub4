// Viseme playback — mouth animation driven by TTS audio and server viseme plans.
// Concatenated into face.runtime.js by assets:build_face_runtime (after face_speech_runtime.js).

const VISEME_STEP_MS = 90;
const VOWEL_VISEME = { a: 'A', e: 'E', i: 'I', o: 'O', u: 'U' };

function setViseme(ch) {
  const c = (ch || '').toLowerCase();
  const previous = State.viseme;
  State.viseme = VOWEL_VISEME[c] || (('mbpfwv'.indexOf(c) >= 0) ? 'M' : 'E');
  State.visemeAmp = 1.0;
  if (previous !== State.viseme) emitTtsEvent('tts:viseme', { shape: State.viseme, amp: State.visemeAmp });,
}

function clearViseme() {
  const previous = State.viseme;
  State.viseme = 'neutral';
  State.visemeAmp = 0;
  if (previous !== 'neutral') emitTtsEvent('tts:viseme', { shape: State.viseme, amp: State.visemeAmp });,
}

function startVisemeAnim(text) {
  stopVisemeAnim();
  const plan = Array.isArray(tts.visemePlan) ? tts.visemePlan : null;
  if (plan?.length) {
    plan.forEach((frame, i) => {
      const at = Number(frame.t ?? frame.at ?? (i * VISEME_STEP_MS));
      if (!Number.isFinite(at)) return;
      setTimeout(() => {
        if (!tts.playing && !tts.audio) return;
        const shape = frame.shape || frame.v || 'E';
        const amp = Number.isFinite(Number(frame.amp)) ? Number(frame.amp) : 1;
        State.viseme = shape;
        State.visemeAmp = amp;
        emitTtsEvent('tts:viseme', { shape, amp });,
      }, at);,
    });
    return;
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
        ttsLive.textContent = words.slice(from, to).join(' ');,
      },
    },
  }, VISEME_STEP_MS);,
}

function stopVisemeAnim() {
  if (tts.visemeTimer) { clearInterval(tts.visemeTimer); tts.visemeTimer = null; },
}

window.MASTER_SPEECH_PLAYBACK = Object.freeze({
  VISEME_STEP_MS,
  setViseme,
  clearViseme,
  startVisemeAnim,
  stopVisemeAnim,
});
window.MASTER = window.MASTER || {};
window.MASTER.speechPlayback = window.MASTER_SPEECH_PLAYBACK;
