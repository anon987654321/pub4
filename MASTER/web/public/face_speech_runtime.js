// Speech / TTS runtime — concatenated into face.runtime.js by assets:build_face_runtime.
// This file is where the TTS implementation lives; it used to live in
// face.part4.txt, which was left behind as a 96-byte stub the build task never
// read. That stub is gone — the rake task's segment list is the only place that
// decides what goes into face.runtime.js.
let actx = null;
let ambientHumGain = null;
function initAudio() {
  if (actx) {
    if (actx.state === 'suspended') actx.resume().catch(() => {});
    return;
  }
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    actx = window.__MASTER_AUDIO_PRIME__ || (Ctx ? new Ctx() : null);
    window.__MASTER_AUDIO_PRIME__ = null;
    if (!actx) return;
    if (actx.state === 'suspended') actx.resume().catch(() => {});
    const silentGain = actx.createGain();
    silentGain.gain.value = 0;
    const silentOsc = actx.createOscillator();
    silentOsc.frequency.value = 0;
    silentOsc.connect(silentGain);
    silentGain.connect(actx.destination);
    silentOsc.start();
    // FA51 ambient thinking hum — 40Hz sine at 3% volume, ducked during TTS
    ambientHumGain = actx.createGain();
    ambientHumGain.gain.value = 0;
    const humOsc = actx.createOscillator();
    humOsc.type = 'sine'; humOsc.frequency.value = 40;
    humOsc.connect(ambientHumGain);
    ambientHumGain.connect(actx.destination);
    humOsc.start();
  } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:init_audio", err); }
}
function setAmbientHum(active) {
  if (!ambientHumGain || !actx) return;
  const target = active ? 0.03 : 0;
  ambientHumGain.gain.setTargetAtTime(target, actx.currentTime, 0.5);
}

function beep(freq, dur) {
  if (!actx) return;
  const o = actx.createOscillator(), g = actx.createGain();
  o.type = 'square'; o.frequency.value = freq;
  g.gain.setValueAtTime(0.08, actx.currentTime);
  g.gain.exponentialRampToValueAtTime(0.001, actx.currentTime + dur);
  o.connect(g); g.connect(actx.destination);
  o.start(); o.stop(actx.currentTime + dur);
}

