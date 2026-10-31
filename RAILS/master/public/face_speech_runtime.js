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

// Resolves once the context runs. A context created before the first gesture
// starts suspended, and anything scheduled on it would sound at that gesture.
function whenAudioRunning() {
  return new Promise((resolve) => {
    if (actx.state === 'running') { resolve(); return; }

    const onChange = () => {
      if (actx.state !== 'running') return;
      actx.removeEventListener('statechange', onChange);
      resolve();
    };
    actx.addEventListener('statechange', onChange);
  });
}

// The startup sound is the file MASTER renders for the terminal too (voice.yml
// boot_sound, surface web), so the two surfaces share one score. It plays only
// once the context runs, and not at all when the first gesture comes after
// late_gesture_s, because by then the user is already working. The gain ramp
// guards the onset even if the file's own fade were lost.
async function bootChime() {
  const spec = window.MASTER_VOICE_POLICY?.boot_sound;
  if (!actx || !spec?.url || document.documentElement.dataset.masterBootChime === '1') return;

  document.documentElement.dataset.masterBootChime = '1';
  try {
    const response = await fetch(new URL(spec.url, document.baseURI).href, { cache: 'force-cache' });
    if (!response.ok) return;

    const buffer = await actx.decodeAudioData(await response.arrayBuffer());
    await whenAudioRunning();
    if (tts.muted || performance.now() > (spec.late_gesture_s || 15) * 1000) return;

    const source = actx.createBufferSource();
    const gain = actx.createGain();
    const t = actx.currentTime;

    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(1, t + (spec.fade_ms || 300) / 1000);
    source.buffer = buffer;
    source.connect(gain);
    gain.connect(actx.destination);
    source.start(t);
  } catch (err) { window.MASTER_LOG?.warn?.("face_speech_runtime:boot_chime", err); }
}

function systemMotif(kind) {
  if (!actx || document.documentElement.dataset.masterSystemMotif === kind) return;
  document.documentElement.dataset.masterSystemMotif = kind;
  const motifs = {
    success: [523.25, 659.25],
    error: [220, 164.81]
  };
  const notes = motifs[kind];
  if (!notes) return;
  notes.forEach((freq, index) => {
    const carrier = actx.createOscillator();
    const modulator = actx.createOscillator();
    const depth = actx.createGain();
    const gain = actx.createGain();
    carrier.type = 'square';
    carrier.frequency.value = freq;
    modulator.type = 'sine';
    modulator.frequency.value = freq * 2;
    depth.gain.value = freq * 0.035;
    modulator.connect(depth);
    depth.connect(carrier.frequency);
    carrier.connect(gain);
    gain.connect(actx.destination);
    const t = actx.currentTime + 0.015 + index * 0.07;
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(0.018, t + 0.006);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.11);
    carrier.start(t);
    modulator.start(t);
    carrier.stop(t + 0.12);
    modulator.stop(t + 0.12);
  });
  setTimeout(() => { delete document.documentElement.dataset.masterSystemMotif; }, 260);
}

window.addEventListener('task:complete', () => systemMotif('success'));
window.addEventListener('tool:failed', () => systemMotif('error'));
window.addEventListener('heartbeat:scan_clean', () => systemMotif('success'));

