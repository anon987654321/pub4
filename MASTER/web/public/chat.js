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