const LOW_POWER = (/SMART[-_ ]?TV|SmartTV|Tizen|Web0?S|HbbTV|VIDAA|NetCast|BRAVIA|Sharp|TCL|Hisense|Vizio|Roku|AppleTV|HiSilicon|MTK|AMLogic/i.test(navigator.userAgent) || (typeof navigator.hardwareConcurrency === "number" && navigator.hardwareConcurrency > 0 && navigator.hardwareConcurrency < 4));
const tts = { lanes: { error: [], nudge: [], response: [] }, queue: [], prefetch: new Map(), attempts: new Map(), meta: new Map(), retryTimer: null, muted: false, playing: false, paused: false, loading: false, cancelToken: 0, current: null, audio: null, visemeTimer: null, serverUnavailable: false, serverUnavailableUntil: 0, serverFailureCount: 0, synthInFlight: 0, analyser: null, analyserBuf: null, analyserFreqBuf: null, pitchOffset: 0, lang: 'en', resumeTime: null, resumeWordIndex: null };
const TTS_DB_NAME = 'master-tts-v1';
const TTS_STORE = 'blobs';
// Fallback matches data/voice.yml, and has to: a failure to load
// MASTER_VOICE_POLICY otherwise switches the voice, its accent and its language
// with nothing said. This literal has been wrong in both directions — Pernille
// here while the policy said Osman, then Osman here while the policy said
// Pernille — which is the two-halves bug voice.yml's own header documents.
const TTS_DEFAULT_VOICE = window.MASTER_VOICE_POLICY?.neural || 'ms-MY-OsmanNeural';
const TTS_STREAM_LIVE_KEY = 'master:tts-stream-live';
function ttsStreamLiveEnabled() {
  try {
    if (localStorage.getItem(TTS_STREAM_LIVE_KEY) === '1') return true;
    if (localStorage.getItem(TTS_STREAM_LIVE_KEY) === '0') return false;
  } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:stream_live_read", err); }
  return !!window.MASTER_VOICE_POLICY?.stream_live_default;
}
function setTtsStreamLive(on) {
  try { localStorage.setItem(TTS_STREAM_LIVE_KEY, on ? '1' : '0'); } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:stream_live_store", err); }
  if (uiStatus) uiStatus.textContent = `tts stream ${on ? 'on' : 'off'}`;
}
function setTtsHealthStatus(msg, ttlMs = 8000) {
  const el = ttsLive || document.getElementById('tts-live');
  if (!el) return;
  if (!msg) {
    delete el.dataset.health;
    if (!tts.loading && !tts.playing) el.textContent = '';
    return;
  }
  el.textContent = msg;
  el.dataset.health = '1';
  clearTimeout(setTtsHealthStatus._timer);
  setTtsHealthStatus._timer = setTimeout(() => {
    if (el.dataset.health === '1') setTtsHealthStatus('');
  }, ttlMs);
}
function emitTtsEvent(type, detail = {}) {
  const payload = { ...detail, type };
  window.dispatchEvent(new CustomEvent(type, { detail: payload }));
  if (window.MASTEREvents?.normalize && window.MASTEREvents?.dispatch) {
    window.MASTEREvents.dispatch(window.MASTEREvents.normalize(payload));
    return;
  }
  window.MASTERVisual?.event?.(type, {
    topology: 'papua-mask',
    entropy: detail.entropy ?? 0.18,
    confidence: detail.confidence ?? 0.86,
    mode: detail.mode || type,
    raw: payload
  });
}
function _activeTtsVoice() {
  return TTS_DEFAULT_VOICE;
}
function _nextTtsVoice() { return _activeTtsVoice(); }
const TTS_STYLE_KEY = 'master:tts_style';
const TTS_STYLE_DEFAULT = 'auto';
function _readStoredTtsStyle() {
  try { return localStorage.getItem(TTS_STYLE_KEY) || TTS_STYLE_DEFAULT; } catch (_) { return TTS_STYLE_DEFAULT; }
}
window.MASTER_TTS_STYLE = _readStoredTtsStyle();
State.ttsStyleLocked = window.MASTER_TTS_STYLE !== 'auto';
function _ttsStyleDecayRate(style) {
  const s = String(style || '').toLowerCase();
  if (/dramatic|storyteller|intense/.test(s)) return 0.92;
  if (/whispered|intimate|calm|ethereal/.test(s)) return 0.58;
  if (/energetic/.test(s)) return 0.75;
  return 0.82;
}
function _nextTtsStyle(_voice) {
  const locked = String(window.MASTER_TTS_STYLE || '').trim();
  if (locked && locked !== 'auto') return locked;
  const persona = window.MASTER_PERSONA || {};
  const style = String(persona.style || 'auto').trim();
  return style && style !== 'auto' ? style : TTS_STYLE_DEFAULT;
}
function syncTtsStyleUi() {
  const style = _nextTtsStyle();
  document.querySelectorAll('.style-chip').forEach((chip) => {
    chip.classList.toggle('active', chip.dataset.style === style);
  });
  const indicator = document.getElementById('tts-style-indicator');
  if (indicator) indicator.textContent = style;
}
function setTtsStyle(style, opts = {}) {
  const next = String(style || '').trim().toLowerCase() || TTS_STYLE_DEFAULT;
  window.MASTER_TTS_STYLE = next;
  State.ttsStyleLocked = opts.lockStyle === false ? false : next !== 'auto';
  try { localStorage.setItem(TTS_STYLE_KEY, next); } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:style_store", err); }
  syncTtsStyleUi();
  if (!opts.silent) {
    emitTtsEvent('tts:style:active', { style: next });
    window.MASTERVisual?.event?.('tts:style:active', { topology: 'papua-mask', entropy: 0.22, confidence: 0.86, mode: next, style: next });
  }
}
syncTtsStyleUi();
function preSpeechInhale(style) {
  const s = style || _nextTtsStyle();
  emitTtsEvent('tts:anticipate', { style: s, expression: { arousal: 0.35, attention: 0.2 } });
  const K = window.ParticleKernel;
  if (mouthPool && K) {
    for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      mouthPool.cells[b + K.FIELD.arousal] = Math.min(1, (mouthPool.cells[b + K.FIELD.arousal] || 0.5) + 0.28);
    }
  }
  if (eyePool && K) {
    for (let i = 0; i < eyePool.count; i++) if (eyePool.alive[i]) {
      const b = i * K.FIELDS_PER_CELL;
      eyePool.cells[b + K.FIELD.attention] = Math.min(1, (eyePool.cells[b + K.FIELD.attention] || 0.5) + 0.15);
    }
  }
}
function _applyLocalPostSpeechDecay(decayRate) {
  const rate = Number.isFinite(Number(decayRate)) ? Number(decayRate) : 0.82;
  const K = window.ParticleKernel;
  if (!mouthPool || !K) return;
  for (let i = 0; i < mouthPool.count; i++) if (mouthPool.alive[i]) {
    const b = i * K.FIELDS_PER_CELL;
    mouthPool.cells[b + K.FIELD.arousal] = Math.max(0.12, (mouthPool.cells[b + K.FIELD.arousal] || 0.5) * rate);
    mouthPool.cells[b + K.FIELD.pressure] = Math.max(0.08, (mouthPool.cells[b + K.FIELD.pressure] || 0) * rate);
  }
  State.pulse = Math.max(0, (State.pulse || 0) * rate);
}
function _parseTtsVisemeHeader(res) {
  const raw = res?.headers?.get?.('X-TTS-Visemes');
  if (!raw) return null;
  try {
    let plan;
    if (/^[A-Za-z0-9+/=]+$/.test(raw) && raw.length > 80) {
      plan = JSON.parse(atob(raw));
    } else {
      plan = JSON.parse(raw);
    }
    return Array.isArray(plan) ? plan : (plan.frames || plan.visemes || plan.viseme_plan || plan.viseme_hints || null);
  } catch (_) {
    return null;
  }
}
function _parseTtsMetaHeader(res) {
  const raw = res?.headers?.get?.('X-TTS-Meta');
  if (!raw) return null;
  try {
    const text = (/^[A-Za-z0-9+/=]+$/.test(raw) && raw.length > 80) ? atob(raw) : raw;
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}
const EMOTION_HISTORY_KEY = 'master:emotion_history';
const EMOTION_HISTORY_CAP = 50;
function pushEmotionHistory(entry) {
  let ring = [];
  try { ring = JSON.parse(localStorage.getItem(EMOTION_HISTORY_KEY) || '[]'); } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:emotion_history_read", err); }
  if (!Array.isArray(ring)) ring = [];
  ring.push({ ts: Date.now(), ...entry });
  while (ring.length > EMOTION_HISTORY_CAP) ring.shift();
  try { localStorage.setItem(EMOTION_HISTORY_KEY, JSON.stringify(ring)); } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:emotion_history_store", err); }
  const bar = document.getElementById('mood-sparkline');
  if (!bar) return;
  bar.innerHTML = ring.slice(-20).map((e) => {
    const h = Math.max(3, Math.round((e.entropy ?? 0.2) * 18));
    return `<i data-mood="${e.mood || e.mode || 'idle'}" style="height:${h}px"></i>`;
  }).join('');
  window.MASTEREmotionHistory = ring;
}
window.addEventListener('master:visual', (ev) => {
  const d = ev.detail || {};
  pushEmotionHistory({
    mood: State.mood,
    mode: d.mode || d.name || State.mode,
    entropy: d.entropy ?? State.entropy ?? 0.2,
    valence: d.expression?.valence ?? 0,
    arousal: d.expression?.arousal ?? 0
  });
});
async function prefetchTtsPhraseBank() {
  if (!window.MASTER_RUNTIME?.enhancements?.includes?.('tts_phrase_bank')) return;
  try {
    const res = await fetch('/chat/tts/phrases');
    if (!res.ok) return;
    const data = await res.json();
    const phrases = Array.isArray(data.phrases) ? data.phrases : [];
    phrases.slice(0, 6).forEach((row) => {
      const voice = guardVoice(row.voice) || _nextTtsVoice();
      const style = row.style || _nextTtsStyle(voice);
      fetchTTS(row.text, voice, style);
    });
  } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:prefetch_phrase_bank", err); }
}
function _quirkifyTts(text, voice, opts = {}) {
  if (!opts.quirky) return text;
  if (text.length < 12) return text;
  const r = Math.random;
  if (voice === 'ezinne' && r() < 0.55) {
    const dim = ['uh... ', 'duh, ', 'hmm... me think... ', 'brain hurt. ', 'oh! oh! ', 'okay um... ', 'wait... what? ', 'ohhh, ', 'me confuse. ', 'numbers? me no like numbers. '];
    text = dim[(r() * dim.length) | 0] + text;
  }
  if (voice === 'ezinne' && r() < 0.4) {
    text = text.replace(/\b(the|a|of|and|is|are|was|were)\b/gi, '').replace(/\s+/g, ' ').trim() + '. ugh.';
  }
  if (r() < 0.06) {
    const mid = Math.max(20, Math.floor(text.length * 0.55));
    const cut = text.indexOf(' ', mid);
    if (cut > 0 && cut < text.length - 8) {
      const fillers = ['... uh, wait — where was I? oh, right. ', '... hmm, lost my train of thought. ', '... um, sorry — anyway. '];
      text = text.slice(0, cut) + fillers[(r() * fillers.length) | 0] + text.slice(cut + 1);
    }
  }
  if (r() < 0.08) {
    const m = text.match(/^(\w)(\w*)(.*)/s);
    if (m && /[a-zA-Z]/.test(m[1])) text = `${m[1]}-${m[1]}-${m[1]}${m[2]}${m[3]}`;
  }
  if (r() < 0.05) {
    const laughs = ['ha ha. ', 'heh, ', 'ha. okay, ', 'pff, '];
    text = laughs[(r() * laughs.length) | 0] + text;
  }
  if (r() < 0.04) {
    text = `... ${text}. sorry.`;
  }
  if (r() < 0.05) {
    const mid = Math.floor(text.length * 0.4);
    const cut = text.indexOf(' ', mid);
    if (cut > 0) text = text.slice(0, cut) + ' — *cough* — ' + text.slice(cut + 1);
  }
  if (r() < 0.04) {
    const words = text.split(' ');
    for (let i = 0; i < words.length; i++) if (r() < 0.35 && words[i].length > 3) words[i] = words[i].split('').join("'");
    text = words.join(' ') + " — sorry, mouth full.";
  }
  if (r() < 0.03) {
    text = "wait — wait. okay. okay. *breathe* — " + text.replace(/\./g, "...") + " — sorry, panicking.";
  }
  if (r() < 0.18) {
    const fillers = ['uh, ', 'hmm, ', 'so, ', 'well, ', 'like, ', 'i mean, ', 'okay so, '];
    text = fillers[(r() * fillers.length) | 0] + text;
  }
  return text;
}
const TTS_FETCH_TIMEOUT_MS = 45000;
const TTS_SYNTH_MAX = 2;
const TTS_PREFETCH_MAX = 2;
let ttsDBPromise = null;
let ttsPrefetchInFlight = 0;

function setTTSLoading(loading) {
  tts.loading = !!loading;
  rootBody.dataset.ttsLoading = tts.loading ? 'true' : 'false';
}

function parsePersonaRate(rate) {
  const text = String(rate || "").trim();
  if (!text) return null;
  if (/%$/.test(text)) {
    const pct = parseFloat(text);
    return Number.isFinite(pct) ? Math.max(0.5, Math.min(2.0, 1 + (pct / 100))) : null;
  }
  const value = parseFloat(text);
  return Number.isFinite(value) && value > 0 ? Math.max(0.5, Math.min(2.0, value)) : null;
}

function parsePersonaPitch(pitch) {
  const text = String(pitch || "").trim();
  if (!text) return null;
  const value = parseFloat(text);
  return Number.isFinite(value) ? value : null;
}

function applyPersonaAudioDefaults() {
  const persona = window.MASTER_PERSONA || {};
  const rate = parsePersonaRate(persona.tts_rate);
  if (rate) setTtsRate(rate);
  const pitch = parsePersonaPitch(persona.tts_pitch);
  if (pitch != null) tts.pitchOffset = pitch;
  if (State.voiceName) setVoiceName(State.voiceName, { speakBlurb: false });
  else if (persona.voice) setVoiceName(persona.voice, { speakBlurb: false });
  syncShareStateUrl();
}
applyPersonaAudioDefaults();
prefetchTtsPhraseBank();

function announceTTS(text) {
  if (!ttsLive) return;
  ttsLive.textContent = text.toString().slice(0, 500);
}

function ttsURL(text, voice, style) {
  const qs = new URLSearchParams({ text });
  // Tell the server which lane this is. Its synthesis queue ranks by the same
  // order this file ranks playback by, so an idle nudge can no longer be
  // synthesized ahead of the reply someone is waiting on. Absent means
  // "response" server-side, which is the safe default — an unlabelled job never
  // loses its place to a nudge.
  const lane = tts.meta.get(text)?.lane;
  if (lane) qs.set('lane', lane);
  const persona = window.MASTER_PERSONA || {};
  const resolvedStyle = style || _nextTtsStyle(voice);
  if (voice) qs.set('voice', voice);
  if (State.ttsStyleLocked && resolvedStyle && resolvedStyle !== 'auto') {
    qs.set('style', resolvedStyle);
    qs.set('style_locked', '1');
  }
  if (State.voiceLocked) qs.set('voice_locked', '1');
  if (persona.tts_rate) qs.set('rate', String(persona.tts_rate));
  if (persona.tts_pitch) qs.set('pitch', String(persona.tts_pitch));
  return `/chat/tts?${qs.toString()}`;
}

async function ttsCacheKey(text, voice, style) {
  if (!window.crypto || !crypto.subtle || !window.TextEncoder) return null;
  const persona = window.MASTER_PERSONA || {};
  const material = `${voice || TTS_DEFAULT_VOICE}|${style || 'auto'}|${persona.tts_rate || ''}|${persona.tts_pitch || ''}|${text}`;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(material));
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('');
}

