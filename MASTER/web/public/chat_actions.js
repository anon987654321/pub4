"use strict";

function chatInput() {
  return document.getElementById("zin");
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || "";
}

function feltCssNumber(name, fallback) {
  const raw = document.documentElement.style.getPropertyValue(name);
  const parsed = parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function collectFeltState() {
  if (typeof window.MASTER_FACE?.collectFeltState === "function") {
    return window.MASTER_FACE.collectFeltState();
  }
  const st = window.MASTER_FACE?.State || {};
  const mood = (st.mood || document.body.dataset.masterState || "idle").toString();
  const mode = (st.mode || document.body.dataset.pipelineStage || "idle").toString();
  const entropy = Number.isFinite(st.entropy) ? st.entropy : feltCssNumber("--master-entropy", 0.2);
  const confidence = Number.isFinite(st.confidence) ? st.confidence : feltCssNumber("--master-confidence", 0.86);
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

function loopsMusicUrl() {
  return window.MASTER_ASSET_PATHS?.faceModules?.["face_loops_music.js"] || "/face_loops_music.js";
}

function triggerClientAction(data) {
  if (!data?.action) return;
  if (data.action === "dilla_bg") {
    import(loopsMusicUrl())
      .then(() => { window._dillaBg?.(); })
      .catch(() => {});
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
  try { activeStreamAbort.abort(); } catch (_) {}
  activeStreamAbort = null;
  window._chatEvtSrc = null;
}

function dispatchSseBlock(block, handlers) {
  if (!block.trim() || block.trimStart().startsWith(":")) return;
  let event = "message";
  const dataLines = [];
  block.split("\n").forEach((line) => {
    if (line.startsWith("event:")) event = line.slice(6).trim();
    else if (line.startsWith("data:")) dataLines.push(line.slice(5).trimStart());
  });
  const data = dataLines.join("\n");
  if (event === "message") handlers.onMessage?.(data);
  else handlers.onNamed?.(event, data);
}

async function openChatStream({ message, state, preEnhanced, imageToken, signal, handlers }) {
  const form = new FormData();
  form.append("message", message);
  if (state) form.append("state", state);
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

window.MASTERChat = {
  enhanceMessage,
  collectFeltState,
  triggerClientAction,
  queueOfflineSend,
  drainOfflineQueue,
  openChatStream,
  startChatStream,
  closeChatStream
};

window.addEventListener("online", () => { drainOfflineQueue().catch(() => {}); });

function startMic(btn) {
  if (window.MASTER_FACE?.startSTT) {
    window.MASTER_FACE.startSTT();
    btn?.classList?.add("active");
    return;
  }
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const input = chatInput();
  if (!SR) { if (input) input.placeholder = "mic unavailable in this browser"; return; }
  if (btn._rec) { try { btn._rec.stop(); } catch (_) {} btn._rec = null; btn.classList.remove("active"); return; }
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
window.sendMessage = (text) => window.MASTER_FACE?.sendMessage?.(text);