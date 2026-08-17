"use strict";

function escapeHtml(str) {
  return str.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const log   = document.getElementById('chat-log');
const CHAT_VIRTUAL_MAX = 56;
let chatArchived = 0;
let chatSpacer = null;

function ensureChatSpacer() {
  if (!log) return null;
  if (!chatSpacer) {
    chatSpacer = document.createElement('div');
    chatSpacer.className = 'virtual-spacer';
    chatSpacer.setAttribute('aria-hidden', 'true');
    log.prepend(chatSpacer);
  }
  return chatSpacer;
}

function trimChatLogVirtual() {
  if (!log || !window.MASTER_RUNTIME?.enhancements?.includes?.('chat_virtual_scroll')) return;
  while (log.querySelectorAll('.message').length > CHAT_VIRTUAL_MAX) {
    const first = log.querySelector('.message');
    if (!first || first.classList.contains('virtual-spacer')) break;
    first.remove();
    chatArchived += 1;
  }
  const spacer = ensureChatSpacer();
  if (spacer) spacer.style.height = `${chatArchived * 68}px`;
}
const zsh   = document.getElementById('zsh');
const input = document.getElementById('zin');
const sessionStartedAt = Date.now();
const recentReplies = [];
let recentReplyCursor = -1;

let _streamEl = null;
let _typingEl = null;

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
  if (window._chatEvtSrc) { try { window._chatEvtSrc.close(); } catch (err) { window.MASTER_LOG?.warn?.("chat:stream_close", err); } window._chatEvtSrc = null; }
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

// Session word/time counter UI removed (idle-screen chrome); kept as a no-op
// so the existing call sites below don't need to change.
function updateSessionStats() {}

const providerChip = (() => {
  let el = document.getElementById('provider-chip');
  if (!el) {
    el = document.createElement('span');
    el.id = 'provider-chip';
    el.className = 'provider-chip';
    el.setAttribute('aria-hidden', 'true');
    const anchor = document.getElementById('zsh-status') || document.getElementById('ui-status');
    if (anchor?.parentElement) anchor.parentElement.appendChild(el);
    else document.body.appendChild(el);
  }
  return el;
})();

function syncProviderChip(provider) {
  if (!providerChip || !provider) return;
  const label = String(provider).slice(0, 12);
  // Idempotency guard — load-bearing, not an optimization: this function
  // emits MASTERVisual.event(), whose bridge re-dispatches a master:visual
  // DOM event carrying the same provider, which the listener below feeds
  // straight back into syncProviderChip. Without exiting on a repeat
  // provider that's unbounded mutual recursion (RangeError: Maximum call
  // stack size exceeded, observed live on every SSE model event).
  if (providerChip.dataset.provider === label) return;
  providerChip.textContent = label;
  providerChip.dataset.provider = label;
  document.documentElement.dataset.modelProvider = label;
  window.MASTERVisual?.event?.('model:tint', { topology: 'neural', entropy: 0.2, confidence: 0.84, provider: label, mode: 'provider' });
}

window.addEventListener('master:palette', (ev) => syncProviderChip(ev.detail?.provider));
window.addEventListener('master:visual', (ev) => {
  const p = ev.detail?.provider;
  if (p && p !== 'unknown') syncProviderChip(p);
});

if (log && window.MASTER_RUNTIME?.enhancements?.includes?.('chat_scroll_snap')) {
  let scrollRaf = null;
  log.addEventListener('scroll', () => {
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => {
      scrollRaf = null;
      const nearBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 64;
      if (nearBottom) log.scrollTop = log.scrollHeight;
    });
  }, { passive: true });
}

function appendMsg(role, text = '') {
  const d = document.createElement('div');
  d.className = `message ${role}`;
  d.tabIndex = 0;
  d.setAttribute('role', 'article');
  d.setAttribute('aria-label', `${role} message`);
  const idx = log.children.length;
  if (idx > 0) {
    const stagger = Math.min(idx, 8) * 48;
    d.style.animationDelay = `${stagger}ms`;
    d.dataset.enterStagger = String(stagger);
  }
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
    const actions = document.createElement('div');
    actions.className = 'msg-actions';
    actions.innerHTML = '<button type="button" data-act="like" title="Rate up">👍</button><button type="button" data-act="retry" title="Retry">🔁</button><button type="button" data-act="delete" title="Delete">🗑</button><button type="button" data-act="simpler" title="Explain simpler">⇣</button><button type="button" data-act="deeper" title="Go deeper">⇡</button>';
    actions.addEventListener('click', (ev) => {
      const act = ev.target?.dataset?.act;
      if (!act) return;
      ev.preventDefault();
      ev.stopPropagation();
      if (act === 'like') {
        d.dataset.reaction = 'like';
        navigator.vibrate?.(10);
        return;
      }
      if (act === 'retry') {
        const last = window._lastUserMessageText || input.value || '';
        if (last && window.sendMessage) window.sendMessage(last);
        return;
      }
      if (act === 'delete') {
        d.remove();
        return;
      }
      if (act === 'simpler') {
        if (window.sendMessage) window.sendMessage(`Please explain this more simply:\n${body.textContent || ''}`);
        return;
      }
      if (act === 'deeper') {
        if (window.sendMessage) window.sendMessage(`Go deeper on this answer:\n${body.textContent || ''}`);
        return;
      }
    });
    d.appendChild(actions);
    _streamEl = body;
    _typingEl = typing;
  }
  log.appendChild(d);
  trimChatLogVirtual();
  log.scrollTop = log.scrollHeight;
  updateSessionStats();
  d.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      openActionMenu(d);
    }
  });
}