function openTTSDB() {
  if (!window.indexedDB) return Promise.resolve(null);
  if (ttsDBPromise) return ttsDBPromise;
  ttsDBPromise = new Promise((resolve) => {
    const req = indexedDB.open(TTS_DB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(TTS_STORE)) db.createObjectStore(TTS_STORE);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => resolve(null);
    req.onblocked = () => resolve(null);
  });
  return ttsDBPromise;
}

async function readCachedTTS(key) {
  const db = await openTTSDB();
  if (!db || !key) return null;
  return new Promise((resolve) => {
    const tx = db.transaction(TTS_STORE, 'readonly');
    const req = tx.objectStore(TTS_STORE).get(key);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => resolve(null);
  });
}

async function writeCachedTTS(key, blob) {
  const db = await openTTSDB();
  if (!db || !key || !blob) return;
  try {
    const tx = db.transaction(TTS_STORE, 'readwrite');
    tx.objectStore(TTS_STORE).put(blob, key);
  } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:write_cached_tts", err); }
}

function latchTtsRateLimit(res) {
  const retryAfter = Math.max(5, parseInt(res?.headers?.get?.('Retry-After') || '60', 10) || 60) * 1000;
  tts.serverFailureCount = (tts.serverFailureCount || 0) + 1;
  tts.serverUnavailable = true;
  tts.serverUnavailableUntil = Date.now() + retryAfter;
  tts.prefetch.clear();
  setTtsHealthStatus(`tts: waiting ${Math.ceil(retryAfter / 1000)}s (rate limit)`);
}
async function loadTTSBlob(text, voice, style) {
  if (tts.serverUnavailable && Date.now() < (tts.serverUnavailableUntil || 0)) throw new Error('429');
  const key = await ttsCacheKey(text, voice, style).catch(() => null);
  const cached = key ? await readCachedTTS(key) : null;
  if (cached) return cached;
  while ((tts.synthInFlight || 0) >= TTS_SYNTH_MAX) {
    await new Promise((resolve) => setTimeout(resolve, 40));
    if (tts.serverUnavailable && Date.now() < (tts.serverUnavailableUntil || 0)) throw new Error('429');
  }
  tts.synthInFlight = (tts.synthInFlight || 0) + 1;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TTS_FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(ttsURL(text, voice, style), { signal: controller.signal });
    clearTimeout(timer);
    if (res.status === 202) {
      const job = res.headers.get('X-TTS-Job') || (await res.json().catch(() => ({}))).job;
      if (!job) throw new Error('tts pending without job');
      if (window.MASTER_RUNTIME?.enhancements?.includes?.('tts_stream_chunk')) {
        const early = _parseTtsVisemeHeader(res);
        if (early) forwardEarlyVisemePlan(early);
      }
      return pollTTSJob(job, controller.signal);
    }
    if (res.status === 429) {
      latchTtsRateLimit(res);
      throw new Error('429');
    }
    if (!res.ok) throw new Error(res.status);
    const meta = _parseTtsMetaHeader(res);
    const visemes = _parseTtsVisemeHeader(res) || meta?.viseme_plan || meta?.viseme_hints;
    if (visemes) tts.visemePlan = visemes;
    const blob = await res.blob();
    writeCachedTTS(key, blob);
    return blob;
  } catch (e) {
    clearTimeout(timer);
    throw e;
  } finally {
    tts.synthInFlight = Math.max(0, (tts.synthInFlight || 0) - 1);
  }
}

