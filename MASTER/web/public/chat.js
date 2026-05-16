// chat.js — primer, panel, input, message stream, server TTS
"use strict";

const panel  = document.getElementById('chat-panel');
const log    = document.getElementById('chat-log');
const zsh    = document.getElementById('zsh');
const input  = document.getElementById('zin');
const primer = document.getElementById('primer');

// AudioContext — must be created inside a user gesture on mobile
let _actx = null;
function getACtx() {
  if (!_actx) _actx = new (window.AudioContext || window.webkitAudioContext)();
  if (_actx.state === 'suspended') _actx.resume();
  return _actx;
}

// Panel open/close
function panelOpen() {
  panel.classList.add('open');
  setTimeout(() => input.focus(), 360);
}
function panelClose() {
  panel.classList.remove('open');
  input.blur();
}

// Primer dismiss — first touch unlocks audio + opens panel
primer.addEventListener('pointerdown', () => {
  getACtx();
  if (typeof unlockTTS === 'function') unlockTTS();
  primer.classList.add('gone');
  zsh.classList.add('live');
  panelOpen();
}, { once: true });

// Swipe overrides (gestures.js defines handleSwipe globally)
const _origSwipe = window.handleSwipe;
window.handleSwipe = (dx, dy) => {
  const ax = Math.abs(dx), ay = Math.abs(dy);
  if (ay <= ax) {
    if (dx > 0) { panelOpen(); return; }
    if (dx < 0 && panel.classList.contains('open')) { panelClose(); return; }
  }
  if (typeof _origSwipe === 'function') _origSwipe(dx, dy);
};

// Close panel when tapping the canvas
document.getElementById('face')?.addEventListener('pointerdown', (e) => {
  if (!panel.classList.contains('open')) return;
  if (!panel.contains(e.target)) panelClose();
}, { passive: true });

// Message log
let _streamEl = null;

function appendMsg(role, text = '') {
  const d = document.createElement('div');
  d.className = 'message ' + role;
  if (role === 'user') {
    const prompt = document.createElement('span');
    prompt.className = 'msg-prompt';
    prompt.textContent = 'you$ ';
    d.appendChild(prompt);
    d.appendChild(document.createTextNode(text));
  } else {
    const prompt = document.createElement('span');
    prompt.className = 'msg-prompt assistant-prompt';
    prompt.textContent = 'master$ ';
    d.appendChild(prompt);
    const body = document.createElement('span');
    body.className = 'msg-body';
    d.appendChild(body);
    const cur = document.createElement('span');
    cur.className = 'cursor';
    d.appendChild(cur);
    _streamEl = body;
  }
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
  return d;
}

// SSE chunk hook — sse.js calls window._chatOnChunk(raw) per token
window._chatOnChunk = (raw) => {
  if (!_streamEl) return;
  _streamEl.textContent += raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
  log.scrollTop = log.scrollHeight;
};
window._chatOnDone = () => {
  _streamEl = null;
  document.querySelectorAll('.cursor').forEach(c => c.remove());
};
window._chatOnError = () => {
  _streamEl = null;
  document.querySelectorAll('.cursor').forEach(c => c.remove());
};

// Input submit
input.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter') return;
  const text = input.value.trim();
  if (!text) return;
  e.preventDefault();
  input.value = '';
  appendMsg('user', text);
  appendMsg('assistant');
  if (typeof sendMessage === 'function') sendMessage(text);
});

// Tier label from meta or URL
(function applyTier() {
  const tier = document.querySelector('meta[name=master-tier]')?.content
    || (location.search.includes('token=') ? 'authenticated' : 'visitor');
  const pp = document.querySelector('#zsh .pp');
  if (pp) pp.textContent = tier === 'authenticated' ? 'dev' : 'visitor';
  const sub = document.getElementById('banner-sub');
  if (sub && tier !== 'authenticated') sub.textContent = 'visitor session · limited tools';
})();