window._chatOnUser  = (text) => {
  window._lastUserMessageText = text;
  appendMsg('user', text);
  appendMsg('assistant');
};

window._chatConfirmEnhance = (original, enhanced) => new Promise(resolve => {
  const note = document.createElement('div');
  note.className = 'enhance-confirm';
  note.innerHTML =
    '<span class="enhance-arrow">\u2192</span> ' +
    '<span class="enhance-text">' + enhanced.replace(/</g, '&lt;') + '</span> ' +
    '<span class="enhance-yn">[y/n]</span>';
  log.appendChild(note);
  log.scrollTop = log.scrollHeight;

  const timeout = setTimeout(() => {
    window.MASTERVisual?.event?.('enhance:settle', { topology: 'papua-mask', entropy: 0.1, confidence: 0.9, mode: 'settle' });
    finish(original);
  }, 12000);

  function finish(chosen) {
    clearTimeout(timeout);
    note.remove();
    document.removeEventListener('keydown', onKey);
    if (chosen === enhanced) {
      window.MASTER_FACE_BLEND?.applyExpression?.({ arousal: 0.7 });
    }
    resolve(chosen);
  }

  function onKey(e) {
    if (e.key === 'y' || e.key === 'Y' || e.key === 'Enter') { e.preventDefault(); finish(enhanced); }
    else if (e.key === 'n' || e.key === 'N' || e.key === 'Escape') { e.preventDefault(); finish(original); }
  }

  document.addEventListener('keydown', onKey);
});

