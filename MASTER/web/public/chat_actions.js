"use strict";

function chatInput() {
  return document.getElementById("zin");
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || "";
}

function collectFeltState() {
  return window.MASTERFeltState?.collectFeltState?.() || null;
}

function isBangCommand(text) {
  return String(text || "").trim().startsWith('!');
}

function validatedFeltState() {
  const state = collectFeltState();
  if (window.MASTERFeltState?.validateFeltState?.(state)) return state;
  window.MASTER_LOG?.warn?.("chat:felt_state", "invalid felt state payload");
  return null;
}

async function enhanceMessage(text) {
  try {
    const r = await fetch(`/chat/enhance?message=${encodeURIComponent(text)}`);
    const data = await r.json();
    if (data.changed && data.enhanced && data.enhanced !== text) {
      const chosen = await (window._chatConfirmEnhance?.(text, data.enhanced) ?? Promise.resolve(text));
      return { text: chosen, preEnhanced: chosen === data.enhanced };
    }
  } catch (err) {
    window.MASTER_LOG?.warn?.("chat:enhance", err);
  }
  return { text, preEnhanced: false };
}

async function runSlashCommand(text) {
  window._chatOnUser?.(text);
  try {
    const resp = await fetch("/chat/command", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ command: text })
    });
    const data = await resp.json().catch(() => ({ output: "" }));
    const out = (data.output || "(no output)").toString();
    window._chatOnChunk?.(out);
    window._chatOnDone?.();
    (data.client_actions || []).forEach(triggerClientAction);
  } catch (err) {
    window._chatOnChunk?.(`error: ${err?.message || err}`);
    window._chatOnError?.("command failed");
  }
}

function loopsMusicUrl() {
  return window.MASTER_ASSET_PATHS?.faceModules?.["face_loops_music.js"] || "/face_loops_music.js";
}

function triggerClientAction(data) {
  if (!data?.action) return;
  if (data.action === "dilla_bg") {
    import(loopsMusicUrl())
      .then(() => { window._dillaBg?.(); })
      .catch((err) => { window.MASTER_LOG?.warn?.("chat:dilla_bg", err); });
    window.MASTERVisual?.event?.("music:dilla", { topology: "papua-mask", entropy: 0.22, confidence: 0.9, mode: "dilla" });
    return;
  }
  if (data.action === "radio_open") {
    const url = data.url || "/radio_bergen";
    window.open(url, "_blank", "noopener,noreferrer");
    window.MASTERVisual?.event?.("music:radio", { topology: "warp-tunnel", entropy: 0.35, confidence: 0.88, mode: "radio" });
  }
}

const OUTBOX_STORE = "pending-sends";
let activeStreamAbort = null;

function closeChatStream() {
  if (!activeStreamAbort) return;
  try { activeStreamAbort.abort(); } catch (err) { window.MASTER_LOG?.warn?.("chat:abort", err); }
  activeStreamAbort = null;
  window._chatEvtSrc = null;
}

function dispatchSseBlock(block, handlers) {
  if (!block.trim() || block.trimStart().startsWith(":")) return;
  let event = "message";
  const dataLines = [];
  block.split("\n").forEach((line) => {
    if (line.startsWith("event:")) event = line.slice(6).trim();
    else if (line.startsWith("data:")) dataLines.push(line.slice(5).replace(/^ /, ""));
  });
  const data = dataLines.join("\n");
  if (event === "message") {
    if (/booting/i.test(data) && /retry/i.test(data)) {
      window.MASTER_CONTAINER_READY = false;
      window.MASTER_CONTAINER?.pollStatus?.();
    }
    handlers.onMessage?.(data);
    return;
  }
  if (handlers.onNamed) handlers.onNamed(event, data);
  else window.MASTER_SSE?.dispatchNamed?.(event, data, handlers.extensions);
}

async function openChatStream({ message, state, preEnhanced, imageToken, signal, handlers }) {
  const form = new FormData();
  form.append("message", message);
  if (window.MASTER_ACTIVE_DOMAIN) form.append("active_domain", window.MASTER_ACTIVE_DOMAIN);
  const felt = state || validatedFeltState();
  if (felt) form.append("state", felt);
  if (preEnhanced) form.append("pre_enhanced", "1");
  if (imageToken) form.append("image_token", imageToken);

  const resp = await fetch("/chat/message", {
    method: "POST",
    headers: { Accept: "text/event-stream", "X-CSRF-Token": csrfToken() },
    body: form,
    signal
  });
  if (!resp.ok) throw new Error(`chat stream ${resp.status}`);

  const reader = resp.body?.getReader?.();
  if (!reader) throw new Error("chat stream unreadable");

  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let splitAt;
    while ((splitAt = buf.indexOf("\n\n")) >= 0) {
      const block = buf.slice(0, splitAt);
      buf = buf.slice(splitAt + 2);
      dispatchSseBlock(block, handlers);
    }
  }
  if (buf.trim()) dispatchSseBlock(buf, handlers);
}