const LOW_POWER = (/SMART[-_ ]?TV|SmartTV|Tizen|Web0?S|HbbTV|VIDAA|NetCast|BRAVIA|Sharp|TCL|Hisense|Vizio|Roku|AppleTV|HiSilicon|MTK|AMLogic/i.test(navigator.userAgent) || (typeof navigator.hardwareConcurrency === "number" && navigator.hardwareConcurrency > 0 && navigator.hardwareConcurrency < 4));
const tts = { lanes: { error: [], nudge: [], response: [] }, queue: [], prefetch: new Map(), attempts: new Map(), meta: new Map(), retryTimer: null, muted: false, playing: false, paused: false, loading: false, cancelToken: 0, current: null, audio: null, visemeTimer: null, performancePlan: null, serverUnavailable: false, serverUnavailableUntil: 0, serverFailureCount: 0, synthInFlight: 0, analyser: null, analyserBuf: null, analyserFreqBuf: null, pitchOffset: 0, lang: 'en', resumeTime: null, resumeWordIndex: null };
const TTS_DB_NAME = 'master-tts-v1';
const TTS_STORE = 'blobs';
// Fallback matches data/voice.yml, and has to: a failure to load
// MASTER_VOICE_POLICY otherwise switches the voice, its accent and its language
// with nothing said. This literal has been wrong in both directions — Pernille
// here while the policy said Osman, then Osman here while the policy said
// Pernille — which is the two-halves bug voice.yml's own header documents.
const TTS_DEFAULT_VOICE = window.MASTER_VOICE_POLICY?.neural || 'en-US-ChristopherNeural';
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
// Quirks are voice-independent. The two that keyed on a voice name took the
// alias, and the only caller passes the policy voice's full neural name, so
// neither ever fired; they are gone and the parameter with them.
function _quirkifyTts(text, opts = {}) {
  if (!opts.quirky) return text;
  if (text.length < 12) return text;
  const r = Math.random;
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
  setAmbientHum(tts.loading && !tts.playing);
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
    if (meta?.performance) {
      const queued = tts.meta.get(text);
      if (queued) queued.performance = meta.performance;
      if (tts.current === text) tts.performancePlan = meta.performance;
    }
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

async function pollTTSJob(job, signal) {
  const streamChunk = window.MASTER_RUNTIME?.enhancements?.includes?.('tts_stream_chunk');
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
  // Keep the first ~2s responsive without turning a queued job into a busy
  // loop. 50ms bounds discovery lag to roughly one network round-trip slice;
  // after the fast window, back off because a genuinely queued job gains
  // nothing from being polled dozens of times a second.
  for (let attempt = 0; attempt < 110; attempt++) {
    const delay = attempt === 0 ? 25 : (attempt <= 40 ? 50 : Math.min(120 + (attempt - 40) * 90, 1200));
    await new Promise((resolve) => setTimeout(resolve, delay));
    const res = await fetch(`/chat/tts/status?job=${encodeURIComponent(job)}`, { signal });
    if (res.status === 202) {
      if (streamChunk) {
        const visemes = _parseTtsVisemeHeader(res) || _parseTtsMetaHeader(res)?.viseme_plan;
        if (visemes) forwardEarlyVisemePlan(visemes);
        emitTtsEvent('tts:chunk:wait', { job, attempt });
      }
      // Do not play a truncated MP3 while the real utterance is still
      // being synthesized. An incomplete file is not a stream: it starts a
      // second Audio element from byte zero and can overlap the final reply.
      // Sentence-level live TTS already provides progressive speech safely.
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
    if (meta?.performance) {
      const queued = tts.meta.get(tts.current);
      if (queued) queued.performance = meta.performance;
      if (tts.current) tts.performancePlan = meta.performance;
    }
    return res.blob();
  }
  throw new Error('tts timeout');
}

// data/voice.yml's tts.post_chain, built as WebAudio nodes.
//
// The chain is dilla's: three resonant peaks at the vowel formants, a chorus,
// a phaser, a band and a limiter. The server applies it with ffmpeg and hands
// the same string to the page in MASTER_VOICE_POLICY, and until now nothing in
// the page read it — the face had its own invented chain instead, so the web
// and the terminal were two voices sharing a name. One declaration, two
// readers: ffmpeg on the server, these nodes here.
//
// Only the filters the chain actually uses are built. Anything else is named
// once in the console and skipped, because a filter silently dropped is a
// voice that differs from the server's without saying so.
function parseFilterArgs(argText) {
  const args = {};
  const positional = [];
  (argText || '').split(':').filter((part) => part.length).forEach((part) => {
    const eq = part.indexOf('=');
    if (eq > 0) args[part.slice(0, eq)] = part.slice(eq + 1);
    else positional.push(part);
  });
  args._ = positional;
  return args;
}

function dbToGain(text) {
  const value = parseFloat(text);
  if (!Number.isFinite(value)) return 1;
  return /db$/i.test(String(text).trim()) ? Math.pow(10, value / 20) : value;
}

// A chorus is delayed copies whose delay is swept by a slow oscillator. ffmpeg
// writes the voices as parallel lists: delays, decays, speeds and depths, one
// entry each per voice, in milliseconds, gain, hertz and milliseconds.
function buildChorus(ctx, args) {
  const named = args.delays !== undefined;
  const [inGain, outGain] = named ? [parseFloat(args.in_gain) || 1, parseFloat(args.out_gain) || 1] : [parseFloat(args._[0]) || 1, parseFloat(args._[1]) || 1];
  const lists = (named ? [args.delays, args.decays, args.speeds, args.depths] : args._.slice(2)).map((list) => String(list).split('|').map(parseFloat));
  const [delays = [20], decays = [0.3], speeds = [0.25], depths = [1]] = lists;
  const input = ctx.createGain();
  const output = ctx.createGain();
  const dry = ctx.createGain();
  dry.gain.value = inGain;
  input.connect(dry);
  dry.connect(output);
  delays.forEach((delayMs, i) => {
    const delay = ctx.createDelay(1);
    delay.delayTime.value = (delayMs || 20) / 1000;
    const voice = ctx.createGain();
    voice.gain.value = decays[i] === undefined ? 0.3 : decays[i];
    const lfo = ctx.createOscillator();
    lfo.frequency.value = speeds[i] === undefined ? 0.25 : speeds[i];
    const depth = ctx.createGain();
    depth.gain.value = ((depths[i] === undefined ? 1 : depths[i]) / 1000);
    lfo.connect(depth);
    depth.connect(delay.delayTime);
    lfo.start();
    input.connect(delay);
    delay.connect(voice);
    voice.connect(output);
  });
  output.gain.value = outGain;
  return { input, output };
}

// A phaser is allpass stages whose corner frequency is swept. Four stages is
// what ffmpeg's aphaser uses by default, and the sweep centre is chosen so the
// notches sit in the range a voice occupies.
function buildPhaser(ctx, args) {
  const speed = parseFloat(args.speed) || 0.5;
  const decay = parseFloat(args.decay) || 0.4;
  const input = ctx.createGain();
  const output = ctx.createGain();
  const wet = ctx.createGain();
  wet.gain.value = decay;
  const lfo = ctx.createOscillator();
  lfo.frequency.value = speed;
  const depth = ctx.createGain();
  depth.gain.value = 700;
  lfo.connect(depth);
  lfo.start();
  let node = input;
  for (let stage = 0; stage < 4; stage++) {
    const allpass = ctx.createBiquadFilter();
    allpass.type = 'allpass';
    allpass.frequency.value = 500 + stage * 400;
    allpass.Q.value = 0.7;
    depth.connect(allpass.frequency);
    node.connect(allpass);
    node = allpass;
  }
  node.connect(wet);
  wet.connect(output);
  input.connect(output);
  return { input, output };
}

// aeval, for the one shape the character presets actually write: ring
// modulation spelled as val(0)*(A+B*sin(2*PI*t*F)) — a dry floor A plus a
// carrier of F hertz at depth B, which is exactly a GainNode whose gain
// parameter a carrier oscillator rides. The matcher refuses every other
// expression: aeval is a language, not a filter, and a node that guessed at
// arithmetic would be a second voice under the preset's name. cos is accepted
// beside sin because the two differ only in carrier phase — a quarter period
// of a 38-50 hertz carrier, beneath perception in the envelope.
function buildAeval(ctx, args) {
  const raw = String(args.exprs !== undefined ? args.exprs : (args._ ? args._[0] : '') || '')
    .replace(/^'+|'+$/g, '').trim();
  const match = raw.match(/^val\(0\)\s*\*\s*\(\s*([0-9.]+)\s*\+\s*([0-9.]+)\s*\*\s*(sin|cos)\s*\(\s*2\s*\*\s*PI\s*\*\s*t\s*\*\s*([0-9.]+)\s*\)\s*\)$/);
  if (!match) return null;
  const floor = parseFloat(match[1]);
  const depth = parseFloat(match[2]);
  const carrier = parseFloat(match[4]);
  if (!Number.isFinite(floor) || !Number.isFinite(depth) || !Number.isFinite(carrier) || carrier <= 0) return null;
  const node = ctx.createGain();
  node.gain.value = floor;
  const lfo = ctx.createOscillator();
  lfo.frequency.value = carrier;
  const ring = ctx.createGain();
  ring.gain.value = depth;
  lfo.connect(ring);
  ring.connect(node.gain);
  lfo.start();
  return { input: node, output: node };
}

// acrusher as bit quantization through a WaveShaper. The `samples` hold (a
// sample-and-true-hold at a fraction of the rate) has no honest node without a
// worklet, so a unit asking for one is refused whole — the glitch preset, the
// only acrusher user, is server-only anyway through its enable=. mix reads as
// the crushed blend against dry, which is how the server lane reads it.
function buildAcrusher(ctx, args) {
  const bits = parseFloat(args.bits);
  if (!Number.isFinite(bits) || bits < 1 || bits > 16) return null;
  if (parseFloat(args.samples || '1') !== 1) return null;
  const mix = args.mix === undefined ? 1 : parseFloat(args.mix);
  if (!Number.isFinite(mix) || mix < 0 || mix > 1) return null;
  const levels = Math.pow(2, bits - 1);
  const count = 2 * levels + 1;
  if (count > 65537) return null;
  const curve = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const x = (i / (count - 1)) * 2 - 1;
    curve[i] = Math.max(-1, Math.min(1, Math.round(x * levels) / levels));
  }
  const crusher = ctx.createWaveShaper();
  crusher.curve = curve;
  // Aliasing is part of what acrusher does; oversampling would clean away the
  // sound the preset asked for.
  crusher.oversample = 'none';
  const input = ctx.createGain();
  const output = ctx.createGain();
  const wet = ctx.createGain();
  wet.gain.value = mix;
  const dry = ctx.createGain();
  dry.gain.value = 1 - mix;
  input.connect(crusher);
  crusher.connect(wet);
  wet.connect(output);
  input.connect(dry);
  dry.connect(output);
  return { input, output };
}

// The asetrate/aresample/atempo idiom as one pitch shifter: two delay taps
// swept in opposite phase by one sawtooth, crossfaded at constant power
// (sin^2 + cos^2 = 1). The sweep is the FM the shifter lives on — the delay
// line's slope sets the ratio exactly, the same arithmetic the idiom writes
// with resampler clocks. An approximation in texture, not in ratio: ffmpeg's
// resampler and this crossfade disagree about artifacts, not about pitch.
const PITCH_SHIFT_RATE = 6;
function buildPitchShift(ctx, ratio) {
  if (!Number.isFinite(ratio) || ratio <= 0) return null;
  if (Math.abs(ratio - 1) < 1e-6) {
    const unity = ctx.createGain();
    return { input: unity, output: unity };
  }
  const sweep = (1 - ratio) / PITCH_SHIFT_RATE;
  const base = Math.abs(sweep) + 0.004;
  const maxDelay = base + Math.abs(sweep) + 0.002;
  const input = ctx.createGain();
  const output = ctx.createGain();
  const saw = ctx.createOscillator();
  saw.type = 'sawtooth';
  saw.frequency.value = PITCH_SHIFT_RATE;
  const sweepGain = ctx.createGain();
  sweepGain.gain.value = sweep;
  saw.connect(sweepGain);
  const tap1 = ctx.createDelay(maxDelay);
  tap1.delayTime.value = base;
  sweepGain.connect(tap1.delayTime);
  // The second tap runs half a phase later, so its wrap lands where the first
  // tap's window is at full weight, and the two never click.
  const halfPhase = ctx.createDelay(0.1);
  halfPhase.delayTime.value = 0.5 / PITCH_SHIFT_RATE;
  sweepGain.connect(halfPhase);
  const tap2 = ctx.createDelay(maxDelay);
  tap2.delayTime.value = base;
  halfPhase.connect(tap2.delayTime);
  // Windows off the same saw: tap 1 fades by sin^2 of the phase, tap 2 by
  // cos^2 — zero exactly at each tap's own wrap, constant power in between.
  const points = 1024;
  const win1 = ctx.createWaveShaper();
  const win2 = ctx.createWaveShaper();
  const curve1 = new Float32Array(points);
  const curve2 = new Float32Array(points);
  for (let i = 0; i < points; i++) {
    const phase = (i / (points - 1)) * 2;
    curve1[i] = Math.pow(Math.sin(Math.PI * phase), 2);
    curve2[i] = Math.pow(Math.cos(Math.PI * phase), 2);
  }
  win1.curve = curve1;
  win2.curve = curve2;
  saw.connect(win1);
  saw.connect(win2);
  const wet1 = ctx.createGain();
  const wet2 = ctx.createGain();
  win1.connect(wet1.gain);
  win2.connect(wet2.gain);
  input.connect(tap1);
  tap1.connect(wet1);
  wet1.connect(output);
  input.connect(tap2);
  tap2.connect(wet2);
  wet2.connect(output);
  saw.start();
  return { input, output };
}

// The idiom must be exactly asetrate=R, aresample=S, atempo=T — contiguous,
// and with atempo closing the arithmetic (T ~= S/R, the duration the asetrate
// spent). Anything looser is refused whole: a rate change the node guessed at
// would be the preset's pitch drifting from what the server speaks.
function buildPitchIdiom(ctx, filters, index) {
  if (index + 2 >= filters.length) return null;
  const rate = filters[index].match(/^asetrate=([0-9.]+)$/);
  const sampleRate = filters[index + 1].match(/^aresample=([0-9.]+)$/);
  const tempo = filters[index + 2].match(/^atempo=([0-9.]+)$/);
  if (!rate || !sampleRate || !tempo) return null;
  const up = parseFloat(rate[1]);
  const base = parseFloat(sampleRate[1]);
  const restore = parseFloat(tempo[1]);
  if (!(up > 0) || !(base > 0) || !(restore > 0)) return null;
  const ratio = up / base;
  if (Math.abs(restore - 1 / ratio) > 0.001 * Math.max(1, 1 / ratio)) return null;
  return buildPitchShift(ctx, ratio);
}

function buildChainNode(ctx, name, args) {
  // A filter with a timeline (enable=) has no honest node; the whole unit is
  // skipped by the caller.
  if (args.enable !== undefined) return null;
  if (name === 'equalizer') {
    const node = ctx.createBiquadFilter();
    node.type = args.t === 'h' ? 'highshelf' : 'peaking';
    node.frequency.value = parseFloat(args.f) || 1000;
    node.Q.value = parseFloat(args.w) || 1;
    node.gain.value = parseFloat(args.g) || 0;
    return { input: node, output: node };
  }
  if (name === 'allpass') {
    const node = ctx.createBiquadFilter();
    node.type = 'allpass';
    node.frequency.value = parseFloat(args.f) || 1000;
    node.Q.value = parseFloat(args.w) || 0.7;
    return { input: node, output: node };
  }
  if (name === 'tremolo' || name === 'apulsator') {
    // Gain swings between 1 - depth and 1, the law ffmpeg and dilla share.
    const depth = parseFloat(name === 'tremolo' ? args.d : args.amount) || 0.5;
    const node = ctx.createGain();
    node.gain.value = 1 - depth / 2;
    const lfo = ctx.createOscillator();
    lfo.frequency.value = parseFloat(name === 'tremolo' ? args.f : args.hz) || 5;
    const swing = ctx.createGain();
    swing.gain.value = depth / 2;
    lfo.connect(swing);
    swing.connect(node.gain);
    lfo.start();
    return { input: node, output: node };
  }
  if (name === 'vibrato') {
    // Pitch deviation d percent at f hertz is a delay swept by d/100/(2*pi*f) seconds.
    const f = parseFloat(args.f) || 5;
    const swing = (parseFloat(args.d) || 0.5) / 100 / (2 * Math.PI * f);
    const delay = ctx.createDelay(0.1);
    delay.delayTime.value = swing * 2 + 0.001;
    const lfo = ctx.createOscillator();
    lfo.frequency.value = f;
    const depth = ctx.createGain();
    depth.gain.value = swing;
    lfo.connect(depth);
    depth.connect(delay.delayTime);
    lfo.start();
    return { input: delay, output: delay };
  }
  if (name === 'aecho') {
    // Feed-forward taps, which is what aecho is: in_gain dry, out_gain overall.
    const [inGain, outGain] = [parseFloat(args._[0]), parseFloat(args._[1])];
    const delays = String(args._[2] || '').split('|').map(parseFloat);
    const decays = String(args._[3] || '').split('|').map(parseFloat);
    const input = ctx.createGain();
    const output = ctx.createGain();
    output.gain.value = Number.isFinite(outGain) ? outGain : 1;
    const dry = ctx.createGain();
    dry.gain.value = Number.isFinite(inGain) ? inGain : 1;
    input.connect(dry);
    dry.connect(output);
    delays.forEach((ms, i) => {
      const tap = ctx.createDelay(4);
      tap.delayTime.value = (ms || 0) / 1000;
      const level = ctx.createGain();
      level.gain.value = Number.isFinite(decays[i]) ? decays[i] : 0.5;
      input.connect(tap);
      tap.connect(level);
      level.connect(output);
    });
    return { input, output };
  }
  if (name === 'asoftclip') {
    const kind = args.type || 'tanh';
    const param = parseFloat(args.param) || 1;
    if (kind !== 'tanh' && kind !== 'atan') return null;
    const curve = new Float32Array(2049);
    for (let i = 0; i < curve.length; i++) {
      const x = (i / 1024) - 1;
      curve[i] = kind === 'tanh' ? Math.tanh(x * param) : (2 / Math.PI) * Math.atan(x * param);
    }
    const node = ctx.createWaveShaper();
    node.curve = curve;
    node.oversample = '4x';
    return { input: node, output: node };
  }
  if (name === 'dcshift') {
    const input = ctx.createGain();
    const source = ctx.createConstantSource();
    source.offset.value = parseFloat(args.shift) || 0;
    source.connect(input);
    source.start();
    return { input, output: input };
  }
  if (name === 'highpass' || name === 'lowpass') {
    const node = ctx.createBiquadFilter();
    node.type = name;
    node.frequency.value = parseFloat(args.f) || (name === 'highpass' ? 200 : 6000);
    return { input: node, output: node };
  }
  if (name === 'volume') {
    const node = ctx.createGain();
    node.gain.value = dbToGain(args.volume || args._[0] || '0dB');
    return { input: node, output: node };
  }
  if (name === 'alimiter') {
    // WebAudio has no limiter, and a compressor with a hard ratio just above
    // the ceiling is the nearest honest thing. The knee is zero so it catches
    // peaks rather than shaping everything under them.
    const node = ctx.createDynamicsCompressor();
    const limit = parseFloat(args.limit) || 0.98;
    node.threshold.value = 20 * Math.log10(limit) - 1;
    node.knee.value = 0;
    node.ratio.value = 20;
    node.attack.value = 0.002;
    node.release.value = 0.08;
    return { input: node, output: node };
  }
  if (name === 'acompressor') {
    // ffmpeg writes the threshold in dB or as a linear level, attack and
    // release in milliseconds, and makeup as a linear gain; WebAudio wants dB
    // and seconds. makeup rides a gain node after the compressor.
    const node = ctx.createDynamicsCompressor();
    const threshold = String(args.threshold || '0.125');
    node.threshold.value = /db$/i.test(threshold) ? parseFloat(threshold) : 20 * Math.log10(parseFloat(threshold) || 0.125);
    node.ratio.value = parseFloat(args.ratio) || 2;
    node.attack.value = (parseFloat(args.attack) || 20) / 1000;
    node.release.value = (parseFloat(args.release) || 250) / 1000;
    const makeup = parseFloat(args.makeup) || 1;
    if (makeup === 1) return { input: node, output: node };
    const gain = ctx.createGain();
    gain.gain.value = makeup;
    node.connect(gain);
    return { input: node, output: gain };
  }
  if (name === 'chorus') return buildChorus(ctx, args);
  if (name === 'aphaser') return buildPhaser(ctx, args);
  if (name === 'aeval') return buildAeval(ctx, args);
  if (name === 'acrusher') return buildAcrusher(ctx, args);
  if (name === 'aformat') {
    // sample_rates alone pins the working rate, which a time-domain graph
    // already satisfies at its own clock — an exact passthrough. Any other
    // aformat dimension (channels, layouts, sample formats) has no node.
    const keys = Object.keys(args).filter((key) => key !== '_');
    if (keys.length !== 1 || keys[0] !== 'sample_rates') return null;
    const node = ctx.createGain();
    return { input: node, output: node };
  }
  if (name === 'adelay') {
    // One delay per channel in milliseconds; the voice arrives mono here, so
    // the first entry carries the unit.
    const ms = String(args._[0] || '').split('|').map(parseFloat).find(Number.isFinite);
    if (!Number.isFinite(ms) || ms < 0) return null;
    const node = ctx.createDelay(2);
    node.delayTime.value = Math.min(ms, 2000) / 1000;
    return { input: node, output: node };
  }
  return null;
}

function buildVoiceChain(ctx, chainText) {
  const stages = [];
  const skipped = [];
  String(chainText || '').split(',').map((part) => part.trim()).filter(Boolean).forEach((filter) => {
    const eq = filter.indexOf('=');
    const name = eq > 0 ? filter.slice(0, eq) : filter;
    const built = buildChainNode(ctx, name, parseFilterArgs(eq > 0 ? filter.slice(eq + 1) : ''));
    if (built) stages.push(built);
    else skipped.push(name);
  });
  if (skipped.length) console.info('voice chain: no node for', skipped.join(', '));
  if (!stages.length) return null;
  stages.forEach((stage, i) => { if (i) stages[i - 1].output.connect(stage.input); });
  return { input: stages[0].input, output: stages[stages.length - 1].output, stages: stages.length, skipped };
}

// dilla's rack and the character presets (voice.yml dilla_fx, character), from
// the same filter strings the server hands ffmpeg. A unit is built only when
// every filter in it has a node: a unit with one filter missing would sound
// like neither the server nor the unit, so it is skipped whole and named once.
// What the page still cannot build: pan and extrastereo (the stereo units),
// afreqshift, aphaseshift, volume with a timeline (delay_throw) and the
// glitch's enable=. Those only the server chain applies. The rate idiom
// (asetrate, aresample, atempo), aeval ring-mod shapes, acrusher bits,
// aformat sample_rates and adelay gained nodes 2026-10-27, so the character
// presets robot, formant, doubler, shimmer, ionosphere, midnight and shortwave
// now build here exactly as the server speaks them (see
// MASTER/data/ideations/master_web_face_voice.yml).
function splitTop(text, sep) {
  const parts = [];
  let current = '';
  let quote = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '\\') { current += ch + (text[i + 1] || ''); i++; continue; }
    if (ch === "'") quote = !quote;
    if (ch === sep && !quote) { parts.push(current); current = ''; } else current += ch;
  }
  if (current.length) parts.push(current);
  return parts;
}