function forwardEarlyVisemePlan(visemes) {
  if (!visemes?.length) return;
  tts.visemePlan = visemes;
  window.dispatchEvent(new CustomEvent('tts:viseme:plan', { detail: { viseme_plan: visemes, frames: visemes } }));
  if (typeof startVisemeAnim === 'function' && tts.current) startVisemeAnim(tts.current);
}

async function tryPartialTTSPlay(job, bytes) {
  if (!window.MASTER_RUNTIME?.enhancements?.includes?.('tts_audio_stream')) return;
  if (bytes < 4096 || tts._partialPlayed) return;
  try {
    const res = await fetch(`/chat/tts/stream?job=${encodeURIComponent(job)}`);
    if (!res.ok || res.status === 202) return;
    const blob = await res.blob();
    if (!blob || blob.size < 4096) return;
    tts._partialPlayed = true;
    emitTtsEvent('tts:chunk:partial', { job, bytes: blob.size });
    const url = URL.createObjectURL(blob);
    const partial = new Audio(url);
    partial.preload = 'auto';
    // The streamed partial played 15% under everything else for no stated
    // reason, so the first thing heard of every utterance was the quietest.
    partial.volume = Math.min(1, tts.volume || 1);
    partial.addEventListener('ended', () => URL.revokeObjectURL(url), { once: true });
    partial.addEventListener('error', () => URL.revokeObjectURL(url), { once: true });
    if (!tts.playing) partial.play().catch(() => URL.revokeObjectURL(url));
  } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:stream_partial", err); }
}

async function pollTTSJob(job, signal) {
  const streamChunk = window.MASTER_RUNTIME?.enhancements?.includes?.('tts_stream_chunk');
  const audioStream = window.MASTER_RUNTIME?.enhancements?.includes?.('tts_audio_stream');
  // ~3 minutes of patience, not ~26s: synthesis is a serial queue on a 1-CPU
  // VPS, so a reply behind a few other chunks legitimately takes 30-60s+.
  // Giving up early threw "tts timeout", which latched serverUnavailable and
  // silenced every later utterance — the "it only says scanning" bug (the
  // pre-cached status phrases play instantly; everything real timed out).
  // Late audio is still worth having: ttsTick serializes playback anyway.
  // Poll fast while the answer is still worth feeling instant, then back off.
  //
  // The previous schedule (40ms, then 80 + attempt*90 capped at 1200) started
  // backing off immediately, so by the time synthesis finished the client was
  // already sleeping in long gaps and noticed late: measured against the
  // schedule itself, audio ready at 1.5s was picked up at 1.79s, at 2.5s it was
  // picked up at 3.12s, and at 4s it was picked up at 4.81s. Up to 810ms of the
  // wait was the client not looking, not the server not finishing.
  //
  // A flat 90ms for the first ~1.6s costs at most 18 extra requests against a
  // local endpoint, and holds worst-case discovery lag under a tenth of a
  // second across the whole range where a reply still feels immediate. After
  // that the old curve resumes, because a job that has taken two seconds is
  // queued behind something and hammering it helps nobody.
  for (let attempt = 0; attempt < 110; attempt++) {
    const delay = attempt === 0 ? 30 : (attempt <= 18 ? 90 : Math.min(120 + (attempt - 18) * 90, 1200));
    await new Promise((resolve) => setTimeout(resolve, delay));
    const res = await fetch(`/chat/tts/status?job=${encodeURIComponent(job)}`, { signal });
    if (res.status === 202) {
      if (streamChunk) {
        const visemes = _parseTtsVisemeHeader(res) || _parseTtsMetaHeader(res)?.viseme_plan;
        if (visemes) forwardEarlyVisemePlan(visemes);
        emitTtsEvent('tts:chunk:wait', { job, attempt });
      }
      if (audioStream) {
        const avail = Number(res.headers.get('X-TTS-Bytes') || 0);
        if (avail > 0) tryPartialTTSPlay(job, avail);
      }
      continue;
    }
    if (res.status === 429) {
      latchTtsRateLimit(res);
      await new Promise((resolve) => setTimeout(resolve, Math.min(15000, (tts.serverUnavailableUntil || 0) - Date.now() || 5000)));
      continue;
    }
    if (!res.ok) throw new Error(res.status);
    const meta = _parseTtsMetaHeader(res);
    const visemes = _parseTtsVisemeHeader(res) || meta?.viseme_plan || meta?.viseme_hints;
    if (visemes) tts.visemePlan = visemes;
    return res.blob();
  }
  throw new Error('tts timeout');
}

