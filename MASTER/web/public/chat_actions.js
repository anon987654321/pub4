"use strict";

function chatInput() {
  return document.getElementById('zin');
}

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
  if (text.startsWith('/')) return runSlashCommand(text);
  if (window._chatEvtSrc) { try { window._chatEvtSrc.close(); } catch (_) {} }
  window._chatOnUser?.(text);

  const enhanced = await enhanceMessage(text);
  const params = new URLSearchParams({ message: enhanced.text, state: 'idle|thinking|0|0' });
  if (enhanced.preEnhanced) params.set('pre_enhanced', '1');

  const SENT_BREAK = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;
  const FIRST_CHUNK = /(.{28,}?[,;:—]\s+|.{36,}?\s+)/;
  let assistantBuffer = '', ttsBuffer = '', firstChunkSent = false;
  window._chatEvtSrc = new EventSource(`/chat/message?${params.toString()}`);
  window._chatEvtSrc.onmessage = (ev) => {
    const raw = ev.data || '';
    if (raw === '[DONE]') {
      const voice = window.MASTERVoice;
      if (voice?.setLastText) voice.setLastText(assistantBuffer);
      if (voice?.enqueue && ttsBuffer.trim()) voice.enqueue(ttsBuffer.trim());
      ttsBuffer = '';
      try { window._chatEvtSrc.close(); } catch (_) {}
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
  window._chatEvtSrc.addEventListener('dmesg', (ev) => {
    try { window._chatOnDmesg?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('thought', (ev) => {
    try { window._chatOnThought?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.onerror = () => {
    const voice = window.MASTERVoice;
    if (voice?.enqueue && ttsBuffer.trim()) voice.enqueue(ttsBuffer.trim());
    ttsBuffer = '';
    try { window._chatEvtSrc.close(); } catch (_) {}
    window._chatOnError?.();
  };
}

function startMic(btn) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const input = chatInput();
  if (!SR) { if (input) input.placeholder = 'mic unavailable in this browser'; return; }
  if (btn._rec) { try { btn._rec.stop(); } catch(_){} btn._rec = null; btn.classList.remove('active'); return; }
  const rec = new SR();
  rec.lang = navigator.language || 'en-US';
  rec.continuous = false;
  rec.interimResults = true;
  rec.onresult = (ev) => {
    let s = '';
    for (let i = 0; i < ev.results.length; i++) s += ev.results[i][0].transcript;
    if (input) input.value = s.trim();
  };
  rec.onerror = () => { btn._rec = null; btn.classList.remove('active'); };
  rec.onend = () => { btn._rec = null; btn.classList.remove('active'); };
  rec.start();
  btn._rec = rec;
  btn.classList.add('active');
}