function buildFilterRun(ctx, filters) {
  const nodes = [];
  for (let i = 0; i < filters.length;) {
    const eq = filters[i].indexOf('=');
    const name = eq > 0 ? filters[i].slice(0, eq) : filters[i];
    // The rate idiom is read before buildChainNode ever sees a rate filter:
    // the triple becomes one pitch shifter, and a stray asetrate, aresample or
    // atempo outside the recognized shape refuses the whole run.
    if (name === 'asetrate' || name === 'aresample' || name === 'atempo') {
      const shifter = buildPitchIdiom(ctx, filters, i);
      if (!shifter) return null;
      nodes.push(shifter);
      i += 3;
      continue;
    }
    const built = buildChainNode(ctx, name, parseFilterArgs(eq > 0 ? filters[i].slice(eq + 1) : ''));
    if (!built) return null;
    nodes.push(built);
    i += 1;
  }
  nodes.forEach((node, i) => { if (i) nodes[i - 1].output.connect(node.input); });
  return nodes;
}

function buildFxUnit(ctx, filterText) {
  const input = ctx.createGain();
  const labels = {};
  let previous = input;
  for (const segment of splitTop(String(filterText), ';')) {
    const match = segment.match(/^((?:\[[^\]]+\])*)(.*?)((?:\[[^\]]+\])*)$/);
    const ins = (match[1].match(/\[([^\]]+)\]/g) || []).map((label) => label.slice(1, -1));
    const outs = (match[3].match(/\[([^\]]+)\]/g) || []).map((label) => label.slice(1, -1));
    const filters = splitTop(match[2], ',');
    const head = filters[0].split('=')[0];
    let current;
    if (head === 'asplit') {
      const source = ins.length ? labels[ins[0]] : previous;
      if (!source) return null;
      outs.forEach((label) => { const tap = ctx.createGain(); source.connect(tap); labels[label] = tap; });
      previous = null;
      continue;
    } else if (head === 'amix') {
      const weights = (parseFilterArgs(filters[0].slice(5)).weights || '').split(' ').map(parseFloat);
      current = ctx.createGain();
      for (let i = 0; i < ins.length; i++) {
        const source = labels[ins[i]];
        if (!source) return null;
        const weight = ctx.createGain();
        weight.gain.value = Number.isFinite(weights[i]) ? weights[i] : 1;
        source.connect(weight);
        weight.connect(current);
      }
      const rest = filters.slice(1);
      if (rest.length) {
        const run = buildFilterRun(ctx, rest);
        if (!run) return null;
        current.connect(run[0].input);
        current = run[run.length - 1].output;
      }
    } else {
      const source = ins.length ? labels[ins[0]] : previous;
      const run = buildFilterRun(ctx, filters);
      if (!source || !run) return null;
      source.connect(run[0].input);
      current = run[run.length - 1].output;
    }
    if (outs.length) labels[outs[0]] = current;
    previous = current;
  }
  return previous ? { input, output: previous } : null;
}