function buildRoomIR(ctx) {
  const sr = ctx.sampleRate, len = Math.floor(sr * 0.28);
  const ir = ctx.createBuffer(2, len, sr);
  for (let ch = 0; ch < 2; ch++) {
    const d = ir.getChannelData(ch);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 4.2);
  }
  return ir;
}

async function connectTTSAudio(audio, boostValue = 1.35) {
  if (LOW_POWER) return;
  if (!actx || actx.state === 'closed') return;
  if (actx.state === 'suspended') await actx.resume().catch(() => {});
  if (actx.state !== 'running') return;
  const msrc = actx.createMediaElementSource(audio);
  const boost = actx.createGain();
  const warmth = actx.createBiquadFilter();
  const smooth = actx.createBiquadFilter();
  const presence = actx.createBiquadFilter();
  const compressor = actx.createDynamicsCompressor();
  const convolver = actx.createConvolver();
  const dryGain = actx.createGain();
  const wetGain = actx.createGain();
  const masterGain = actx.createGain();
  const analyser = actx.createAnalyser();
  boost.gain.value = boostValue;
  warmth.type = 'lowshelf'; warmth.frequency.value = 220; warmth.gain.value = 3.5;
  smooth.type = 'highshelf'; smooth.frequency.value = 8500; smooth.gain.value = -3;
  presence.type = 'peaking'; presence.frequency.value = 3200; presence.Q.value = 1.2; presence.gain.value = -1.8;
  // Opened up because the gain above feeds this. At -22/7:1 almost everything
  // was above the knee, so raising masterGain bought compression rather than
  // loudness — the level went up and got squashed back down in the same graph.
  // -12 and 3:1 still catches peaks and lets the gain reach the output.
  compressor.threshold.value = -12; compressor.knee.value = 18; compressor.ratio.value = 3;
  compressor.attack.value = 0.004; compressor.release.value = 0.22;
  convolver.buffer = buildRoomIR(actx);
  // Operator, 2026-08-11: no reverb on the voice, and 10x louder. The wet leg is
  // left wired rather than unpicked from the graph so restoring it is one
  // number, but it contributes nothing at 0.
  //
  // 1.9, which is what fits. Measured 2026-08-13 against a real /chat/tts
// response: edge-tts hands us speech peaking at -4.5 dBFS, and this graph
// (boost 1.35 -> warmth +3.5 -> smooth -3 -> presence -1.8 -> compressor at
// -12/3:1) leaves it peaking at -5.5 dBFS. The largest gain that fits under
// 0 dBFS is 1.88x. 19.0 put the output 20.1 dB over, so every utterance was
// hard-clipped by the destination and the compressor pumped underneath it —
// audible as a thin, torn voice rather than a loud one.
//
// "10x louder" multiplied a number that was already at the ceiling. The lever
// for loudness is the synthesiser, where data/voice.yml already asks for
// +40% volume, or a limiter here. Not raw gain into a clamped destination.
//
// Published on tts so face_audio_bridge duck-restores to the live value;
// TTS_PLAYBACK_GAIN there must stay equal to this.
const masterGainValue = 1.9;
  dryGain.gain.value = 1.0; wetGain.gain.value = 0.0; masterGain.gain.value = masterGainValue;
  tts.playbackGain = masterGainValue;
  analyser.fftSize = 256;
  msrc.connect(boost);
  boost.connect(warmth); warmth.connect(smooth); smooth.connect(presence);
  presence.connect(dryGain); presence.connect(convolver);
  convolver.connect(wetGain);
  dryGain.connect(masterGain); wetGain.connect(masterGain);
  masterGain.connect(compressor); compressor.connect(analyser); analyser.connect(actx.destination);
  tts.analyser = analyser;
  tts.outputGain = masterGain;
  tts.analyserBuf = new Uint8Array(analyser.fftSize);
  tts.analyserFreqBuf = new Uint8Array(analyser.frequencyBinCount);
}

function hasAnalyserBuffers() {
  return !!(tts.playing && tts.analyser && tts.analyserBuf && tts.analyserFreqBuf);
}

function finishTTSPlayback(src, continueQueue = true) {
  const finishedText = tts.current || tts.lastText || '';
  const style = State.currentSpeechStyle || _nextTtsStyle();
  const decay_rate = _ttsStyleDecayRate(style);
  if (tts.playing || finishedText) {
    emitTtsEvent('tts:playback:end', { text: finishedText, interrupted: !continueQueue, backend: 'edge', style, decay_rate });
  }
  _applyLocalPostSpeechDecay(decay_rate);
  // Blink on finishing a thought. Humans blink at clause boundaries and just
  // after an utterance ends, and that coupling is most of what makes a blink
  // read as punctuation rather than a timer running behind the face. Skipped
  // when the utterance was cut off — an interruption is not a completed thought.
  if (continueQueue) window.MASTER_ATTENTION?.cue?.('utterance_end');
  tts.visemePlan = null;
  if (tts.outputGain && actx && Number.isFinite(tts.playbackGain)) {
    tts.outputGain.gain.setValueAtTime(tts.playbackGain, actx.currentTime);
  }
  setTTSLoading(false);
  stopVisemeAnim();
  rootBody.dataset.ttsWave = '';
  clearThinkingAloud?.();
  tts.analyser = null; tts.analyserBuf = null; tts.analyserFreqBuf = null;
  tts.resumeTime = null; tts.resumeWordIndex = null;
  if (src) URL.revokeObjectURL(src);
  tts.audio = null; tts.playing = false; tts.paused = false;
  if (tts.watchdog) { clearTimeout(tts.watchdog); tts.watchdog = null; }
  if (State.mode === 'speaking') { State.mode = 'idle'; window.MASTER_FACE?.setAmbientHum?.(false); }
  clearViseme();
  if (ttsLive) ttsLive.textContent = '';
  if (spinBtn) { spinBtn.textContent = '❚❚'; spinBtn.setAttribute('aria-label', 'Pause or resume'); }
  tts.current = null;
  if (continueQueue) ttsTick();
}

