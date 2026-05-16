// tts.js — server-side edge-tts via /chat/tts, AudioContext playback
"use strict";

const tts = {
  enabled: true, muted: false,
  queue: [], model: '', mood: 'idle', unlocked: false, currentUtt: null,
  playing: false
};
const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;

// Shared AudioContext — created on first user gesture (primer click)
let _ttsActx = null;
function _getTtsActx() {
  if (!_ttsActx) _ttsActx = new (window.AudioContext || window.webkitAudioContext)();
  if (_ttsActx.state === 'suspended') _ttsActx.resume();
  return _ttsActx;
}

function pickVoice() {
  if (!tts.enabled) return;
  const v = speechSynthesis.getVoices();
  if (!v.length) return;
  const en = v.filter(x => /en[-_]/i.test(x.lang));
  tts.voice = en.find(x => /Google.*US|Samantha|Daniel|Karen|Alex/i.test(x.name)) || en[0] || v[0];
}
if (tts.enabled) {
  speechSynthesis.onvoiceschanged = pickVoice;
  pickVoice();
}

const MODEL_TIMBRE = {
  deepseek: { rate: 0.96, pitch: 0.92 }, claude: { rate: 1.00, pitch: 1.00 },
  gemini: { rate: 1.05, pitch: 1.08 }, gpt: { rate: 0.98, pitch: 1.04 }
};
const MOOD_PROSODY = {
  focused: { rate: 1.00, pitch: 0.98 }, curious: { rate: 1.10, pitch: 1.12 },
  tense: { rate: 1.15, pitch: 1.05 }, weary: { rate: 0.88, pitch: 0.92 }, idle: { rate: 1.00, pitch: 1.00 }
};

function ttsParams() {
  const m = (tts.model || '').toLowerCase();
  const tb = Object.entries(MODEL_TIMBRE).find(([k]) => m.includes(k));
  const t = tb ? tb[1] : { rate: 1.0, pitch: 1.0 };
  const p = MOOD_PROSODY[tts.mood] || MOOD_PROSODY.idle;
  return { rate: t.rate * p.rate, pitch: t.pitch * p.pitch };
}

function unlockTTS() {
  if (tts.unlocked) return;
  _getTtsActx();
  tts.unlocked = true;
}

function enqueueSpeech(text) {
  if (tts.muted) return;
  const clean = text.replace(/```[\s\S]*?```/g, '').replace(/[*_`~]/g, '').trim();
  if (!clean) return;
  tts.queue.push(clean);
  ttsTick();
}

function ttsTick() {
  if (tts.muted || tts.playing || !tts.queue.length) return;
  const text = tts.queue.shift();
  tts.playing = true;
  const tok = new URLSearchParams(location.search).get('token') || '';
  const url = `/chat/tts?text=${encodeURIComponent(text)}&voice=osman&style=auto`
    + (tok ? `&token=${encodeURIComponent(tok)}` : '');
  fetch(url)
    .then(r => r.ok ? r.arrayBuffer() : Promise.reject(r.status))
    .then(buf => {
      const ac = _getTtsActx();
      return ac.decodeAudioData(buf).then(decoded => {
        duck(true);
        State.mode = 'speaking';
        const src = ac.createBufferSource();
        src.buffer = decoded;
        src.connect(ac.destination);
        tts.currentUtt = src;
        src.onended = () => {
          tts.currentUtt = null; tts.playing = false;
          duck(false); setMouth('neutral');
          if (State.mode === 'speaking') State.mode = 'idle';
          ttsTick();
        };
        src.start();
      });
    })
    .catch(() => { tts.playing = false; ttsTick(); });
}

function ttsSkip() {
  tts.queue.length = 0;
  if (tts.currentUtt && tts.currentUtt.stop) try { tts.currentUtt.stop(); } catch (_) {}
  tts.currentUtt = null; tts.playing = false;
  duck(false); setMouth('neutral');
}

function ttsToggleMute() {
  tts.muted = !tts.muted;
  if (tts.muted) ttsSkip();
  Face.coronaFlash = tts.muted ? 0.6 : 0.3;
}

function driveViseme(text, idx) {
  const c = (text[idx] || '').toLowerCase();
  if ('aeiou'.indexOf(c) >= 0) setMouth(c.toUpperCase());
  else if ('mbpfwv'.indexOf(c) >= 0) setMouth('M');
  else if (c === ' ' || c === '.') setMouth('neutral');
  else setMouth('E');
}

function setMouth(shape) {
  if (Face.mouth === shape) return;
  Face.mouth = shape;
  const cx = Face.cx, cy = Face.cy, s = Face.s;
  let m = mouthArc(cx, cy + s * 0.92, s * 0.7, shape, 30);
  for (let i = 0; i < 7; i++) {
    const tx = cx - s * 0.32 + i * (s * 0.64 / 6);
    m.push({ x: tx, y: cy + s * 0.88, zone: 'mouth' });
    m.push({ x: tx, y: cy + s * 0.96, zone: 'mouth' });
  }
  Face.zones.mouth = m;
  Face.anchors = [].concat(...Object.values(Face.zones));
  assignHomes();
}

function whisper(text) {
  if (!tts.enabled || tts.muted || !text) return;
  const u = new SpeechSynthesisUtterance(text);
  u.rate = 1.1; u.pitch = 0.86; u.volume = 0.45;
  if (tts.voice) u.voice = tts.voice;
  tts.queue.push(u); ttsTick();
}