function gainNode(ctx, db) {
  const node = ctx.createGain();
  node.gain.value = Math.pow(10, (Number(db) || 0) / 20);
  return { input: node, output: node };
}

// Returns { head, tail, built, skipped }. head is input trim, character
// presets and the mono units with their stage trims; tail is the stereo units'
// slot (none are buildable), the final trim and the ceiling limiter. Null when
// the server declares no rack.
function buildFxRack(ctx, fx, characters) {
  const wanted = [];
  if (fx?.enabled) {
    wanted.push({ id: 'in_db', node: gainNode(ctx, fx.in_db) });
  }
  const built = [];
  const skipped = [];
  const place = (id, filter) => {
    const unit = buildFxUnit(ctx, filter);
    if (unit) { wanted.push({ id, node: unit }); built.push(id); } else skipped.push(id);
  };
  if (fx?.enabled) {
    const mono = (fx.units || []).filter((unit) => (unit.region || 'mono') === 'mono');
    mono.forEach((unit, i) => {
      place(unit.id, unit.filter);
      const next = mono[i + 1];
      const trim = (fx.stage_trim_db || {})[unit.stage];
      if ((!next || next.stage !== unit.stage) && trim) wanted.push({ id: `trim:${unit.stage}`, node: gainNode(ctx, trim) });
    });
    (fx.units || []).filter((unit) => unit.region === 'stereo').forEach((unit) => skipped.push(unit.id));
  }
  (characters || []).forEach((row) => place(`character:${row.id}`, row.filter));
  if (!wanted.length) return null;
  const nodes = wanted.map((item) => item.node);
  nodes.forEach((node, i) => { if (i) nodes[i - 1].output.connect(node.input); });
  const tail = [];
  if (fx?.enabled) {
    tail.push(gainNode(ctx, fx.trim_db));
    const limiter = buildChainNode(ctx, 'alimiter', { limit: String(fx.ceiling || 0.85), _: [] });
    if (limiter) tail.push(limiter);
  }
  tail.forEach((node, i) => { if (i) tail[i - 1].output.connect(node.input); });
  if (skipped.length) console.info('voice rack: server only:', skipped.join(', '));
  return {
    head: { input: nodes[0].input, output: nodes[nodes.length - 1].output },
    tail: tail.length ? { input: tail[0].input, output: tail[tail.length - 1].output } : null,
    built,
    skipped,
  };
}