function fetchTTS(text, voice, style) {
  if (tts.serverUnavailable && Date.now() < (tts.serverUnavailableUntil || 0)) return;
  if (tts.serverUnavailable && Date.now() >= (tts.serverUnavailableUntil || 0)) tts.serverUnavailable = false;
  if (tts.prefetch.has(text) || ttsPrefetchInFlight >= TTS_PREFETCH_MAX) return;
  const meta = tts.meta.get(text) || {};
  ttsPrefetchInFlight++;
  const p = loadTTSBlob(text, voice || meta.voice, style || meta.style)
    .catch(() => null)
    .finally(() => { ttsPrefetchInFlight = Math.max(0, ttsPrefetchInFlight - 1); });
  tts.prefetch.set(text, p);
}
const PARALINGUISTIC_RE = /\[(chuckle|sigh|laugh|cough)\]/i;
function applyParalinguisticState(text) {
  const m = String(text || '').match(PARALINGUISTIC_RE);
  if (!m) return;
  const tag = m[1].toLowerCase();
  if (tag === 'chuckle' || tag === 'laugh') {
    State.laughter = Math.min(1, (State.laughter || 0) + 0.65);
    rootBody.dataset.laughter = '1';
    setTimeout(() => { delete rootBody.dataset.laughter; State.laughter = 0; }, 2400);
  }
  if (tag === 'sigh') {
    State.breath = Math.max(0.45, (State.breath || 1) * 0.72);
    State.mood = 'weary';
  }
}

function dropQueuedSpeech(text) {
  const index = tts.queue.indexOf(text);
  if (index >= 0) tts.queue.splice(index, 1);
}

// Errors first, then the thing the visitor actually asked for, then filler.
// The nudge lane used to outrank `response`, so an idle-loop line queued while
// a reply was still waiting on synthesis was spoken *instead of* the reply,
// first — literally answering a question with "the moon is just a really
// committed pebble". Filler is by definition the most droppable thing here, so
// it drains last.
function nextQueuedSpeech() {
  return tts.lanes.error[0] || tts.lanes.response[0] || tts.lanes.nudge[0] || tts.queue[0];
}

function dequeueTtsLane() {
  const text = tts.lanes.error.shift() || tts.lanes.response.shift() || tts.lanes.nudge.shift();
  if (text) {
    dropQueuedSpeech(text);
    return text;
  }
  return tts.queue.shift();
}

