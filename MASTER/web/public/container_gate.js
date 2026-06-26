"use strict";

const SMOKE_MESSAGES = /^(ping|pong|health|up)$/i;
const POLL_MS = 3000;
const MAX_POLLS = 40;

function metaReady() {
  return document.querySelector('meta[name="master-container-ready"]')?.content === "1";
}

function setReady(isReady, detail) {
  window.MASTER_CONTAINER_READY = isReady;
  document.body.dataset.containerReady = isReady ? "1" : "0";
  const input = document.getElementById("zin");
  if (input) {
    input.disabled = !isReady;
    if (!input.dataset.defaultPlaceholder) input.dataset.defaultPlaceholder = input.placeholder || "ask anything";
    input.placeholder = isReady ? input.dataset.defaultPlaceholder : "master warming up…";
  }
  const ui = document.getElementById("ui-status");
  if (ui && !isReady) ui.textContent = "master warming up";
  else if (ui && isReady && (ui.textContent === "master warming up" || ui.textContent === "master still starting…")) {
    ui.textContent = "";
  }
  if (isReady && detail?.model) {
    const chip = document.getElementById("provider-chip");
    if (chip && !chip.textContent) chip.textContent = String(detail.model).slice(0, 12);
  }
  if (isReady) window.dispatchEvent(new CustomEvent("master:container-ready", { detail: detail || {} }));
}

function setWarmupStalled(reason) {
  const ui = document.getElementById("ui-status");
  if (ui) ui.textContent = "master still starting…";
  const errLive = document.getElementById("error-live");
  if (errLive) errLive.textContent = reason || "master warming up — retry shortly";
  window.dispatchEvent(new CustomEvent("master:container-timeout", { detail: { reason } }));
}

async function pollStatus() {
  try {
    const resp = await fetch("/runtime/status");
    if (!resp.ok) {
      if (resp.status === 503) setWarmupStalled("master container booting");
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
  window._chatOnDmesg?.("master warming up");
  const errLive = document.getElementById("error-live");
  if (errLive) errLive.textContent = "master warming up";
  return true;
}

let pollCount = 0;
let pollTimer = null;

async function pollTick() {
  pollCount += 1;
  const ready = await pollStatus();
  if (ready) {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
    return;
  }
  if (pollCount >= MAX_POLLS) {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
    setWarmupStalled("master did not become ready — reload or retry in a minute");
  }
}

setReady(metaReady(), { model: document.querySelector('meta[name="master-model"]')?.content || "booting" });
if (!window.MASTER_CONTAINER_READY) {
  pollTick();
  pollTimer = window.setInterval(pollTick, POLL_MS);
}

window.MASTER_CONTAINER = {
  ready: () => window.MASTER_CONTAINER_READY !== false,
  blockingSend,
  pollStatus
};