// The room from data/voice.yml's tts.room, as WebAudio: the dry voice plus one
// delayed, attenuated tap per early reflection, the second channel delayed by
// width_ms, and a StereoPanner that follows the head's yaw. ffmpeg builds the
// same reflections on the server (Policy#room_chain), so both lanes speak in
// one room. Returns null when the policy declares none, and the voice stays dry.
function buildRoom(ctx, room) {
  if (!room || !Array.isArray(room.reflections_ms) || !room.reflections_ms.length) return null;
  const input = ctx.createGain();
  const merger = ctx.createChannelMerger(2);
  const mono = ctx.createGain();
  mono.channelCount = 1;
  mono.channelCountMode = 'explicit';
  input.connect(mono);
  const widthDelay = ctx.createDelay(0.1);
  widthDelay.delayTime.value = (Number(room.width_ms) || 0) / 1000;
  const sum = ctx.createGain();
  const level = Math.pow(0.707, 1);
  sum.gain.value = level;
  mono.connect(sum);
  room.reflections_ms.forEach((ms, i) => {
    const tap = ctx.createDelay(0.5);
    tap.delayTime.value = ms / 1000;
    const decay = ctx.createGain();
    decay.gain.value = (room.decays?.[i] ?? 0.1);
    mono.connect(tap);
    tap.connect(decay);
    decay.connect(sum);
  });
  sum.connect(merger, 0, 0);
  sum.connect(widthDelay);
  widthDelay.connect(merger, 0, 1);
  const makeup = ctx.createGain();
  makeup.gain.value = Math.pow(10, (Number(room.gain_db) || 0) / 20) * (Number(room.out_gain) || 0.9);
  merger.connect(makeup);
  const panner = ctx.createStereoPanner();
  makeup.connect(panner);
  const pan = room.pan || {};
  const follow = pan.follow_head !== false;
  const strength = Number(pan.strength) || 0;
  const limit = Number(pan.max) || 0.5;
  // The head turns about +-0.9 rad at most; that span maps onto +-strength.
  const update = () => {
    const yaw = window.MASTER_FACE?.head?.rotation?.y || 0;
    const target = follow ? Math.max(-limit, Math.min(limit, (yaw / 0.9) * strength)) : 0;
    panner.pan.setTargetAtTime(target, ctx.currentTime, 0.08);
  };
  return { input, output: panner, update };
}

