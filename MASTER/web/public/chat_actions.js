"use strict";

function chatInput() {
  return document.getElementById('zin');
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

function feltCssNumber(name, fallback) {
  const raw = document.documentElement.style.getPropertyValue(name);
  const parsed = parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function collectFeltState() {
  if (typeof window.MASTER_FACE?.collectFeltState === 'function') {
    return window.MASTER_FACE.collectFeltState();
  }
  const st = window.MASTER_FACE?.State || {};
  const mood = (st.mood || document.body.dataset.masterState || 'idle').toString();
  const mode = (st.mode || document.body.dataset.pipelineStage || 'idle').toString();
  const entropy = Number.isFinite(st.entropy) ? st.entropy : feltCssNumber('--master-entropy', 0.2);
  const confidence = Number.isFinite(st.confidence) ? st.confidence : feltCssNumber('--master-confidence', 0.86);
  return `${mood}|${mode}|${entropy.toFixed(2)}|${confidence.toFixed(2)}`;
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

const OUTBOX_STORE = 'pending-sends';

async function queueOfflineSend(text) {
  if (!window.indexedDB) return false;
  const db = await new Promise((resolve, reject) => {
    const req = indexedDB.open('master-session', 2);
    req.onupgradeneeded = () => {
      const database = req.result;
      if (!database.objectStoreNames.contains(OUTBOX_STORE)) database.createObjectStore(OUTBOX_STORE, { keyPath: 'id', autoIncrement: true });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  await new Promise((resolve, reject) => {
    const tx = db.transaction(OUTBOX_STORE, 'readwrite');
    tx.objectStore(OUTBOX_STORE).add({ text, ts: Date.now() });
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
  window._chatOnDmesg?.('queued offline');
  return true;
}

async function drainOfflineQueue() {
  if (!navigator.onLine || !window.indexedDB) return;
  const db = await new Promise((resolve) => {
    const req = indexedDB.open('master-session', 2);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => resolve(null);
  });
  if (!db?.objectStoreNames?.contains(OUTBOX_STORE)) return;
  const rows = await new Promise((resolve) => {
    const tx = db.transaction(OUTBOX_STORE, 'readonly');
    const getAll = tx.objectStore(OUTBOX_STORE).getAll();
    getAll.onsuccess = () => resolve(getAll.result || []);
    getAll.onerror = () => resolve([]);
  });
  for (const row of rows) {
    await sendMessage(row.text);
    await new Promise((resolve) => {
      const tx = db.transaction(OUTBOX_STORE, 'readwrite');
      tx.objectStore(OUTBOX_STORE).delete(row.id);
      tx.oncomplete = resolve;
    });
  }
}

window.addEventListener('online', () => { drainOfflineQueue().catch(() => {}); });

async function sendMessage(text) {
  if (!navigator.onLine) {
    const queued = await queueOfflineSend(text);
    if (queued) return;
  }
  if (text.startsWith('!') && text.length > 1) return runSlashCommand('/shell ' + text.slice(1).trim());
  if (text.startsWith('/')) return runSlashCommand(text);
  if (window._chatEvtSrc) { try { window._chatEvtSrc.close(); } catch (_) {} }
  window._chatOnUser?.(text);

  const enhanced = await enhanceMessage(text);
  const params = new URLSearchParams({ message: enhanced.text, state: collectFeltState() });
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
    try {
      const line = JSON.parse(ev.data);
      window._chatOnDmesg?.(line);
      window.MASTERVisual?.runtime?.({ event: "dmesg", data: line });
    } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('thought', (ev) => {
    try { window._chatOnThought?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('compaction', (ev) => {
    try { window._chatOnCompaction?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('ctx_footer', (ev) => {
    try { window._chatOnCtxFooter?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('phantom', (ev) => {
    try { window._chatOnPhantom?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('tool_stack', (ev) => {
    try { window._chatOnToolStack?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('stage', (ev) => {
    try { window._chatOnStage?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.addEventListener('btw', (ev) => {
    try { window._chatOnBtw?.(JSON.parse(ev.data)); } catch (_) {}
  });
  window._chatEvtSrc.onerror = () => {
    const voice = window.MASTERVoice;
    if (voice?.enqueue && ttsBuffer.trim()) voice.enqueue(ttsBuffer.trim());
    ttsBuffer = '';
    try { window._chatEvtSrc.close(); } catch (_) {}
    window._chatOnError?.('stream interrupted');
  };
}

function startMic(btn) {
  if (window.MASTER_FACE?.startSTT) {
    window.MASTER_FACE.startSTT();
    btn?.classList?.add('active');
    return;
  }
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

window.collectFeltState = collectFeltState;
if (!window.sendMessage) window.sendMessage = sendMessage;
