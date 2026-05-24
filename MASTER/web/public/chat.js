"use strict";

const log   = document.getElementById('chat-log');
const zsh   = document.getElementById('zsh');
const input = document.getElementById('zin');
const photoButton = document.getElementById('photo-button');
const photoInput  = document.getElementById('photo');

let _streamEl = null;
let _evtSrc = null;
let _pendingPhoto = null;

function appendMsg(role, text = '') {
  const d = document.createElement('div');
  d.className = 'message ' + role;
  const prompt = document.createElement('span');
  prompt.className = 'msg-prompt';
  prompt.textContent = role === 'user' ? 'you$ ' : 'master$ ';
  d.appendChild(prompt);
  if (role === 'user') {
    d.appendChild(document.createTextNode(text));
  } else {
    const body = document.createElement('span');
    body.className = 'msg-body';
    const cur = document.createElement('span');
    cur.className = 'cursor';
    d.appendChild(body);
    d.appendChild(cur);
    _streamEl = body;
  }
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
}

window._chatOnUser  = (text) => { appendMsg('user', text); appendMsg('assistant'); };

// Enhance confirm: show dim enhanced text + [y/n], resolve with chosen message.
window._chatConfirmEnhance = (original, enhanced) => new Promise(resolve => {
  const note = document.createElement('div');
  note.className = 'enhance-confirm';
  note.innerHTML =
    '<span class="enhance-arrow">\u2192</span> ' +
    '<span class="enhance-text">' + enhanced.replace(/</g, '&lt;') + '</span> ' +
    '<span class="enhance-yn">[y/n]</span>';
  log.appendChild(note);
  log.scrollTop = log.scrollHeight;

  function finish(chosen) {
    note.remove();
    document.removeEventListener('keydown', onKey);
    resolve(chosen);
  }

  function onKey(e) {
    if (e.key === 'y' || e.key === 'Y' || e.key === 'Enter') { e.preventDefault(); finish(enhanced); }
    else if (e.key === 'n' || e.key === 'N' || e.key === 'Escape') { e.preventDefault(); finish(original); }
  }

  document.addEventListener('keydown', onKey);
});
window._chatOnChunk = (raw) => {
  if (!_streamEl) return;
  _streamEl.textContent += raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
  log.scrollTop = log.scrollHeight;
};
window._chatOnDone  = () => { _streamEl = null; document.querySelectorAll('.cursor').forEach(c => c.remove()); };
window._chatOnError = () => { _streamEl = null; document.querySelectorAll('.cursor').forEach(c => c.remove()); };

window._chatOnDmesg = (line) => {
  if (!line) return;
  const d = document.createElement('div');
  d.className = 'dmesg-line';
  d.textContent = line;
  const asst = log.querySelector('.message.assistant:last-of-type');
  asst ? log.insertBefore(d, asst) : log.appendChild(d);
  log.scrollTop = log.scrollHeight;
  setTimeout(() => { d.classList.add('dmesg-fade'); setTimeout(() => d.remove(), 800); }, 7000);
};

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

function setPhotoState(state, text) {
  if (!photoButton) return;
  photoButton.dataset.state = state;
  photoButton.textContent = text;
}

async function uploadPhoto(file) {
  const form = new FormData();
  form.append('photo', file);
  setPhotoState('busy', '…');
  const response = await fetch('/chat/photo', {
    method: 'POST',
    headers: { 'X-CSRF-Token': csrfToken() },
    credentials: 'same-origin',
    body: form
  });
  if (!response.ok) throw new Error(`photo upload failed: ${response.status}`);
  _pendingPhoto = await response.json();
  setPhotoState(_pendingPhoto.processed ? 'ready' : 'raw', '1');
}

async function enhanceMessage(text) {
  try {
    const r = await fetch(`/chat/enhance?message=${encodeURIComponent(text)}`);
    const data = await r.json();
    if (data.changed && data.enhanced && data.enhanced !== text) {
      const chosen = await (window._chatConfirmEnhance?.(text, data.enhanced) ?? Promise.resolve(text));
      return { text: chosen, preEnhanced: chosen === data.enhanced };
    }
  } catch (_) {}
  return { text, preEnhanced: false };
}

async function sendMessageWithPhoto(text) {
  if (_evtSrc) { try { _evtSrc.close(); } catch (_) {} }
  window._chatOnUser?.(text);

  const enhanced = await enhanceMessage(text);
  const params = new URLSearchParams({ message: enhanced.text, state: 'idle|thinking|0|0' });
  if (enhanced.preEnhanced) params.set('pre_enhanced', '1');
  if (_pendingPhoto?.token) params.set('image_token', _pendingPhoto.token);

  _pendingPhoto = null;
  if (photoInput) photoInput.value = '';
  setPhotoState('idle', '+');

  _evtSrc = new EventSource(`/chat/message?${params.toString()}`);
  _evtSrc.onmessage = (ev) => {
    const raw = ev.data || '';
    if (raw === '[DONE]') {
      try { _evtSrc.close(); } catch (_) {}
      window._chatOnDone?.();
      return;
    }
    if (raw.startsWith('ERROR:')) {
      window._chatOnChunk?.('\n' + raw + '\n');
      window._chatOnError?.();
      return;
    }
    window._chatOnChunk?.(raw);
  };
  _evtSrc.addEventListener('dmesg', (ev) => {
    try { window._chatOnDmesg?.(JSON.parse(ev.data)); } catch (_) {}
  });
  _evtSrc.onerror = () => {
    try { _evtSrc.close(); } catch (_) {}
    window._chatOnError?.();
  };
}

photoButton?.addEventListener('click', () => photoInput?.click());
photoInput?.addEventListener('change', async () => {
  const file = photoInput.files && photoInput.files[0];
  if (!file) return;
  try {
    await uploadPhoto(file);
  } catch (err) {
    setPhotoState('idle', '+');
    appendMsg('assistant', `photo upload failed: ${err.message}`);
    window._chatOnDone?.();
  }
});

zsh?.addEventListener('submit', (event) => {
  event.preventDefault();
  event.stopImmediatePropagation();
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  sendMessageWithPhoto(text);
}, true);

(function applyTier() {
  const tier = document.querySelector('meta[name=master-tier]')?.content || 'visitor';
  const pp = document.querySelector('#zsh .pp');
  if (pp) pp.textContent = tier === 'authenticated' ? 'dev' : 'visitor';
})();

setPhotoState('idle', '+');