async function connectTTSAudio(audio, boostValue = 1.35) {
  if (LOW_POWER) return;
  if (!actx || actx.state === 'closed') return;
  if (actx.state === 'suspended') await actx.resume().catch(() => {});
  if (actx.state !== 'running') return;
  const msrc = actx.createMediaElementSource(audio);
  const analyser = actx.createAnalyser();
  const masterGain = actx.createGain();
  // The server's streaming path — the one TtsJob uses — hands the browser bare
  // edge-tts, because only Speech#synthesize shapes and
  // synthesize_streaming_to_file does not. So the page is where the chain gets
  // applied for the web, and it applies the declared one rather than an
  // invented one. What stood here until 2026-09-16 was a hand-built
  // warmth/smooth/presence/convolver graph nobody had declared anywhere: the
  // terminal spoke through dilla's chain and the face spoke through this, two
  // voices under one name.
  const chain = buildVoiceChain(actx, window.MASTER_VOICE_POLICY?.post_chain);
  // The chain ends in volume=23dB and a limiter, so it carries its own level
  // and masterGain is left at unity for the duck to ride. Without a chain the
  // graph is the old bare one, and 1.9 is the gain measured to fit under
  // 0 dBFS against a real /chat/tts response.
  //
  // Published on tts so face_audio_bridge duck-restores to the live value;
  // TTS_PLAYBACK_GAIN there is the fallback when it is not.
  const masterGainValue = chain ? 1.0 : 1.9;
  masterGain.gain.value = masterGainValue;
  tts.playbackGain = masterGainValue;
  analyser.fftSize = 256;
  analyser.smoothingTimeConstant = 0.72;
  const room = chain ? buildRoom(actx, window.MASTER_VOICE_POLICY?.room) : null;
  const rack = chain ? buildFxRack(actx, window.MASTER_VOICE_POLICY?.dilla_fx, window.MASTER_VOICE_POLICY?.character) : null;
  if (tts.panTimer) { clearInterval(tts.panTimer); tts.panTimer = null; }
  if (chain) {
    // source -> post_chain -> rack (dilla units, character) -> room -> rack tail -> master
    msrc.connect(chain.input);
    let tailOf = chain.output;
    if (rack) { tailOf.connect(rack.head.input); tailOf = rack.head.output; }
    if (room) {
      tailOf.connect(room.input);
      tailOf = room.output;
      room.update();
      tts.panTimer = setInterval(room.update, 60);
    }
    if (rack?.tail) { tailOf.connect(rack.tail.input); tailOf = rack.tail.output; }
    tailOf.connect(masterGain);
  } else {
    const boost = actx.createGain();

    boost.gain.value = boostValue;
    msrc.connect(boost);
    boost.connect(masterGain);
  }
  masterGain.connect(analyser);
  analyser.connect(actx.destination);
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
  tts.endedAt = performance.now();
  if (tts.panTimer) { clearInterval(tts.panTimer); tts.panTimer = null; }
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
  tts.performancePlan = null;
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
  const decorated = _quirkifyTts(clean, opts);
  const _v = speechVoiceForText(decorated);
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
  tts.queue.push(text);
  return true;
}
function scheduleTtsTick(delay) {
  if (tts.retryTimer) clearTimeout(tts.retryTimer);
  tts.retryTimer = setTimeout(() => { tts.retryTimer = null; ttsTick(); }, delay || 600);
}

