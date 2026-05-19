"use strict";

const log   = document.getElementById('chat-log');
const zsh   = document.getElementById('zsh');
const input = document.getElementById('zin');

let _streamEl = null;

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

(function applyTier() {
  const tier = document.querySelector('meta[name=master-tier]')?.content
    || (location.search.includes('token=') ? 'authenticated' : 'visitor');
  const pp = document.querySelector('#zsh .pp');
  if (pp) pp.textContent = tier === 'authenticated' ? 'dev' : 'visitor';
})();