function enqueueSpeech(text, opts = {}) {
  if (tts.muted) return;
  // Speaking counts as activity — keeps frame()'s idle drift from dissolving
  // the face while a long reply is being read aloud.
  State.lastTouch = performance.now();
  emitTtsEvent('tts:anticipate', { expression: { arousal: 0.25 }, style: _nextTtsStyle(_nextTtsVoice()) });
  window.MASTERVisual?.event?.('tts:prefetch', { topology: 'papua-mask', entropy: 0.22, confidence: 0.8, mode: 'anticipate' });
  const clean = text
    .replace(/```[\s\S]*?```/g, '')
    .replace(/`[^`]*`/g, '')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/^[-*+]\s+/gm, '')
    .replace(/^\d+\.\s+/gm, '')
    .replace(/^[-_*]{3,}$/gm, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[*_~]/g, '')
    .trim();
  if (!clean) return;
  if (!shouldEnqueueTtsChunk(clean, opts)) return;
  const _v = _nextTtsVoice();
  const decorated = _quirkifyTts(clean, _v, opts);
  applyParalinguisticState(decorated);
  if (tts.meta.size > 32) tts.meta.clear();
  tts.meta.set(decorated, {
    voice: _v,
    style: _nextTtsStyle(_v),
    lane: opts.priority === 'error' ? 'error' : (opts.quirky || opts.nudge ? 'nudge' : 'response'),
  });
  announceTTS(decorated);
  tts.lastText = decorated;
  tts.resumeTime = null;
  tts.resumeWordIndex = null;
  const lane = opts.priority === 'error' ? 'error' : (opts.quirky || opts.nudge ? 'nudge' : 'response');
  // A real reply makes every queued idle line stale — nobody wants yesterday's
  // filler read out after their answer. Reordering the lanes alone would only
  // defer them, not drop them, so the backlog would still be spoken eventually.
  if (lane === 'response' && tts.lanes.nudge.length) {
    tts.lanes.nudge.splice(0).forEach((stale) => {
      dropQueuedSpeech(stale);
      tts.prefetch.delete(stale);
      tts.meta.delete(stale);
    });
  }
  tts.lanes[lane].push(decorated);
  tts.queue.push(decorated);
  nodImpulse += 0.022;
  ttsTick();
}

function requeueChunk(text) {
  if (!text) return false;
  const n = (tts.attempts.get(text) || 0) + 1;
  if (n > 5) { tts.attempts.delete(text); return false; }
  tts.attempts.set(text, n);
  tts.queue.unshift(text);
  return true;
}
function scheduleTtsTick(delay) {
  if (tts.retryTimer) clearTimeout(tts.retryTimer);
  tts.retryTimer = setTimeout(() => { tts.retryTimer = null; ttsTick(); }, delay || 600);
}

function highQualityVoiceEnabled() {
  if (new URLSearchParams(window.location.search).get('hq_voice') === '1') return true;
  try { return localStorage.getItem('master:voice-mode-hq') === '1'; } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:hq_voice_read", err); }
  return false;
}
function browserTtsFallbackAllowed() {
  // Inside Voice Mode, browser speechSynthesis is the deliberate default
  // (instant, zero server load) rather than an opt-in fallback — the VPS's
  // server-TTS latency floor is incompatible with a live conversation. The
  // "high-quality voice" toggle opts back into server TTS and accepts the
  // latency. Outside Voice Mode, normal chat keeps server TTS as primary.
  if (State.voiceMode && !highQualityVoiceEnabled()) return true;
  if (new URLSearchParams(window.location.search).get('tts_fallback') === '1') return true;
  try { return localStorage.getItem('master:tts-fallback') === '1'; } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:fallback_allowed_read", err); }
  return false;
}
// speechSynthesis.getVoices() is populated asynchronously in Chrome: it
// returns [] on first call and fills in on the 'voiceschanged' event. Touch it
// early so a real voice list exists by the time Voice Mode wants to speak.
let _browserVoicesPrimed = false;
function primeBrowserVoices() {
  if (_browserVoicesPrimed || !('speechSynthesis' in window)) return;
  _browserVoicesPrimed = true;
  try {
    speechSynthesis.getVoices();
    speechSynthesis.addEventListener('voiceschanged', () => {}, { once: true });
  } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:voices_prime", err); }
}
function pickBrowserVoice(lang) {
  let voices = [];
  try { voices = speechSynthesis.getVoices() || []; } catch (_) { return null; }
  if (!voices.length) return null;
  const want = String(lang).toLowerCase();
  const base = want.split('-')[0];
  return voices.find((v) => (v.lang || '').toLowerCase() === want)
      || voices.find((v) => (v.lang || '').toLowerCase().startsWith(base))
      || voices.find((v) => v.default)
      || voices[0];
}
// Warm the voice list as soon as this segment loads, so the first thing said
// in Voice Mode is not the one utterance that finds getVoices() still empty.
primeBrowserVoices();

// Time-boxed, per the boot contract: browser speech must never permanently
// downgrade the session, so a failure parks it for five minutes and then lets
// it try again.
const BROWSER_TTS_COOLDOWN_MS = 300000;
function browserTtsParked() {
  return tts.browserTtsBrokenUntil ? Date.now() < tts.browserTtsBrokenUntil : false;
}
function parkBrowserTts(reason) {
  tts.browserTtsBrokenUntil = Date.now() + BROWSER_TTS_COOLDOWN_MS;
  window.MASTER_LOG?.warn?.("face_speech_runtime:browser_tts_parked", reason);
}
function speakWithBrowserTTS(text, token) {
  if (!browserTtsFallbackAllowed()) return false;
  if (!('speechSynthesis' in window) || !window.SpeechSynthesisUtterance) return false;
  if (browserTtsParked()) return false;

  // Returning false here is the whole point: the caller then falls through to
  // server TTS. Previously this function returned true the moment speak() did
  // not throw, whether or not anything could ever be spoken. When no voice
  // matched the utterance language — or the voice list had not loaded yet —
  // speak() silently did nothing, onstart/onend never fired, tts.playing stayed
  // true and setTTSLoading(false) never ran. That one bug produced all three
  // reported symptoms at once: no audio, a mic that never re-armed because
  // resumeSttAfterSpeech() is only reached from onend, and the same sentence
  // spoken again each time the watchdog requeued it.
  // en-US, not en-GB. This is the browser-speech fallback used when the neural
  // endpoint is unavailable, and it picked a British voice for every non-nb
  // utterance — so the fallback contradicted the policy voice precisely when it
  // was the only thing speaking.
  //
  // Deliberately still en-US now that the policy voice is ms-MY-OsmanNeural: the
  // words are English either way, and a browser is far likelier to ship an
  // en-US voice than an ms-MY one. Asking for a locale the platform lacks gets
  // an arbitrary substitute, which is worse than a plain English fallback. The
  // Malay accent is a property of the neural voice, not something this path can
  // reproduce.
  const lang = tts.lang === 'nb' ? 'nb-NO' : 'en-US';
  const voice = pickBrowserVoice(lang);
  if (!voice) { primeBrowserVoices(); return false; }

  const utterance = new SpeechSynthesisUtterance(text);
  utterance.voice = voice;
  utterance.lang = voice.lang || lang;
  utterance.rate = getTtsRate();

  let started = false;
  let startGuard = null;
  const clearGuard = () => { if (startGuard) { clearTimeout(startGuard); startGuard = null; } };

  utterance.onstart = () => {
    started = true;
    clearGuard();
    emitTtsEvent('tts:playback:start', { text, backend: 'browser', duration: null });
    startVisemeAnim(text);
    setTTSLoading(false);
  };
  utterance.onend = utterance.onerror = () => {
    clearGuard();
    if (token !== tts.cancelToken) return;
    emitTtsEvent('tts:playback:end', { text, interrupted: false, backend: 'browser' });
    stopVisemeAnim();
    clearViseme();
    tts.playing = false;
    tts.audio = null;
    tts.current = null;
    if (tts.watchdog) { clearTimeout(tts.watchdog); tts.watchdog = null; }
    if (State.mode === 'speaking') State.mode = 'idle';
    ttsTick();
  };

  try {
    speechSynthesis.cancel();
    speechSynthesis.speak(utterance);
  } catch (_) {
    return false;
  }

  // speak() accepted it, but acceptance is not utterance. If nothing has begun
  // shortly after, treat browser speech as unavailable and hand this same text
  // back to the queue so the server voice says it — rather than stalling the
  // queue and the mic behind an utterance that will never start or end.
  startGuard = setTimeout(() => {
    startGuard = null;
    if (started || token !== tts.cancelToken) return;
    try { speechSynthesis.cancel(); } catch (_) { /* already gone */ }
    parkBrowserTts('speech never started');
    tts.playing = false;
    tts.current = null;
    if (tts.watchdog) { clearTimeout(tts.watchdog); tts.watchdog = null; }
    if (State.mode === 'speaking') State.mode = 'idle';
    requeueChunk(text);
    scheduleTtsTick(50);
  }, 1500);

  return true;
}

function ttsTick() {
  if (tts.muted || tts.playing || tts.paused) return;
  const text = dequeueTtsLane();
  if (!text) { resumeSttAfterSpeech(); return; }
  tts.current = text;
  tts.playing = true;
  // Duck the mic while we speak: continuous SpeechRecognition has no echo
  // cancellation against this page's own audio output, so an open mic during
  // playback transcribes the assistant's own reply and resubmits it as if the
  // user said it, producing an unprompted follow-up reply (reported as the
  // assistant "randomly saying facts"). See resumeSttAfterSpeech() below.
  if (State.sttActive) { try { stopSTT(); } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:tts_tick_stt_duck", err); } }
  const token = ++tts.cancelToken;
  setTTSLoading(true);
  if (actx?.state === 'suspended') actx.resume().catch(() => {});
  if (tts.watchdog) clearTimeout(tts.watchdog);
  // The watchdog arms BEFORE the blob fetch, so its timeout must cover the
  // whole synthesis queue wait (pollTTSJob is allowed ~3 minutes on the
  // 1-CPU VPS), not just playback. At the old 20s floor it fired while jobs
  // were still legitimately pending, requeued each utterance, and after
  // requeueChunk's 3 attempts DROPPED it - so only the instant pre-cached
  // status phrases ("Scanning.") were ever heard while every real reply
  // died in the queue. 200s base + playback allowance keeps it as a true
  // hung-playback failsafe instead of a queue-latency killer.
  const wdMs = 200000 + Math.min(120000, Math.max(20000, text.length * 180));
  tts.watchdog = setTimeout(() => { if (tts.playing && token === tts.cancelToken) { console.warn('tts watchdog: requeue'); requeueChunk(text); finishTTSPlayback(null, true); } }, wdMs);
  State.mode = 'speaking'; setAmbientHum(false);
  // Voice Mode default: speak instantly via the browser, skip the Edge
  // round-trip entirely. Opt into server TTS quality via the "high-quality
  // voice" toggle if the latency is acceptable for this conversation.
  // Say which voice this is, once per session. Voice Mode deliberately speaks
  // through the browser rather than the server — see browserTtsFallbackAllowed,
  // the VPS latency floor is incompatible with a live conversation — so the
  // voice here is the operating system's, not the one data/voice.yml names.
  // That is a reasonable trade and an unreasonable surprise: someone who has
  // just changed the configured voice hears an unrelated one and concludes the
  // change did not take. The toggle is hq_voice=1 or master:voice-mode-hq.
  if (State.voiceMode && !highQualityVoiceEnabled() && !tts.browserVoiceNoticeShown) {
    tts.browserVoiceNoticeShown = true;
    setTtsHealthStatus('voice mode: browser voice (hq off)');
  }
  if (State.voiceMode && !highQualityVoiceEnabled() && speakWithBrowserTTS(text, token)) return;
  if (tts.serverUnavailable && Date.now() < (tts.serverUnavailableUntil || 0) && speakWithBrowserTTS(text, token)) return;
  if (tts.serverUnavailable && Date.now() < (tts.serverUnavailableUntil || 0)) { tts.playing = false; tts.current = null; setTTSLoading(false); ttsTick(); return; }
  if (tts.serverUnavailable) tts.serverUnavailable = false;
  const meta = tts.meta.get(text) || {};
  const voice = meta.voice || _activeTtsVoice();
  const style = meta.style;
  const edgeBlob = tts.prefetch.get(text) || loadTTSBlob(text, voice, style);
  tts.prefetch.delete(text);
  tts.meta.delete(text);
  const nextSpeech = nextQueuedSpeech();
  if (nextSpeech) fetchTTS(nextSpeech);

  let settled = false;

  async function playEdge(blob) {
    if (settled || token !== tts.cancelToken) return;
    settled = true;
    const src = URL.createObjectURL(blob);
    const audio = new Audio(src);
    const baseRate = getTtsRate() * 0.97;
    // Measure duration for beat quantization — 1.5s timeout guards against silent hang
    const dur = await new Promise(resolve => {
      const t = setTimeout(() => resolve(null), 280);
      audio.onloadedmetadata = () => { clearTimeout(t); resolve(audio.duration); };
      audio.onerror = () => { clearTimeout(t); resolve(null); };
      audio.load();
    });
    if (token !== tts.cancelToken) { URL.revokeObjectURL(src); return; }
    audio.playbackRate = LOW_POWER ? 1.0 : baseRate;
    if (token !== tts.cancelToken) { URL.revokeObjectURL(src); return; }
    if (tts.audio && tts.audio !== audio) { try { tts.audio.pause(); } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:audio_pause", err); } }
    tts.audio = audio;
    setTTSLoading(false);
    if (spinBtn) { spinBtn.textContent = '❚❚'; spinBtn.setAttribute('aria-label', 'Pause or resume'); }
    audio.onplay = () => {
      emitTtsEvent('tts:playback:start', { text, voice, style, duration: dur || audio.duration || null, backend: 'edge' });
      startVisemeAnim(text);
      if (navigator.vibrate) navigator.vibrate([35, 55, 35]);
      rootBody.dataset.ttsWave = 'true';
      preSpeechInhale(style);
    };
    audio.onended = audio.onerror = () => finishTTSPlayback(src);
    connectTTSAudio(audio).catch(() => {});
    audio.play().catch(() => { requeueChunk(text); finishTTSPlayback(src); });
  }

  edgeBlob
    .then(blob => { if (!blob) throw new Error('empty'); playEdge(blob); })
    .catch(() => {
      tts.serverFailureCount = (tts.serverFailureCount || 0) + 1;
      tts.serverUnavailable = true;
      tts.serverUnavailableUntil = Date.now() + Math.min(30000, 5000 * tts.serverFailureCount);
      if (speakWithBrowserTTS(text, token)) return;
      setTtsHealthStatus('tts: unavailable', 12000);
      tts.audio = null; tts.playing = false; tts.current = null; setTTSLoading(false);
      requeueChunk(text);
      const s = document.getElementById('zsh-status');
      if (s && (tts.attempts.get(text) || 0) >= 3) {
        s.textContent = 'tts fail';
        rootBody.dataset.ttsError = 'true';
        const errLive = document.getElementById('error-live');
        if (errLive) errLive.textContent = 'speech unavailable';
        setTimeout(() => {
          rootBody.dataset.ttsError = '';
          if (s.textContent === 'tts fail') s.textContent = '';
          if (errLive?.textContent === 'speech unavailable') errLive.textContent = '';
        }, 2500);
      }
      const retryMs = Math.max(800, (tts.serverUnavailableUntil || 0) - Date.now() || 0);
      if (token === tts.cancelToken) scheduleTtsTick(retryMs);
    });
}

function ttsTogglePause() {
  if (!tts.audio) return;
  if (tts.audio.paused) {
    if (tts.resumeTime != null && typeof tts.audio.duration === 'number' && tts.audio.duration > 0) {
      const seek = Math.max(0, Math.min(tts.audio.duration, tts.resumeTime));
      try { tts.audio.currentTime = seek; } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:seek_resume", err); }
    }
    tts.audio.play().catch(() => {});
    tts.paused = false;
    if (spinBtn) { spinBtn.textContent = '❚❚'; spinBtn.setAttribute('aria-label', 'Pause current response'); }
    return;
  }
  if (typeof tts.audio.currentTime === 'number' && typeof tts.audio.duration === 'number' && tts.audio.duration > 0) {
    const text = tts.lastText || '';
    const words = text.split(/\s+/).filter(Boolean);
    const ratio = Math.max(0, Math.min(1, tts.audio.currentTime / tts.audio.duration));
    const idx = words.length ? Math.max(0, Math.min(words.length - 1, Math.floor(ratio * words.length))) : 0;
    tts.resumeWordIndex = idx;
    tts.resumeTime = words.length ? (idx / words.length) * tts.audio.duration : tts.audio.currentTime;
  }
  tts.audio.pause();
  tts.paused = true;
  if (spinBtn) { spinBtn.textContent = '▶'; spinBtn.setAttribute('aria-label', 'Resume current response'); }
}

(function pollDeployHealth() {
  const refresh = () => {
    fetch('/health', { credentials: 'same-origin', cache: 'no-store' })
      .then((r) => (r.ok ? r.json() : null))
      .then((body) => {
        if (!body) return;
        if (body.deploy?.tts_socket === false) setTtsHealthStatus('tts: socket down', 12000);
        else if (body.checks?.tts === false) setTtsHealthStatus('tts: unavailable', 12000);
      })
      .catch(() => {});
  };
  refresh();
  setInterval(refresh, 60000);
})();

window.MASTER_SPEECH_RUNTIME = Object.freeze({
  get tts() { return tts; },
  initAudio,
  enqueueSpeech,
  ttsTick,
  loadTTSBlob,
  emitTtsEvent,
  browserTtsFallbackAllowed,
  highQualityVoiceEnabled,
  speakWithBrowserTTS,
});
window.MASTER = window.MASTER || {};
window.MASTER.speechRuntime = window.MASTER_SPEECH_RUNTIME;
