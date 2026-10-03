"use strict";

// Locale text from the view (window.MASTER_T); the fallback is what a page without it shows.
function gateT(key, fallback) {
  return window.MASTER_T ? window.MASTER_T(key, fallback) : fallback;
}

const SMOKE_MESSAGES = /^(ping|pong|health|up)$/i;
const POLL_MS = 3000;
const POLL_MS_FAST = 1000;
const FAST_POLLS = 6;
const MAX_POLLS = 40;

function metaReady() {
  return document.querySelector('meta[name="master-container-ready"]')?.content === "1";
}

function setReady(isReady, detail) {
  window.MASTER_CONTAINER_READY = isReady;
  document.body.dataset.containerReady = isReady ? "1" : "0";
  let readyMeta = document.querySelector('meta[name="master-container-ready"]');
  if (isReady) {
    if (!readyMeta) {
      readyMeta = document.createElement('meta');
      readyMeta.name = 'master-container-ready';
      document.head.appendChild(readyMeta);
    }
    readyMeta.content = '1';
  } else if (readyMeta) {
    readyMeta.content = '0';
  }
  const input = document.getElementById("zin");
  if (input) {
    input.disabled = !isReady;
    if (!input.dataset.defaultPlaceholder) input.dataset.defaultPlaceholder = input.placeholder || "ask anything";
    input.placeholder = isReady ? input.dataset.defaultPlaceholder : gateT("warming_up_placeholder", "master warming up…");
  }
  const ui = document.getElementById("ui-status");
  const warming = gateT("warming_up", "master warming up");
  if (ui && !isReady) ui.textContent = warming;
  else if (ui && isReady && (ui.textContent === warming || ui.textContent === gateT("still_starting", "master still starting…"))) {
    ui.textContent = "";
  }
  if (isReady && detail?.model) {
    const chip = document.getElementById("provider-chip");
    if (chip && !chip.textContent) chip.textContent = String(detail.model).slice(0, 12);
    document.documentElement.dataset.modelProvider = String(detail.model).slice(0, 24);
  }
  if (detail?.build) document.documentElement.dataset.build = String(detail.build).slice(0, 12);
  if (isReady) {
    window.MASTER?.boot?.signal?.("container_ready", { source: "container_gate", ...detail });
    window.dispatchEvent(new CustomEvent("master:container-ready", { detail: detail || {} }));
  } else {
    window.MASTER?.boot?.signal?.("container_warmup", { source: "container_gate" });
  }
}

function ensureRetryBootButton() {
  let btn = document.getElementById("master-retry-boot");
  if (btn) return btn;
  btn = document.createElement("button");
  btn.id = "master-retry-boot";
  btn.type = "button";
  btn.className = "tool master-retry-boot";
  btn.textContent = gateT("retry_boot", "retry boot");
  btn.addEventListener("click", () => {
    pollCount = 0;
    if (pollTimer) clearTimeout(pollTimer);
    pollTimer = null;
    window.MASTER?.boot?.transition?.("RECOVERING", { source: "retry_boot_button" });
    pollTick();
    const ui = document.getElementById("ui-status");
    if (ui) ui.textContent = gateT("retrying_boot", "retrying boot…");
  });
  const shell = document.getElementById("zsh") || document.body;
  shell.appendChild(btn);
  return btn;
}

function setWarmupStalled(reason) {
  const ui = document.getElementById("ui-status");
  if (ui) ui.textContent = gateT("still_starting", "master still starting…");
  const errLive = document.getElementById("error-live");
  if (errLive) errLive.textContent = reason || gateT("warming_retry", "master warming up — retry shortly");
  ensureRetryBootButton();
  window.dispatchEvent(new CustomEvent("master:container-timeout", { detail: { reason } }));
}

async function pollStatus() {
  try {
    const resp = await fetch("/runtime/status");
    if (!resp.ok) {
      if (resp.status === 503) setWarmupStalled(gateT("container_booting", "master container booting"));
      return false;
    }
    const data = await resp.json();
    setReady(!!data.ready, data);
    return !!data.ready;
  } catch (err) {
    window.MASTER_LOG?.warn?.("container_gate:poll", err);
    return false;
  }
}

function blockingSend(text) {
  if (window.MASTER_CONTAINER_READY !== false) return false;
  if (SMOKE_MESSAGES.test(String(text || "").trim())) return false;
  const warming = gateT("warming_up", "master warming up");
  window._chatOnDmesg?.(warming);
  const errLive = document.getElementById("error-live");
  if (errLive) errLive.textContent = warming;
  return true;
}

let pollCount = 0;
let pollTimer = null;

function pollIntervalMs() {
  return pollCount < FAST_POLLS ? POLL_MS_FAST : POLL_MS;
}

function schedulePollTick() {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = window.setTimeout(async () => {
    pollTimer = null;
    await pollTick();
  }, pollIntervalMs());
}

async function pollTick() {
  pollCount += 1;
  const ready = await pollStatus();
  if (ready) return;
  if (pollCount >= MAX_POLLS) {
    setWarmupStalled(gateT("not_ready", "master did not become ready — reload or retry in a minute"));
    return;
  }
  schedulePollTick();
}

setReady(metaReady(), { model: document.querySelector('meta[name="master-model"]')?.content || "booting" });
if (!window.MASTER_CONTAINER_READY) pollTick();

window.MASTER_CONTAINER = {
  ready: () => window.MASTER_CONTAINER_READY !== false,
  blockingSend,
  pollStatus
};