// The browser refuses sound until the page has had a gesture, and the face now
// starts without one: no primer tap, and a visitor who only talks never
// touches the page. A refused play() used to requeue the sentence and finish,
// which retried five times in a row and dropped it, so the first reply was
// never heard. The refused element is held, the queue waits behind it, and the
// first interaction of any kind plays it. Once a page has had that gesture the
// browser lets every later reply play by itself.
const GESTURE_EVENTS = ['pointerdown', 'keydown', 'touchend', 'click'];
function holdForGesture(audio, token) {
  const hint = document.getElementById('zsh-status');
  // Written as an attribute the stylesheet prints, not as text: State.mode's
  // setter blanks this element's textContent on every mode change, and the
  // mic re-arming does exactly that while the audio waits.
  if (hint) hint.dataset.blockedLabel = window.MASTER_T ? window.MASTER_T('tap_to_hear', 'tap anywhere to hear the reply') : 'tap anywhere to hear the reply';
  rootBody.dataset.ttsBlocked = '1';
  const release = () => {
    GESTURE_EVENTS.forEach((ev) => removeEventListener(ev, release, { capture: true }));
    delete rootBody.dataset.ttsBlocked;
    if (token !== tts.cancelToken || tts.audio !== audio) return;
    if (actx?.state === 'suspended') actx.resume().catch(() => {});
    audio.play().catch((err) => {
      if (err?.name === 'NotAllowedError') holdForGesture(audio, token);
      else finishTTSPlayback(audio.src);
    });
  };
  GESTURE_EVENTS.forEach((ev) => addEventListener(ev, release, { capture: true, passive: true }));
}

