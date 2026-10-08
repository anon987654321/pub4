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
// One interval on tts.visemeTimer, cursored over the audio frames: a second call
// replaces the first rather than stacking on it. Before playback begins the
// cursor simply holds at frame 0.

function fallbackVisemeShape(text, index) {
  const source = String(text || '').toLowerCase();
  const pair = source.slice(index, index + 2);
  if (/^(sh|ch|th|zh)/.test(pair)) return 'E';
  const ch = source[index] || ' ';
  if ('aeiouy'.includes(ch)) return VOWEL_VISEME[ch === 'y' ? 'e' : ch];
  if ('mbpfvw'.includes(ch)) return 'M';
  if ('oouu'.includes(pair)) return 'O';
  if (' .,!?;:—-'.includes(ch)) return 'neutral';
  return 'E';
}

function fallbackVisemePlan(text, durationMs) {
  const source = String(text || '');
  if (!source) return [];
  const weights = [];
  let total = 0;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    const weight = /[.,!?;:—-]/.test(ch) ? 1.8 : (/\s/.test(ch) ? 0.24 : (/[aeiouy]/i.test(ch) ? 1.25 : 0.72));
    weights.push(weight);
    total += weight;
  }
  let cursor = 0;
  return weights.map((weight, i) => {
    const at = total > 0 ? (cursor / total) * durationMs : 0;
    cursor += weight;
    const shape = fallbackVisemeShape(source, i);
    const pause = /[.,!?;:—-]/.test(source[i]);
    return { at, shape, amp: pause ? 0.12 : (shape === 'neutral' ? 0.0 : 0.55 + (/[aeiouy]/i.test(source[i]) ? 0.3 : 0.12)) };
  });
}

function startVisemeAnim(text) {
  stopVisemeAnim();
  const frames = planFrames();
  if (frames) {
    let cursor = 0;
    tts.visemeTimer = setInterval(() => {
      if (!tts.playing && !tts.audio) { stopVisemeAnim(); return; }
      const audio = tts.audio;
      if (!audio || audio.paused) return;
      const elapsed = audio.currentTime * 1000;
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
  let fallbackPlan = null;
  tts.visemeTimer = setInterval(() => {
    const audio = tts.audio;
    const durationMs = audio && Number.isFinite(audio.duration) ? audio.duration * 1000 : Math.max(900, text.length * 42);
    if (!fallbackPlan || fallbackPlan.durationMs !== durationMs) {
      fallbackPlan = { durationMs, frames: fallbackVisemePlan(text, durationMs) };
    }
    const elapsed = audio && Number.isFinite(audio.currentTime) ? audio.currentTime * 1000 : 0;
    let current = fallbackPlan.frames[0] || { shape: 'neutral', amp: 0 };
    for (const frame of fallbackPlan.frames) {
      if (frame.at > elapsed) break;
      current = frame;
    }
    State.viseme = current.shape;
    State.visemeAmp = current.amp;
    emitTtsEvent('tts:viseme', { shape: current.shape, amp: current.amp });
    if (ttsLive) {
      const ratio = Math.min(0.999, elapsed / Math.max(1, durationMs));
      const wIdx = Math.min(words.length - 1, Math.floor(ratio * words.length));
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
  fallbackVisemePlan,
  setViseme,
  clearViseme,
  startVisemeAnim,
  stopVisemeAnim,
});
window.MASTER = window.MASTER || {};
window.MASTER.speechPlayback = window.MASTER_SPEECH_PLAYBACK;
