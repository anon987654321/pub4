"use strict";

const log   = document.getElementById('chat-log');
const zsh   = document.getElementById('zsh');
const input = document.getElementById('zin');

let _streamEl = null;
let _evtSrc = null;

// ARIA live region for streamed text (FA137) — announce new tokens to SR
const streamLive = (() => {
  let el = document.getElementById('stream-live');
  if (!el) {
    el = document.createElement('div');
    el.id = 'stream-live';
    el.className = 'sr-only';
    el.setAttribute('aria-live', 'polite');
    el.setAttribute('aria-atomic', 'false');
    document.body.appendChild(el);
  }
  return el;
})();

window._chatCancel = () => {
  if (_evtSrc) { try { _evtSrc.close(); } catch (_) {} _evtSrc = null; }
  window._chatOnError?.();
};

function appendMsg(role, text = '') {
  const d = document.createElement('div');
  d.className = 'message ' + role;
  d.tabIndex = 0;
  d.setAttribute('role', 'article');
  d.setAttribute('aria-label', role + ' message');
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
    const copyBtn = document.createElement(button);
    copyBtn.className = msg-copy;
    copyBtn.title = Copy;
    copyBtn.setAttribute(aria-label, Copy response);
    copyBtn.addEventListener(click, () => {
      navigator.clipboard?.writeText(body.textContent || ).then(() => {
        copyBtn.textContent = u2713;
        setTimeout(() => { copyBtn.textContent = ; }, 1200);
      });
    });
    d.appendChild(body);
    d.appendChild(cur);
    d.appendChild(copyBtn);
    _streamEl = body;
  }
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
  d.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      openActionMenu(d);
    }
  });
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
  const text = _streamEl.textContent + raw.replace(/\n/g, '\n').replace(/\\\\/g, '\\');
  if (text.includes('```')) {
    _streamEl.innerHTML = text.replace(/```([^`]*?)```/gs, '<pre><code>$1</code></pre>').replace(/\n/g, '<br>');
  } else {
    _streamEl.textContent = text;
  }
  log.scrollTop = log.scrollHeight;
  if (streamLive) {
    streamLive.textContent = raw.replace(/[\n\r]/g, ' ').trim() || raw;
  }
};
window._chatOnDone  = () => {
  _streamEl = null;
  document.querySelectorAll('.cursor').forEach(c => {
    c.style.transition = 'opacity 0.25s steps(4,end)';
    c.style.opacity = '0';
    setTimeout(() => c.remove(), 280);
  });
  if (streamLive) streamLive.textContent = '';
};
window._chatOnError = () => {
  _streamEl = null;
  document.querySelectorAll('.cursor').forEach(c => c.remove());
  if (streamLive) streamLive.textContent = '';
};

function getMsgText(msgEl) {
  const p = msgEl.querySelector('.msg-prompt')?.textContent || '';
  const b = msgEl.querySelector('.msg-body') || msgEl;
  return (p + ' ' + (b.textContent || '')).trim();
}

function openActionMenu(msgEl) {
  document.querySelectorAll('.action-menu').forEach(m => m.remove());
  const menu = document.createElement('div');
  menu.className = 'action-menu';
  const txt = getMsgText(msgEl);
  menu.innerHTML = '<button data-act="copy">Copy</button><button data-act="quote">Quote</button><button data-act="close">Close</button>';
  const rect = msgEl.getBoundingClientRect();
  menu.style.left = (rect.left + window.scrollX + 8) + 'px';
  menu.style.top = (rect.bottom + window.scrollY + 2) + 'px';
  document.body.appendChild(menu);
  const onAct = (ev) => {
    const act = ev.target.dataset.act;
    if (act === 'copy') {
      navigator.clipboard?.writeText(txt).catch(() => {});
      menu.remove();
    } else if (act === 'quote') {
      if (input) { input.value = '> ' + txt + '\n'; input.focus(); }
      menu.remove();
    } else if (act === 'close') {
      menu.remove();
    }
  };
  menu.addEventListener('click', onAct);
  const close = (e) => {
    if (!menu.contains(e.target) || (e.key && e.key === 'Escape')) {
      menu.remove();
      document.removeEventListener('click', close, true);
      document.removeEventListener('keydown', close);
    }
  };
  setTimeout(() => {
    document.addEventListener('click', close, true);
    document.addEventListener('keydown', close);
  }, 0);
}

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
  window.MASTERVoice?.initAudio?.();
  sendMessage(text);
}, true);