function ttsTick() {
  if (tts.muted || tts.playing || tts.paused) return;
  const unavailableUntil = Number(tts.serverUnavailableUntil || 0);
  if (tts.serverUnavailable && Date.now() < unavailableUntil) {
    scheduleTtsTick(Math.max(250, unavailableUntil - Date.now()));
    return;
  }
  const text = dequeueTtsLane();
  if (!text) { resumeSttAfterSpeech(); return; }
  tts.current = text;
  tts.performancePlan = tts.meta.get(text)?.performance || null;
  tts.lang = detectLang(text);
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
  // Server TTS is the only normal speaker. The queue owns the utterance,
  // synthesis, playback, visemes, and STT ducking as one transaction. A slow
  // server must not trigger a second voice; the explicit browser emergency
  // path below is reached only after a real server failure.
  if (tts.serverUnavailable && Date.now() < (tts.serverUnavailableUntil || 0)) {
    tts.playing = false;
    tts.current = null;
    setTTSLoading(false);
    ttsTick();
    return;
  }
  if (tts.serverUnavailable) tts.serverUnavailable = false;
  const meta = tts.meta.get(text) || {};
  const voice = meta.voice || _activeTtsVoice();
  const style = meta.style;
  const edgeBlob = tts.prefetch.get(text) || loadTTSBlob(text, voice, style);
  tts.prefetch.delete(text);
  tts.meta.delete(text);
  // Browser speech is an emergency fallback after an actual server
  // failure, not a latency race. Starting it while Edge is merely still
  // synthesizing can introduce a second system voice into the same reply.
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
      const chatTiming = window.MASTER_CHAT_TIMING;
      if (meta.lane === 'response' && chatTiming && chatTiming.firstAudioMs === null) {
        chatTiming.firstAudioMs = Math.round(performance.now() - chatTiming.startedAt);
      }
      emitTtsEvent('tts:playback:start', { text, voice, style, duration: dur || audio.duration || null, backend: 'edge' });
      startVisemeAnim(text);
      if (navigator.vibrate) navigator.vibrate([35, 55, 35]);
      rootBody.dataset.ttsWave = 'true';
      preSpeechInhale(style);
    };
    audio.onended = audio.onerror = () => finishTTSPlayback(src);
    connectTTSAudio(audio).catch(() => {});
    const play = (retried = false) => audio.play().catch((err) => {
      if (err?.name === 'NotAllowedError') { holdForGesture(audio, token); return; }
      if (!retried && ['AbortError', 'NotSupportedError', 'NetworkError'].includes(err?.name)) {
        window.MASTER_LOG?.warn?.('face_speech_runtime:audio_retry', err);
        try { audio.load(); } catch (_) {}
        setTimeout(() => { if (token === tts.cancelToken && tts.audio === audio) play(true); }, 120);
        return;
      }
      requeueChunk(text); finishTTSPlayback(src);
    });
    play();
  }

  edgeBlob
    .then(blob => { if (!blob) throw new Error('empty'); playEdge(blob); })
    .catch(() => {
      tts.serverFailureCount = (tts.serverFailureCount || 0) + 1;
      tts.serverUnavailable = true;
      tts.serverUnavailableUntil = Date.now() + Math.min(30000, 5000 * tts.serverFailureCount);
      setTtsHealthStatus('tts: unavailable', 12000);
      tts.audio = null; tts.playing = false; tts.current = null; setTTSLoading(false);
      if (State.mode === 'speaking') State.mode = 'idle';
      resumeSttAfterSpeech();
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

});
window.MASTER = window.MASTER || {};
window.MASTER.speechRuntime = window.MASTER_SPEECH_RUNTIME;
