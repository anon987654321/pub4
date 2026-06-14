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
  const idx = log.children.length;
  if (idx > 0) d.style.animationDelay = Math.min(idx, 3) * 40 + 'ms';
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
    const copyBtn = document.createElement('button');
    copyBtn.className = 'msg-copy';
    copyBtn.title = 'Copy';
    copyBtn.setAttribute('aria-label', 'Copy response');
    copyBtn.addEventListener('click', () => {
      navigator.clipboard?.writeText(body.textContent || '').then(() => {
        copyBtn.textContent = '\u2713';
        setTimeout(() => { copyBtn.textContent = ''; }, 1200);
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
      if (input) { input.value = `> ${txt}\n`; input.focus(); }
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

window._chatOnThought = (line) => {
  if (!line) return;
  const asst = log.querySelector('.message.assistant:last-of-type');
  if (!asst) return;
  let block = asst.querySelector('.thought-trace');
  if (!block) {
    block = document.createElement('div');
    block.className = 'thought-trace';
    asst.insertBefore(block, asst.firstChild);
  }
  const d = document.createElement('div');
  d.className = 'thought-line';
  d.textContent = line;
  block.appendChild(d);
  log.scrollTop = log.scrollHeight;
};

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

async function runSlashCommand(text) {
  window._chatOnUser?.(text);
  try {
    const r = await fetch('/chat/command', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify({ command: text })
    });
    const data = await r.json().catch(() => ({ output: '' }));
    const out = (data.output || '(no output)').toString();
    window._chatOnChunk?.(out);
    window._chatOnDone?.();
  } catch (e) {
    window._chatOnChunk?.('error: ' + (e.message || e));
    window._chatOnError?.();
  }
}

async function sendMessage(text) {
  if (text.startsWith('/')) { return runSlashCommand(text); }
  if (_evtSrc) { try { _evtSrc.close(); } catch (_) {} }
  window._chatOnUser?.(text);

  const enhanced = await enhanceMessage(text);
  const params = new URLSearchParams({ message: enhanced.text, state: 'idle|thinking|0|0' });
  if (enhanced.preEnhanced) params.set('pre_enhanced', '1');

  const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;
  const FIRST_CHUNK = /(.{28,}?[,;:—]\s+|.{36,}?\s+)/;
  let assistantBuffer = '', ttsBuffer = '', firstChunkSent = false;
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
      const voice = window.MASTERVoice;
      if (voice?.enqueue && ttsBuffer.trim()) voice.enqueue(ttsBuffer.trim());
      ttsBuffer = '';
      window._chatOnChunk?.(`\n${raw}\n`);
      window._chatOnError?.();
      return;
    }
    const chunk = raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
    assistantBuffer += chunk;
    ttsBuffer += chunk;
    window._chatOnChunk?.(raw);
    let m;
    if (!firstChunkSent) {
      const fm = ttsBuffer.match(FIRST_CHUNK);
      if (fm) {
        const cut = fm.index + fm[0].length;
        const sent = ttsBuffer.slice(0, cut).trim();
        ttsBuffer = ttsBuffer.slice(cut);
        if (sent) { window.MASTERVoice?.enqueue?.(sent); firstChunkSent = true; }
      }
    }
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
  _evtSrc.addEventListener('thought', (ev) => {
    try { window._chatOnThought?.(JSON.parse(ev.data)); } catch (_) {}
  });
  _evtSrc.onerror = () => {
    const voice = window.MASTERVoice;
    if (voice?.enqueue && ttsBuffer.trim()) voice.enqueue(ttsBuffer.trim());
    ttsBuffer = '';
    try { _evtSrc.close(); } catch (_) {}
    window._chatOnError?.();
  };
}

zsh?.addEventListener('submit', (event) => {
  event.preventDefault();
  event.stopImmediatePropagation();
  const text = input.value.trim();
  if (/^(endless white|\/ew)$/i.test(text)) { window._endlessWhite?.(); input.value = ''; return; }
  if (!text) return;
  input.value = '';
  window.MASTERVoice?.initAudio?.();
  sendMessage(text);
}, true);

document.querySelectorAll('.tool').forEach(btn => {
  btn.addEventListener('click', (ev) => {
    ev.preventDefault();
    const cmd = btn.dataset.cmd;
    const act = btn.dataset.act;
    if (cmd) { input.value = cmd; input.focus(); return; }
    if (act === 'mic') startMic(btn);
  });
});

function startMic(btn) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) { input.placeholder = 'mic unavailable in this browser'; return; }
  if (btn._rec) { try { btn._rec.stop(); } catch(_){} btn._rec = null; btn.classList.remove('active'); return; }
  const rec = new SR();
  rec.lang = navigator.language || 'en-US';
  rec.continuous = false;
  rec.interimResults = true;
  rec.onresult = (ev) => {
    let s = '';
    for (let i = 0; i < ev.results.length; i++) s += ev.results[i][0].transcript;
    input.value = s.trim();
  };
  rec.onerror = () => { btn._rec = null; btn.classList.remove('active'); };
  rec.onend = () => { btn._rec = null; btn.classList.remove('active'); };
  rec.start();
  btn._rec = rec;
  btn.classList.add('active');
}