let _chunkCount = 0;
let _streamLiveTimer = null;
window._chatOnChunk = (raw) => {
  if (!_streamEl) return;
  if (_typingEl && (document.body.dataset.instantStream === '1' || raw.length > 0)) { _typingEl.remove(); _typingEl = null; }
  _chunkCount++;
  if (/booting/i.test(raw) && /retry/i.test(raw)) {
    const ui = document.getElementById('ui-status');
    if (ui) ui.textContent = 'master warming up — retry shortly';
    const errLive = document.getElementById('error-live');
    if (errLive) errLive.textContent = 'master warming up';
    _streamEl.textContent = 'master is still starting — try again in a moment.';
    return;
  }
  if (raw.startsWith('ERROR:')) {
    _streamEl.closest('.message')?.classList.add('msg-error-flash');
    setTimeout(() => _streamEl.closest('.message')?.classList.remove('msg-error-flash'), 120);
  }
  const text = _streamEl.textContent + raw.replace(/\n/g, '\n').replace(/\\\\/g, '\\');
  if (text.includes('```')) {
    _streamEl.innerHTML = escapeHtml(text).replace(/```([^`]*?)```/gs, '<pre><code>$1</code></pre>').replace(/\n/g, '<br>');
  } else {
    _streamEl.textContent = text;
  }
  const nearBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 48;
  if (nearBottom) requestAnimationFrame(() => { log.scrollTop = log.scrollHeight; });
  if (streamLive) {
    const snippet = raw.replace(/[\n\r]/g, ' ').trim() || raw;
    clearTimeout(_streamLiveTimer);
    _streamLiveTimer = setTimeout(() => { streamLive.textContent = snippet; }, 120);
  }
  if (/(?:\(|\b)(?:ha(?:ha)?|heh|lol|lmao|rofl)\b|[🤣😂😆]/i.test(raw)) triggerLaughterBurst();
  updateSessionStats();
};
window._chatOnDone  = () => {
  _toolStackCount = 0;
  delete document.body.dataset.pipelineStage;
  const stageBar = document.getElementById('pipeline-stage');
  if (stageBar) stageBar.textContent = '';
  const finished = (_streamEl?.textContent || '').trim();
  if (finished) window._chatRememberReply?.(finished);
  window._chatCollapseLongBlock?.(_streamEl);
  const lastAsst = log?.querySelector('.message.assistant:last-of-type');
  if (lastAsst && parseFloat(document.body.dataset.confidence || '1') > 0.75) {
    lastAsst.classList.add('msg-settled');
    setTimeout(() => lastAsst.classList.remove('msg-settled'), 1800);
  }
  _chunkCount = 0;
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
window._chatOnError = (reason = '') => {
  _streamEl = null;
  if (_typingEl) { _typingEl.remove(); _typingEl = null; }
  document.querySelectorAll('.cursor').forEach(c => c.remove());
  if (streamLive) streamLive.textContent = '';
  const errLive = document.getElementById('error-live');
  if (errLive && reason) errLive.textContent = reason;
  window._chatShowStreamRetry?.(reason);
  updateSessionStats();
};

function getMsgText(msgEl) {
  const p = msgEl.querySelector('.msg-prompt')?.textContent || '';
  const b = msgEl.querySelector('.msg-body') || msgEl;
  return (`${p} ` + (b.textContent || '')).trim();
}

window._chatRememberReply = (text) => {
  const reply = String(text || '').trim();
  if (!reply) return;
  if (recentReplies[recentReplies.length - 1] === reply) return;
  recentReplies.push(reply);
  while (recentReplies.length > 12) recentReplies.shift();
  recentReplyCursor = recentReplies.length;
};

window._chatCycleRecentReply = (direction) => {
  if (!recentReplies.length || !input) return;
  recentReplyCursor = Math.max(0, Math.min(recentReplies.length - 1, recentReplyCursor + (direction > 0 ? 1 : -1)));
  input.value = recentReplies[recentReplyCursor] || '';
  input.focus();
  input.setSelectionRange?.(input.value.length, input.value.length);
};

function openActionMenu(msgEl) {
  document.querySelectorAll('.action-menu').forEach(m => m.remove());
  const menu = document.createElement('div');
  menu.className = 'action-menu';
  const txt = getMsgText(msgEl);
  const bodyText = msgEl.querySelector('.msg-body')?.textContent || txt;
  menu.innerHTML = '<button data-act="copy">Copy</button><button data-act="quote">Quote</button><button data-act="simpler">Simpler</button><button data-act="deeper">Deeper</button><button data-act="close">Close</button>';
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
    } else if (act === 'simpler') {
      if (window.sendMessage) window.sendMessage(`Please explain this more simply:\n${bodyText}`);
      menu.remove();
    } else if (act === 'deeper') {
      if (window.sendMessage) window.sendMessage(`Go deeper on this answer:\n${bodyText}`);
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

// Per-message context-usage footer removed (idle-screen chrome); no-op kept
// since callers use optional chaining and this file assigns it unconditionally.
window._chatOnCtxFooter = () => {};

window._chatOnCompaction = (payload) => {
  if (!payload?.summary) return;
  const note = document.createElement('div');
  note.className = 'message system compaction-note';
  note.setAttribute('role', 'note');
  const title = document.createElement('div');
  title.className = 'compaction-title';
  title.textContent = 'context compacted';
  const body = document.createElement('pre');
  body.className = 'compaction-body';
  body.textContent = payload.summary;
  note.appendChild(title);
  note.appendChild(body);
  log?.appendChild(note);
  log.scrollTop = log.scrollHeight;
  window._chatOnDmesg?.('compact0 at master0: compaction summary logged');
  window.MASTERVisual?.event?.('compaction:done', { topology: 'terrain', entropy: 0.35, confidence: 0.7, mode: 'compact' });
};

window._chatOnPhantom = (payload) => {
  // Raw "phantom: <pattern>" badge text removed (internal-mechanism jargon
  // leaking into the transcript); the glitch reaction below is kept since
  // it's an ambient visual cue, not a label.
  const asst = log?.querySelector('.message.assistant:last-of-type');
  if (asst) {
    asst.classList.add('msg-phantom');
    asst.dataset.phantom = (payload?.patterns || []).join(',');
  }
  document.body.dataset.phantomGlitch = '1';
  setTimeout(() => delete document.body.dataset.phantomGlitch, 900);
  window.MASTERVisual?.event?.('phantom:detected', { topology: 'glitch', entropy: 0.9, confidence: 0.2, mode: 'phantom' });
};

let _toolStackCount = 0;
window._chatOnToolStack = (payload) => {
  _toolStackCount += payload?.count || 1;
  const asst = log?.querySelector('.message.assistant:last-of-type');
  if (!asst) return;
  let stack = asst.querySelector('.tool-stack');
  if (!stack) {
    stack = document.createElement('details');
    stack.className = 'tool-stack';
    stack.innerHTML = '<summary></summary><div class="tool-stack-body"></div>';
    asst.insertBefore(stack, asst.firstChild);
  }
  const summary = stack.querySelector('summary');
  const body = stack.querySelector('.tool-stack-body');
  summary.textContent = `${_toolStackCount} tool call(s)`;
  let chip = document.getElementById('tool-progress-chip');
  if (!chip) {
    chip = document.createElement('span');
    chip.id = 'tool-progress-chip';
    chip.className = 'tool-progress-chip';
    chip.setAttribute('aria-live', 'polite');
    const anchor = document.getElementById('ui-status') || document.getElementById('zsh-status');
    (anchor?.parentElement || document.body).appendChild(chip);
  }
  chip.textContent = `tools ${_toolStackCount}`;
  chip.dataset.count = String(_toolStackCount);
  const line = document.createElement('div');
  line.className = 'tool-stack-line';
  const tool = payload?.tool ? ` ${payload.tool}` : '';
  const path = payload?.path ? ` ${payload.path}` : '';
  line.textContent = `step ${payload?.step ?? '?'}:${tool}${path} (${payload?.count ?? 1})`;
  body.appendChild(line);
  if (payload?.diff) {
    const diff = document.createElement('details');
    diff.className = 'tool-diff';
    diff.innerHTML = `<summary>diff</summary><pre class="diff-body">${payload.diff}</pre>`;
    body.appendChild(diff);
  }
};

window._chatOnStage = (payload) => {
  if (!payload?.stage) return;
  const label = payload.stage.toLowerCase();
  document.body.dataset.pipelineStage = label;
  const phase = payload.phase === 'done' ? ` ${payload.ms || 0}ms` : '…';
  const text = `${payload.stage}${phase}`;
  let bar = document.getElementById('pipeline-stage');
  if (!bar) {
    bar = document.createElement('div');
    bar.id = 'pipeline-stage';
    bar.className = 'pipeline-stage';
    bar.setAttribute('aria-live', 'polite');
    document.body.appendChild(bar);
  }
  bar.textContent = text;
  const ui = document.getElementById('ui-status');
  if (ui) ui.textContent = text;
};

window._chatOnBtw = (payload) => {
  if (!payload?.summary) return;
  const note = document.createElement('div');
  note.className = 'message system btw-note';
  note.textContent = `btw/${payload.type}: ${payload.summary}`;
  log?.appendChild(note);
  log.scrollTop = log.scrollHeight;
};

// Visible "thought trace" block removed (internal event-name clutter). No-op
// kept since callers use optional chaining.
window._chatOnThought = () => {};

window._chatPassHairline = () => {
  const last = log?.querySelector('.message.assistant:last-of-type, .message.user:last-of-type');
  if (!last) return;
  last.classList.add('msg-pass-flash');
  setTimeout(() => last.classList.remove('msg-pass-flash'), 420);
};

// The visible "dmesg" transcript line (raw internal event names like
// "llm0 at master0: ...") is removed, but face_micro_interactions.js's
// veto/pass ecology reaction depends on the chat:dmesg event firing, so the
// dispatch + ecology burst stay; only the DOM line creation is gone.
window._chatOnDmesg = (line) => {
  if (!line) return;
  window.dispatchEvent(new CustomEvent('chat:dmesg', { detail: { line: String(line) } }));
  if (/veto|pass/i.test(String(line))) window.MASTEREcology?.burst?.(4, 0.25);
};

(function wirePhotoUpload() {
  const photoBtn = document.getElementById('photo-button');
  const photoInput = document.getElementById('photo');
  if (!photoBtn || !photoInput) return;
  const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content || '';
  let pressTimer = null;
  photoBtn.addEventListener('click', () => {
    if (photoBtn.dataset.state === 'busy') return;
    photoInput.click();
  });
  photoBtn.addEventListener('pointerdown', () => {
    window.MASTERVisual?.event?.('photo:capture', { topology: 'papua-mask', entropy: 0.12, confidence: 0.9, mode: 'capture' });
    pressTimer = setTimeout(() => {
      if (photoBtn.dataset.state !== 'busy' && photoBtn.dataset.state !== 'ready') {
        window.MASTERVisual?.event?.('photo:preview', { topology: 'papua-mask', entropy: 0.1, confidence: 0.85, mode: 'preview' });
      }
    }, 420);
  });
  photoBtn.addEventListener('pointerup', () => { if (pressTimer) clearTimeout(pressTimer); });
  photoBtn.addEventListener('pointercancel', () => { if (pressTimer) clearTimeout(pressTimer); });
  photoBtn.addEventListener('pointerenter', () => {
    if (photoBtn.dataset.state === 'ready') {
      window.MASTERVisual?.event?.('photo:ready', { topology: 'papua-mask', entropy: 0.12, confidence: 0.88, mode: 'ready' });
    }
  });
  photoInput.addEventListener('change', async () => {
    const file = photoInput.files?.[0];
    photoInput.value = '';
    if (!file) return;
    photoBtn.dataset.state = 'busy';
    const body = new FormData();
    body.append('photo', file);
    try {
      const r = await fetch('/chat/photo', { method: 'POST', headers: { 'X-CSRF-Token': csrf() }, body });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(data.error || 'upload failed');
      window._imageToken = data.token;
      photoBtn.dataset.state = 'ready';
      window.MASTERVisual?.event?.('photo:ready', { topology: 'papua-mask', entropy: 0.14, confidence: 0.9, mode: 'ready' });
    } catch (err) {
      window.MASTER_LOG?.warn?.("chat:upload", err);
      photoBtn.dataset.state = '';
      setTimeout(() => photoBtn.classList.add('photo-fail'), 200);
      setTimeout(() => photoBtn.classList.remove('photo-fail'), 1200);
      window._chatOnDmesg?.('photo upload failed');
    }
  });
})();

document.querySelectorAll('.tool').forEach(btn => {
  btn.addEventListener('click', (ev) => {
    ev.preventDefault();
    const cmd = btn.dataset.cmd;
    const act = btn.dataset.act;
    if (cmd) { input.value = cmd; input.focus(); return; }
    if (act === 'mic') {
      // startMic lives in chat_actions.js, which is not loaded on every entry
      // point. Fall back to the always-loaded face voice API so the mic button
      // never throws ReferenceError. (PRESERVE_THEN_IMPROVE_NEVER_BREAK)
      if (typeof startMic === 'function') { startMic(btn); return; }
      btn.classList.toggle('active');
      (window.MASTERVoice?.toggleMic || window.MASTER_FACE?.ttsToggleMic)?.();
    }
  });
});

(function wireCommandPalette() {
  const COMMANDS = [
    { cmd: '/run ', hint: 'natural-language task entry' },
    { cmd: '/scan ', hint: 'deep-scan path' },
    { cmd: '/fix ', hint: 'autofix target' },
    { cmd: '/review ', hint: 'review changes' },
    { cmd: '/why ', hint: 'explain rule or law' },
    { cmd: '/btw research ', hint: 'parallel side agent' },
    { cmd: '/rtk', hint: 'shell output filter stats' },
    { cmd: '/plan', hint: 'show pinned plan' },
    { cmd: '/rebuild', hint: 'hot-restart web face' },
    { cmd: '/grep ', hint: 'search session history' },
    { cmd: '/propose ', hint: 'suggest improvement' },
    { cmd: '/help', hint: 'list commands' },
    { cmd: '/status', hint: 'service and repo health' },
    { cmd: '/self', hint: 'scan MASTER itself' },
    { cmd: 'ping', hint: 'smoke test connection' },
    { cmd: '/voice last', hint: 'replay last reply (Ryan en-GB)' },
    { cmd: '/voice stream on', hint: 'sentence TTS during stream' },
    { action: 'dashboard', label: 'mission control', hint: 'open /dashboard' },
    { action: 'history', label: 'toggle history', hint: 'sidebar · Ctrl+Shift+H' },
    { action: 'export', label: 'export session', hint: 'markdown download · Ctrl+Shift+E' },
    { action: 'export_jsonl', label: 'export jsonl', hint: 'machine-readable session' },
    { action: 'export_png', label: 'export face png', hint: 'snapshot canvas' },
    { action: 'log_search', label: 'filter chat log', hint: 'search visible messages' },
    { action: 'instant', label: 'toggle instant stream', hint: 'skip typing indicator' },
    { action: 'focus', label: 'toggle focus mode', hint: 'hide chrome, face only' },
    { action: 'mute', label: 'toggle TTS mute', hint: 'keyboard: t' },
    { action: 'preview', label: 'preview voice', hint: 'play voice blurb' },
    { action: 'shortcuts', label: 'keyboard shortcuts', hint: 'press ?' },
    { action: 'voice_mode', label: 'hands-free voice mode', hint: 'continuous listening, no mic press' }
  ];

  fetch('/chat/skills').then(r => r.json()).then((skills) => {
    if (!Array.isArray(skills)) return;
    skills.forEach((skill) => {
      COMMANDS.push({ cmd: `/run ${skill.name}`, label: skill.name, hint: skill.description || 'skill' });
    });
  }).catch(() => {});

  let root = document.getElementById('cmd-palette');
  if (!root) {
    root = document.createElement('div');
    root.id = 'cmd-palette';
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-modal', 'true');
    root.setAttribute('aria-label', 'Command palette');
    root.innerHTML = '<div id="cmd-palette-panel"><input id="cmd-palette-input" type="search" autocomplete="off" spellcheck="false" placeholder="command or action" aria-label="Filter commands"><ul id="cmd-palette-list" role="listbox"></ul></div>';
    document.body.appendChild(root);
  }

  const panelInput = document.getElementById('cmd-palette-input');
  const list = document.getElementById('cmd-palette-list');
  let activeIndex = 0;
  let filtered = COMMANDS.slice();

  function runEntry(entry) {
    closePalette();
    if (entry.action === 'dashboard') { window.location.href = '/dashboard'; return; }
    if (entry.action === 'history') { window.MASTERHistory?.toggle?.(); return; }
    if (entry.action === 'export') { window.MASTERExport?.download?.(); return; }
    if (entry.action === 'export_jsonl') { window.MASTERExport?.jsonl?.(); return; }
    if (entry.action === 'export_png') { window.MASTERExport?.png?.(); return; }
    if (entry.action === 'log_search') { window.MASTERLogSearch?.open?.(); return; }
    if (entry.action === 'instant') { window.MASTERStreamMode?.toggle?.(); return; }
    if (entry.action === 'focus') { window.MASTER_FACE?.toggleFocusMode?.(); return; }
    if (entry.action === 'mute') { window.MASTERVoice?.toggleMute?.(); return; }
    if (entry.action === 'preview') { window.MASTERVoice?.previewVoice?.(); return; }
    if (entry.action === 'shortcuts') { window.MASTERShortcuts?.open?.(); return; }
    // Voice Mode is where continuous listening lives — recognition.continuous
    // with a quiet timer and barge-in. This entry used to set a window.MASTER_STT
    // flag that nothing read, and print "stt: continuous" into the status line,
    // so the one visible sign of hands-free was the only part of it that worked.
    if (entry.action === 'voice_mode') { window.MASTER_FACE?.toggleVoiceMode?.(); return; }
    const text = entry.cmd || '';
    if (!text) return;
    if (input) { input.value = text; input.focus(); }
    if (text === 'ping' || text.startsWith('/')) window.sendMessage?.(text);
  }

  function renderList() {
    if (!list) return;
    list.innerHTML = '';
    filtered.forEach((entry, index) => {
      const li = document.createElement('li');
      li.setAttribute('role', 'option');
      li.dataset.active = index === activeIndex ? '1' : '0';
      const label = entry.cmd || entry.label || '';
      li.innerHTML = `${label}<span class="cmd-hint">${entry.hint || ''}</span>`;
      li.addEventListener('mousedown', (ev) => { ev.preventDefault(); runEntry(entry); });
      list.appendChild(li);
    });
  }

  function filterItems(query) {
    const q = query.trim().toLowerCase();
    filtered = !q ? COMMANDS.slice() : COMMANDS.filter((entry) => {
      const hay = `${entry.cmd || ''} ${entry.label || ''} ${entry.hint || ''}`.toLowerCase();
      return hay.includes(q);
    });
    activeIndex = 0;
    renderList();
  }

  const _inerted = [];

  function trapFocus(ev) {
    if (root.dataset.open !== '1' || ev.key !== 'Tab') return;
    const focusable = root.querySelectorAll('input, button, [role="option"]');
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (ev.shiftKey && document.activeElement === first) { ev.preventDefault(); last.focus(); }
    else if (!ev.shiftKey && document.activeElement === last) { ev.preventDefault(); first.focus(); }
  }

  function openPalette(seed = '') {
    root.dataset.open = '1';
    filterItems(seed);
    panelInput.value = seed;
    document.querySelectorAll('body > *').forEach((el) => {
      if (el === root || el.id === 'cmd-palette-panel') return;
      if (!el.inert) { el.inert = true; _inerted.push(el); }
    });
    panelInput.focus();
    panelInput.select();
    document.addEventListener('keydown', trapFocus);
    window.MASTERVisual?.event?.('palette:open', { topology: 'neural', entropy: 0.12, confidence: 0.9, mode: 'palette' });
  }

  function closePalette() {
    delete root.dataset.open;
    _inerted.forEach((el) => { el.inert = false; });
    _inerted.length = 0;
    document.removeEventListener('keydown', trapFocus);
    if (panelInput) panelInput.value = '';
    input?.focus();
  }

  panelInput?.addEventListener('input', () => filterItems(panelInput.value));
  panelInput?.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') { ev.preventDefault(); closePalette(); return; }
    if (ev.key === 'ArrowDown') {
      ev.preventDefault();
      activeIndex = Math.min(filtered.length - 1, activeIndex + 1);
      renderList();
      return;
    }
    if (ev.key === 'ArrowUp') {
      ev.preventDefault();
      activeIndex = Math.max(0, activeIndex - 1);
      renderList();
      return;
    }
    if (ev.key === 'Enter' && filtered[activeIndex]) {
      ev.preventDefault();
      runEntry(filtered[activeIndex]);
    }
  });

  root.addEventListener('click', (ev) => { if (ev.target === root) closePalette(); });
  document.addEventListener('keydown', (ev) => {
    const mod = ev.metaKey || ev.ctrlKey;
    if (mod && ev.key.toLowerCase() === 'k') {
      ev.preventDefault();
      if (root.dataset.open === '1') closePalette();
      else openPalette();
      return;
    }
    if (ev.key === '/' && document.activeElement === input && !input.value) {
      ev.preventDefault();
      openPalette('/');
    }
  });

  window.MASTERCommandPalette = { open: openPalette, close: closePalette };
})();

(function wireHistorySidebar() {
  let panel = document.getElementById('chat-history-panel');
  if (!panel) {
    panel = document.createElement('aside');
    panel.id = 'chat-history-panel';
    panel.setAttribute('aria-label', 'Session history');
    panel.innerHTML =
      '<header class="history-head">' +
      '<span class="history-title">history</span>' +
      '<button type="button" id="history-close" aria-label="Close history">×</button>' +
      '</header>' +
      '<input id="history-search" type="search" autocomplete="off" spellcheck="false" placeholder="search turns" aria-label="Search history">' +
      '<ul id="history-list" role="list"></ul>';
    document.body.appendChild(panel);
  }

  const list = document.getElementById('history-list');
  const search = document.getElementById('history-search');
  const closeBtn = document.getElementById('history-close');
  let cached = [];
  let open = false;

  function faceAck(label) {
    const status = document.getElementById('ui-status');
    if (status) {
      const prev = status.textContent;
      status.textContent = label;
      setTimeout(() => { if (status.textContent === label) status.textContent = prev; }, 900);
    }
    window.MASTERVisual?.event?.('ui:ack', { topology: 'neural', entropy: 0.14, confidence: 0.9, mode: label });
  }

  function renderItems(items) {
    if (!list) return;
    list.innerHTML = '';
    items.forEach((entry, index) => {
      const li = document.createElement('li');
      li.dataset.role = entry.role || 'user';
      li.dataset.index = String(index);
      const role = document.createElement('span');
      role.className = 'history-role';
      role.textContent = entry.role === 'assistant' ? 'master' : 'you';
      const body = document.createElement('span');
      body.className = 'history-body';
      body.textContent = (entry.content || '').slice(0, 240);
      li.appendChild(role);
      li.appendChild(body);
      li.addEventListener('click', () => {
        const quote = (entry.content || '').trim();
        if (!quote || !input) return;
        input.value = `> ${quote}\n`;
        input.focus();
        faceAck('quoted');
      });
      list.appendChild(li);
    });
  }

  function filterItems(query) {
    const q = query.trim().toLowerCase();
    if (!q) return renderItems(cached);
    renderItems(cached.filter((entry) => `${entry.role} ${entry.content}`.toLowerCase().includes(q)));
  }

  async function loadHistory() {
    try {
      const r = await fetch('/chat/history');
      const data = await r.json();
      cached = Array.isArray(data) ? data.slice(-20) : [];
      filterItems(search?.value || '');
    } catch (err) {
      window.MASTER_LOG?.warn?.("chat:history_load", err);
      cached = [];
      renderItems([]);
    }
  }

  function setOpen(next) {
    open = next;
    panel.dataset.open = open ? '1' : '0';
    document.body.dataset.historyOpen = open ? '1' : undefined;
    if (!open) delete document.body.dataset.historyOpen;
    if (open) {
      loadHistory();
      search?.focus();
      faceAck('history');
    }
  }

  function toggle() { setOpen(!open); }

  search?.addEventListener('input', () => filterItems(search.value));
  closeBtn?.addEventListener('click', () => setOpen(false));
  panel.addEventListener('click', (ev) => { if (ev.target === panel) setOpen(false); });

  document.addEventListener('keydown', (ev) => {
    const mod = ev.metaKey || ev.ctrlKey;
    if (mod && ev.shiftKey && ev.key.toLowerCase() === 'h') {
      ev.preventDefault();
      toggle();
    }
    if (ev.key === 'Escape' && open) {
      ev.preventDefault();
      setOpen(false);
    }
  });

  window.MASTERHistory = { toggle, open: () => setOpen(true), close: () => setOpen(false), reload: loadHistory };
})();

(function wireSessionExport() {
  function collectMarkdown() {
    const started = new Date(sessionStartedAt).toISOString();
    const lines = [`# MASTER session`, ``, `exported: ${new Date().toISOString()}`, `started: ${started}`, ``];
    if (!log) return lines.join('\n');
    log.querySelectorAll('.message').forEach((msgEl) => {
      const role = msgEl.classList.contains('user') ? 'you' : 'master';
      const body = msgEl.querySelector('.msg-body') || msgEl;
      const text = (body.textContent || '').replace(/^(you\$|master\$)\s*/i, '').trim();
      if (!text) return;
      lines.push(`## ${role}`, '', text, '');
    });
    return lines.join('\n');
  }

  function download() {
    const md = collectMarkdown();
    const blob = new Blob([md], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    anchor.href = url;
    anchor.download = `master-session-${stamp}.md`;
    anchor.click();
    URL.revokeObjectURL(url);
    const status = document.getElementById('ui-status');
    if (status) {
      const prev = status.textContent;
      status.textContent = 'exported';
      setTimeout(() => { if (status.textContent === 'exported') status.textContent = prev; }, 900);
    }
    window.MASTERVisual?.event?.('session:export', { topology: 'terrain', entropy: 0.1, confidence: 0.95, mode: 'export' });
  }

  document.addEventListener('keydown', (ev) => {
    const mod = ev.metaKey || ev.ctrlKey;
    if (mod && ev.shiftKey && ev.key.toLowerCase() === 'e') {
      ev.preventDefault();
      download();
    }
  });

  function collectJsonl() {
    const rows = [];
    if (!log) return '';
    log.querySelectorAll('.message').forEach((msgEl) => {
      const role = msgEl.classList.contains('user') ? 'user' : 'assistant';
      const body = msgEl.querySelector('.msg-body') || msgEl;
      const text = (body.textContent || '').replace(/^(you\$|master\$)\s*/i, '').trim();
      if (!text) return;
      rows.push({ ts: msgEl.dataset.ts || '', role, content: text });
    });
    return rows.map((row) => JSON.stringify(row)).join('\n');
  }

  function jsonl() {
    const blob = new Blob([collectJsonl()], { type: 'application/x-ndjson;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `master-session-${Date.now()}.jsonl`;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  function png() {
    const canvas = document.getElementById('face');
    if (!canvas || typeof canvas.toBlob !== 'function') return;
    canvas.toBlob((blob) => {
      if (!blob) return;
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `master-face-${Date.now()}.png`;
      anchor.click();
      URL.revokeObjectURL(url);
    }, 'image/png');
  }

  window.MASTERExport = { download, markdown: collectMarkdown, jsonl, png, collectJsonl };
})();

(function wireUiBacklog() {
  const RETRY_ID = 'stream-retry';
  const CMD_KEY = 'master:cmd_hist';
  const IDB_NAME = 'master-session';
  const IDB_STORE = 'turns';

  function announceError(text) {
    const el = document.getElementById('error-live');
    if (el) el.textContent = text;
    const status = document.getElementById('zsh-status') || document.getElementById('ui-status');
    if (status) status.textContent = text;
  }

  window._chatShowStreamRetry = (reason = 'link quiet') => {
    let chip = document.getElementById(RETRY_ID);
    if (!chip) {
      chip = document.createElement('button');
      chip.id = RETRY_ID;
      chip.type = 'button';
      chip.className = 'stream-retry';
      chip.textContent = 'retry';
      chip.addEventListener('click', () => {
        const last = window._lastUserMessageText || '';
        if (last && window.sendMessage) window.sendMessage(last);
        chip.remove();
      });
      document.getElementById('zsh')?.appendChild(chip);
    }
    announceError(reason.includes('rate') ? 'slow down — rate limit' : 'stream failed — retry?');
    window.MASTERVisual?.event?.('chat:retry', { topology: 'serpent', entropy: 0.5, confidence: 0.4, mode: 'retry' });
  };

  window._chatCollapseLongBlock = (bodyEl) => {
    if (!bodyEl) return;
    const text = (bodyEl.textContent || '').trim();
    if (text.length < 800 || bodyEl.closest('details')) return;
    const details = document.createElement('details');
    details.className = 'msg-collapse';
    details.open = true;
    const summary = document.createElement('summary');
    summary.textContent = `response (${text.length} chars)`;
    const inner = document.createElement('div');
    inner.className = 'msg-body';
    inner.innerHTML = bodyEl.innerHTML;
    details.appendChild(summary);
    details.appendChild(inner);
    bodyEl.replaceWith(details);
  };

  window.MASTERStreamMode = {
    toggle() {
      const on = document.body.dataset.instantStream === '1';
      if (on) {
        delete document.body.dataset.instantStream;
        localStorage.removeItem('master:instant-stream');
      } else {
        document.body.dataset.instantStream = '1';
        localStorage.setItem('master:instant-stream', '1');
      }
      const status = document.getElementById('ui-status');
      if (status) status.textContent = on ? 'stream: paced' : 'stream: instant';
    }
  };
  if (localStorage.getItem('master:instant-stream') === '1') document.body.dataset.instantStream = '1';

  window.MASTERLogSearch = (() => {
    let inputEl = null;
    function open() {
      if (!inputEl) {
        inputEl = document.createElement('input');
        inputEl.id = 'log-search';
        inputEl.type = 'search';
        inputEl.placeholder = 'filter visible log';
        inputEl.className = 'log-search';
        inputEl.setAttribute('aria-label', 'Filter chat log');
        inputEl.addEventListener('input', () => {
          const q = inputEl.value.trim().toLowerCase();
          log?.querySelectorAll('.message').forEach((msg) => {
            const text = (msg.textContent || '').toLowerCase();
            msg.hidden = q.length > 0 && !text.includes(q);
          });
        });
        document.getElementById('chat-shell')?.prepend(inputEl);
      }
      inputEl.focus();
    }
    return { open };
  })();

  function pushCmdHistory(text) {
    const trimmed = String(text || '').trim();
    if (!trimmed) return;
    let hist = [];
    try { hist = JSON.parse(localStorage.getItem(CMD_KEY) || '[]'); } catch (err) { window.MASTER_LOG?.warn?.("chat:cmd_history_parse", err); }
    if (hist[hist.length - 1] !== trimmed) hist.push(trimmed);
    while (hist.length > 40) hist.shift();
    localStorage.setItem(CMD_KEY, JSON.stringify(hist));
  }

  const origOnUser = window._chatOnUser;
  window._chatOnUser = (text) => {
    pushCmdHistory(text);
    origOnUser?.(text);
    persistTurn('user', text);
  };

  const origOnDone = window._chatOnDone;
  window._chatOnDone = () => {
    origOnDone?.();
    const body = log?.querySelector('.message.assistant:last-of-type .msg-body, .message.assistant:last-of-type details .msg-body');
    if (body) persistTurn('assistant', body.textContent || '');
    document.getElementById(RETRY_ID)?.remove();
  };

  function persistTurn(role, content) {
    if (!content || !window.indexedDB) return;
    const req = indexedDB.open(IDB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(IDB_STORE)) db.createObjectStore(IDB_STORE, { keyPath: 'id', autoIncrement: true });
    };
    req.onsuccess = () => {
      const db = req.result;
      const tx = db.transaction(IDB_STORE, 'readwrite');
      tx.objectStore(IDB_STORE).add({ role, content, ts: Date.now() });
    };
  }

  document.getElementById('describe-face-btn')?.addEventListener('click', () => {
    const st = window.MASTER_FACE?.State || {};
    const line = `mode ${st.mode || 'idle'}, mood ${st.mood || 'idle'}, confidence ${(st.confidence ?? 0.86).toFixed(2)}, entropy ${(st.entropy ?? 0.2).toFixed(2)}`;
    navigator.clipboard?.writeText(line).catch(() => {});
    const live = document.getElementById('mood-live');
    if (live) live.textContent = line;
    window.MASTERVisual?.event?.('face:describe', { topology: 'papua-mask', entropy: 0.12, confidence: st.confidence || 0.86, mode: 'describe' });
  });

  if (new URLSearchParams(location.search).get('focus') === '1') {
    window.addEventListener('load', () => window.MASTER_FACE?.toggleFocusMode?.(), { once: true });
  }

})();
