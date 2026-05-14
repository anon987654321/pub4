// sse.js — sendMessage() EventSource SSE, state ping interval, applyProviderTint()
"use strict";

let evtSrc = null;

function sendMessage(text) {
  if (evtSrc) { try { evtSrc.close(); } catch (e) {} }
  ttsSkip();
  State.mode = 'thinking';
  Face.dispersionTarget = 0.35;
  Face.browTarget = 0.4;
  const token = new URLSearchParams(window.location.search).get('token') || '';
  const stateBlob = encodeURIComponent(`${State.mood}|${State.mode}|${((performance.now() - State.lastTouch)/1000)|0}|${palIdx}`);
  const url = `/chat/message?token=${encodeURIComponent(token)}&message=${encodeURIComponent(text)}&state=${stateBlob}`;
  evtSrc = new EventSource(url);
  let pending = '';
  evtSrc.onmessage = (ev) => {
    const raw = ev.data || '';
    if (raw === '[DONE]') {
      if (pending.trim()) enqueueSpeech(pending.trim());
      pending = '';
      State.mode = 'idle'; Face.browTarget = 0; Face.dispersionTarget = 0;
      mandalaLock();
      try { evtSrc.close(); } catch (e) {}
      return;
    }
    if (raw.startsWith('ERROR:')) { Face.coronaFlash = 1.0; State.mode = 'error'; fadePaletteTo(VERDICT_TINT.veto); return; }
    const chunk = raw.replace(/\\n/g, '\n').replace(/\\\\/g, '\\');
    pending += chunk;
    Face.dispersionTarget = 0;
    let m;
    while ((m = pending.match(SENT_BREAK))) {
      const cut = m.index + m[0].length;
      const sent = pending.slice(0, cut).trim();
      pending = pending.slice(cut);
      if (sent) {
        enqueueSpeech(sent); chromaticPulse();
        Face.dispersionTarget = Math.min(0.06, (Face.dispersionTarget || 0) + 0.04);
        setTimeout(() => { if (Face.dispersionTarget > 0) Face.dispersionTarget = Math.max(0, Face.dispersionTarget - 0.04); }, 250);
      }
    }
  };
  evtSrc.addEventListener('tool', (ev) => {
    try { JSON.parse(ev.data); datamosh(); Face.dispersionTarget = 0.2; } catch (e) {}
  });
  evtSrc.addEventListener('mood', (ev) => {
    const m = (ev.data || '').trim();
    if (!m) return;
    tts.mood = m; State.mood = m; moodTone(m);
  });
  evtSrc.addEventListener('model', (ev) => {
    const m = (ev.data || '').trim();
    if (!m) return;
    tts.model = m; applyProviderTint(m);
  });
  evtSrc.addEventListener('verdict', (ev) => {
    const v = (ev.data || '').trim();
    fadePaletteTo(VERDICT_TINT[v] || timePalette());
    pulseEdge();
  });
  evtSrc.addEventListener('confidence', (ev) => {
    const c = parseFloat(ev.data); if (isNaN(c)) return;
    State.confidence = c; Face.browTarget = 1 - c; Face.dispersionTarget = Math.max(0, (1 - c) * 0.4);
  });
  evtSrc.onerror = () => { Face.coronaFlash = 0.6; State.mode = 'error'; try { evtSrc.close(); } catch (e) {} };
}

setInterval(() => {
  const idleS = ((performance.now() - State.lastTouch) / 1000) | 0;
  const body = new URLSearchParams({
    mood: State.mood, mode: State.mode, idle: String(idleS),
    palette: String(palIdx), confidence: State.confidence.toFixed(2),
    tilt_x: State.tiltX.toFixed(2), tilt_y: State.tiltY.toFixed(2)
  });
  try { fetch('/canvas/state', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body, keepalive: true }); } catch (e) {}
}, 8000);

function applyProviderTint(model) {
  const m = (model || '').toLowerCase();
  const key = Object.keys(PROVIDER_TINT).find(k => m.includes(k));
  if (key) fadePaletteTo(PROVIDER_TINT[key]);
}

function pulseEdge() { Face.edgePulse = 1.0; }