async function queueOfflineSend(text) {
  if (!window.indexedDB) return false;
  const db = await new Promise((resolve, reject) => {
    const req = indexedDB.open("master-session", 2);
    req.onupgradeneeded = () => {
      const database = req.result;
      if (!database.objectStoreNames.contains(OUTBOX_STORE)) {
        database.createObjectStore(OUTBOX_STORE, { keyPath: "id", autoIncrement: true });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  await new Promise((resolve, reject) => {
    const tx = db.transaction(OUTBOX_STORE, "readwrite");
    tx.objectStore(OUTBOX_STORE).add({ text, ts: Date.now() });
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
  window._chatOnDmesg?.("queued offline");
  return true;
}

async function drainOfflineQueue() {
  if (!navigator.onLine || !window.indexedDB) return;
  const db = await new Promise((resolve) => {
    const req = indexedDB.open("master-session", 2);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => resolve(null);
  });
  if (!db?.objectStoreNames?.contains(OUTBOX_STORE)) return;
  const rows = await new Promise((resolve) => {
    const tx = db.transaction(OUTBOX_STORE, "readonly");
    const getAll = tx.objectStore(OUTBOX_STORE).getAll();
    getAll.onsuccess = () => resolve(getAll.result || []);
    getAll.onerror = () => resolve([]);
  });
  for (const row of rows) {
    await window.sendMessage?.(row.text);
    await new Promise((resolve) => {
      const tx = db.transaction(OUTBOX_STORE, "readwrite");
      tx.objectStore(OUTBOX_STORE).delete(row.id);
      tx.oncomplete = resolve;
    });
  }
}

async function startChatStream(payload, handlers) {
  closeChatStream();
  const ac = new AbortController();
  activeStreamAbort = ac;
  window._chatEvtSrc = { close: () => closeChatStream() };
  try {
    await openChatStream({ ...payload, signal: ac.signal, handlers });
  } catch (err) {
    if (err?.name === "AbortError") return;
    handlers.onError?.(err);
    throw err;
  } finally {
    if (activeStreamAbort === ac) {
      activeStreamAbort = null;
      window._chatEvtSrc = null;
    }
  }
}

async function sendMessage(text) {
  const input = chatInput();
  const message = String(text ?? input?.value ?? "").trim();
  if (!message) return false;
  if (window.MASTER_FACE?.sendMessage && window.MASTER_FACE.sendMessage !== sendMessage) {
    return window.MASTER_FACE.sendMessage(message);
  }
  if (!navigator.onLine) {
    const queued = await queueOfflineSend(message);
    if (queued) return true;
  }
  if (isBangCommand(message) && message.length > 1) return runSlashCommand(`/shell ${message.slice(1).trim()}`);
  if (message.startsWith("/")) return runSlashCommand(message);

  window._chatOnUser?.(message);
  const enhanced = await enhanceMessage(message);
  const imageToken = window._imageToken || null;
  window._imageToken = null;
  let assistantBuffer = "";
  let ttsBuffer = "";
  const sentenceBreak = /([.!?…]+["'\u201D]?\s+|[\n]{2,})/;
  // Clause boundaries, used only for the very first thing said in a reply, and
  // split into two because they break in opposite directions. Punctuation ends a
  // clause, so the cut goes AFTER it. A conjunction begins one, so the cut goes
  // BEFORE it — cutting after left the opener trailing a dangling "and", which
  // is not where anyone pauses.
  const clausePunct = /[,;:—–]\s+/;
  const clauseJoin = /\s+(?:and|but|so|because|which|that|when|if)\s+/i;
  let spokeFirst = false;

  // Time to first sound is what makes a reply feel immediate, and synthesis
  // time scales with how much text you hand the engine. Waiting for a whole
  // sentence means a 25-word opener is synthesized before anything is heard;
  // cutting the FIRST utterance at a clause starts the voice on a handful of
  // words while the rest of the sentence is still arriving. Everything after
  // that uses whole sentences, so phrasing settles immediately and only the
  // opening is clipped short.
  //
  // Bounded on both sides deliberately: under MIN_FIRST_CHARS a fragment is too
  // short to read as speech rather than a noise, and past MAX_FIRST_CHARS we
  // stop waiting for a tidy boundary and start talking anyway.
  const MIN_FIRST_CHARS = 24;
  const MAX_FIRST_CHARS = 90;
  const firstChunkCut = () => {
    if (spokeFirst || ttsBuffer.trim().length < MIN_FIRST_CHARS) return -1;
    const tail = ttsBuffer.slice(MIN_FIRST_CHARS);
    const punct = tail.match(clausePunct);
    const join = tail.match(clauseJoin);
    // Whichever boundary comes first wins; punctuation keeps its mark, a
    // conjunction is handed to the next chunk.
    if (punct && (!join || punct.index <= join.index)) {
      return MIN_FIRST_CHARS + punct.index + punct[0].length;
    }
    if (join) return MIN_FIRST_CHARS + join.index;
    if (ttsBuffer.length >= MAX_FIRST_CHARS) {
      // No boundary in range — break at a word edge, never mid-word.
      const space = ttsBuffer.lastIndexOf(' ', MAX_FIRST_CHARS);
      return space > MIN_FIRST_CHARS ? space + 1 : -1;
    }
    return -1;
  };

  const flushSpeech = (force = false) => {
    let match;
    while ((match = ttsBuffer.match(sentenceBreak)) || (force && ttsBuffer.trim())) {
      const cut = match ? match.index + match[0].length : ttsBuffer.length;
      const sentence = ttsBuffer.slice(0, cut).trim();
      ttsBuffer = ttsBuffer.slice(cut);
      if (sentence) { window.MASTERVoice?.enqueue?.(sentence); spokeFirst = true; }
      if (!match) break;
    }
    if (force) return;
    const early = firstChunkCut();
    if (early > 0) {
      const opener = ttsBuffer.slice(0, early).trim();
      ttsBuffer = ttsBuffer.slice(early);
      if (opener) { window.MASTERVoice?.enqueue?.(opener); spokeFirst = true; }
    }
  };

  try {
    await startChatStream({
      message: enhanced.text,
      state: validatedFeltState(),
      preEnhanced: enhanced.preEnhanced,
      imageToken
    }, {
      onMessage(rawData) {
        const raw = rawData || "";
        if (raw === "[DONE]") {
          flushSpeech(true);
          window.MASTERVoice?.setLastText?.(assistantBuffer);
          window._chatOnDone?.();
          return;
        }
        if (raw.startsWith("ERROR:")) {
          flushSpeech(true);
          window._chatOnChunk?.(`\n${raw}\n`);
          window._chatOnError?.("stream error");
          return;
        }
        const chunk = raw.replace(/\\n/g, "\n").replace(/\\\\/g, "\\");
        assistantBuffer += chunk;
        ttsBuffer += chunk;
        window._chatOnChunk?.(chunk);
        flushSpeech(false);
      },
      onNamed(event, data) {
        window.MASTER_SSE?.dispatchNamed?.(event, data);
        window.MASTERVisual?.event?.(`sse:${event}`, { raw: data, mode: event });
      },
      onError(err) {
        flushSpeech(true);
        window._chatOnError?.(err?.message || "stream interrupted");
      }
    });
  } catch (_) {
    return false;
  }
  return true;
}

window.MASTERChat = {
  enhanceMessage,
  isBangCommand,
  collectFeltState,
  triggerClientAction,
  queueOfflineSend,
  drainOfflineQueue,
  openChatStream,
  startChatStream,
  sendMessage,
  closeChatStream
};

window.addEventListener("online", () => { drainOfflineQueue().catch((err) => { window.MASTER_LOG?.warn?.("chat:offline_drain", err); }); });
window.addEventListener('compaction', (ev) => {
  window._chatOnCompaction?.(ev.detail || {});
});

function startMic(btn) {
  if (window.MASTER_FACE?.startSTT) {
    window.MASTER_FACE.startSTT();
    btn?.classList?.add("active");
    return;
  }
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const input = chatInput();
  if (!SR) { if (input) input.placeholder = "mic unavailable in this browser"; return; }
  if (btn._rec) { try { btn._rec.stop(); } catch (err) { window.MASTER_LOG?.warn?.("chat:mic_stop", err); } btn._rec = null; btn.classList.remove("active"); return; }
  const rec = new SR();
  rec.lang = navigator.language || "en-US";
  rec.continuous = false;
  rec.interimResults = true;
  rec.onresult = (ev) => {
    let s = "";
    for (let i = 0; i < ev.results.length; i++) s += ev.results[i][0].transcript;
    if (input) input.value = s.trim();
  };
  rec.onerror = () => { btn._rec = null; btn.classList.remove("active"); };
  rec.onend = () => { btn._rec = null; btn.classList.remove("active"); };
  rec.start();
  btn._rec = rec;
  btn.classList.add("active");
}

window.collectFeltState = collectFeltState;
if (!window.sendMessage) window.sendMessage = sendMessage;
