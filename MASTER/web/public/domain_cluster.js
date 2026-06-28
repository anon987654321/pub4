"use strict";

const DOMAIN_NODES = [
  { id: "brgen.no", label: "brgen.no" },
  { id: "marketplace.brgen.no", label: "marketplace" },
  { id: "playlist.brgen.no", label: "playlist" },
  { id: "takeaway.brgen.no", label: "takeaway" },
  { id: "tv.brgen.no", label: "tv" },
  { id: "messenger.brgen.no", label: "messages" },
  { id: "maps.brgen.no", label: "maps" },
  { id: "amber.brgen.no", label: "amber" },
  { id: "hjerterom.no", label: "hjerterom" },
  { id: "baibl.brgen.no", label: "baibl" },
  { id: "blognet.brgen.no", label: "blognet" },
  { id: "bsdports.org", label: "bsdports" }
];

function nodeActive(label, domainId) {
  if (domainId === "brgen.no") return label === "brgen.no";
  const root = domainId.split(".")[0];
  return label === root;
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || "";
}

async function syncDomainBackend(domainId) {
  const key = domainId.split(".")[0];
  const status = document.getElementById("zsh-status");
  try {
    const res = await fetch("/chat/command", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify({ command: `/domain ${key}` }),
      credentials: "same-origin"
    });
    if (!res.ok) {
      if (status) status.textContent = `domain ${key}: sync deferred`;
      return;
    }
    const data = await res.json();
    const line = (data.output || "").split("\n").find(Boolean) || `domain ${key} ok`;
    if (status) status.textContent = line.slice(0, 96);
    window.MASTERVisual?.event?.("domain:sync", {
      topology: "cluster",
      entropy: 0.12,
      confidence: 0.86,
      domain: domainId,
      output: line.slice(0, 200)
    });
  } catch (err) {
    window.MASTER_LOG?.warn?.("domain:sync", err);
    if (status) status.textContent = `domain ${key}: offline`;
  }
}

function renderDomainBar() {
  const bar = document.getElementById("domain-cluster-bar");
  if (!bar || bar.dataset.ready === "1") return;
  bar.dataset.ready = "1";
  const stored = localStorage.getItem("master_active_domain");
  if (stored) window.MASTER_ACTIVE_DOMAIN = stored;
  bar.innerHTML = DOMAIN_NODES.map((node) => {
    const active = node.id === (window.MASTER_ACTIVE_DOMAIN || "brgen.no") ? " active" : "";
    return `<button type="button" class="domain-node${active}" data-domain="${node.id}">${node.label}</button>`;
  }).join("");
  bar.addEventListener("click", (e) => {
    const btn = e.target.closest(".domain-node");
    if (!btn) return;
    switchDomain(btn.dataset.domain);
  });
}

function switchDomain(domainId) {
  window.MASTER_ACTIVE_DOMAIN = domainId;
  try { localStorage.setItem("master_active_domain", domainId); } catch (_) {}
  document.querySelectorAll("#domain-cluster-bar .domain-node").forEach((el) => {
    el.classList.toggle("active", nodeActive(el.textContent.trim(), domainId));
  });
  const status = document.getElementById("zsh-status");
  if (status) status.textContent = domainId;
  window.MASTERVisual?.event?.("domain:switch", { topology: "cluster", entropy: 0.18, confidence: 0.9, domain: domainId });
  const input = document.getElementById("zin");
  if (input && document.activeElement !== input) {
    input.placeholder = `ask anything (${domainId.split(".")[0]})`;
  }
  if (document.body.classList.contains("face-session")) syncDomainBackend(domainId);
}

window.MASTERDomainCluster = { renderDomainBar, switchDomain, syncDomainBackend, nodes: DOMAIN_NODES };

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", renderDomainBar, { once: true });
} else {
  renderDomainBar();
}

document.addEventListener("master:session-ready", () => {
  if (window.MASTER_ACTIVE_DOMAIN) syncDomainBackend(window.MASTER_ACTIVE_DOMAIN);
}, { once: true });