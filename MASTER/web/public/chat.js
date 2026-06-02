"use strict";

const log   = document.getElementById('chat-log');
const zsh   = document.getElementById('zsh');
const input = document.getElementById('zin');

let _streamEl = null;
let _evtSrc = null;

window._chatCancel = () => {
  if (_evtSrc) { try { _evtSrc.close(); } catch (_) {} _evtSrc = null; }
  window._chatOnError?.();
};

function appendMsg(role, text = '') {
  const d = document.createElement('div');
  d.className = 'message ' + role;
  const now = new Date();
  d.dataset.ts = now.getHours().toString().padStart(2,'0') + ':' + now.getMinutes().toString().padStart(2,'0');
  if (role === 'assistant') {
    const conf = parseFloat(document.body.dataset.confidence || '1');
    d.style.setProperty('--conf-alpha', (0.08 + conf * 0.3).toFixed(2));
  }
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
  const text = _streamEl.textContent + raw.replace(/\n/g, '\n').replace(/\\/g, '\');
  if (text.includes('```')) {
    _streamEl.innerHTML = text.replace(/```([^`]*?)```/gs, '<pre><code>$1</code></pre>').replace(/\n/g, '<br>');
  } else {
    _streamEl.textContent = text;
  }
  log.scrollTop = log.scrollHeight;
};
window._chatOnDone  = () => { _streamEl = null; document.querySelectorAll('.cursor').forEach(c => { c.style.transition = 'opacity 0.25s steps(4,end)'; c.style.opacity = '0'; setTimeout(() => c.remove(), 280); }); };
window._chatOnError = () => { _streamEl = null; document.querySelectorAll('.cursor').forEach(c => c.remove()); };

window._chatOnDmesg = (line) => {
  if (!line) return;
  const d = document.createElement('div');
  d.className = 'dmesg-line';
  d.style.opacity = '0.25';
  d.textContent = line;
  const asst = log.querySelector('.message.assistant:last-of-type');
  asst ? log.insertBefore(d, asst) : log.appendChild(d);
  log.scrollTop = log.scrollHeight;
  requestAnimationFrame(() => { d.style.transition = 'opacity 0.18s steps(3,end)'; d.style.opacity = '1'; });
  setTimeout(() => { d.classList.add('dmesg-fade'); setTimeout(() => d.remove(), 800); }, 7000);
};

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || '';
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

async function sendMessage(text) {
  if (_evtSrc) { try { _evtSrc.close(); } catch (_) {} }
  window._chatOnUser?.(text);

  const enhanced = await enhanceMessage(text);
  const params = new URLSearchParams({ message: enhanced.text, state: 'idle|thinking|0|0' });
  if (enhanced.preEnhanced) params.set('pre_enhanced', '1');

  const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;
  let assistantBuffer = '', ttsBuffer = '';
  _evtSrc = new EventSource(`/chat/message?${params.toString()}`);
  _evtSrc.onmessage = (ev) => {
    const raw = ev.data || '';
    if (raw === '[DONE]') {
      const voice = window.MASTERVoice;
      if (voice?.setLastText) voice.setLastText(assistantBuffer);
      if (voice?.enqueue && ttsBuffer.trim()) voice.enqueue(ttsBuffer.trim());
      ttsBuffer = '';
      try { _evtSrc.close(); } catch (_) {}
      window._chatOnDone?.();
      return;
    }
    if (raw.startsWith('ERROR:')) {
      window._chatOnChunk?.('\n' + raw + '\n');
      window._chatOnError?.();
      return;
    }
    const chunk = raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
    assistantBuffer += chunk;
    ttsBuffer += chunk;
    window._chatOnChunk?.(raw);
    let m;
    while ((m = ttsBuffer.match(SENT_BREAK))) {
      const cut = m.index + m[0].length;
      const sent = ttsBuffer.slice(0, cut).trim();
      ttsBuffer = ttsBuffer.slice(cut);
      if (sent) window.MASTERVoice?.enqueue?.(sent);
    }
  };
  _evtSrc.addEventListener('dmesg', (ev) => {
    try { window._chatOnDmesg?.(JSON.parse(ev.data)); } catch (_) {}
  });
  _evtSrc.onerror = () => {
    try { _evtSrc.close(); } catch (_) {}
    window._chatOnError?.();
  };
}

zsh?.addEventListener('submit', (event) => {
  event.preventDefault();
  event.stopImmediatePropagation();
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  sendMessage(text);
}, true);
