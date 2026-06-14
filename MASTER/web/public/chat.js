"use strict";

const log   = document.getElementById('chat-log');
const zsh   = document.getElementById('zsh');
const input = document.getElementById('zin');
const sessionStartedAt = Date.now();

let _streamEl = null;
let _typingEl = null;

const sessionStats = (() => {
  let el = document.getElementById('session-stats');
  if (!el) {
    el = document.createElement('div');
    el.id = 'session-stats';
    el.className = 'session-stats';
    document.body.appendChild(el);
  }
  return el;
})();

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

window._chatEvtSrc = null;
window._chatCancel = () => {
  if (window._chatEvtSrc) { try { window._chatEvtSrc.close(); } catch (_) {} window._chatEvtSrc = null; }
  window._chatOnError?.();
};

let laughterTimer = null;
function triggerLaughterBurst() {
  const face = window.MASTER_FACE;
  if (!face?.State) return;
  face.State.shake = Math.max(face.State.shake || 0, 0.7);
  face.State.pulse = Math.max(face.State.pulse || 0, 0.55);
  document.body.dataset.laughter = '1';
  if (laughterTimer) clearTimeout(laughterTimer);
  laughterTimer = setTimeout(() => {
    delete document.body.dataset.laughter;
    laughterTimer = null;
  }, 900);
}

function updateSessionStats() {
  if (!sessionStats || !log) return;
  const messageCount = log.querySelectorAll('.message').length;
  const wordCount = Array.from(log.querySelectorAll('.message')).reduce((total, msgEl) => {
    const body = msgEl.querySelector('.msg-body');
    const text = (body?.textContent || msgEl.textContent || '').replace(/^(you\$|master\$)\s*/i, '').trim();
    if (!text) return total;
    return total + text.split(/\s+/).filter(Boolean).length;
  }, 0);
  const elapsedMs = Date.now() - sessionStartedAt;
  const minutes = Math.floor(elapsedMs / 60000);
  const seconds = Math.floor((elapsedMs % 60000) / 1000).toString().padStart(2, '0');
  const wordLabel = wordCount >= 1000 ? `${(wordCount / 1000).toFixed(1).replace(/\.0$/, '')}k words today` : `${wordCount} words today`;
  sessionStats.textContent = `${wordLabel} · ${minutes}m ${seconds}s`;
  sessionStats.title = `remembers ${messageCount} things from today`;
}
setInterval(updateSessionStats, 1000);

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
    const typing = document.createElement('span');
    typing.className = 'typing-indicator';
    typing.innerHTML = '<span></span><span></span><span></span>';
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
    d.appendChild(typing);
    d.appendChild(cur);
    d.appendChild(copyBtn);
    _streamEl = body;
    _typingEl = typing;
  }
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
  updateSessionStats();
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
  if (_typingEl) { _typingEl.remove(); _typingEl = null; }
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
  if (/(?:\(|\b)(?:ha(?:ha)?|heh|lol|lmao|rofl)\b|[🤣😂😆]/i.test(raw)) triggerLaughterBurst();
  updateSessionStats();
};
window._chatOnDone  = () => {
  _streamEl = null;
  if (_typingEl) { _typingEl.remove(); _typingEl = null; }
  document.querySelectorAll('.cursor').forEach(c => {
    c.style.transition = 'opacity 0.25s steps(4,end)';
    c.style.opacity = '0';
    setTimeout(() => c.remove(), 280);
  });
  if (streamLive) streamLive.textContent = '';
  updateSessionStats();
};
window._chatOnError = () => {
  _streamEl = null;
  if (_typingEl) { _typingEl.remove(); _typingEl = null; }
  document.querySelectorAll('.cursor').forEach(c => c.remove());
  if (streamLive) streamLive.textContent = '';
  updateSessionStats();
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
