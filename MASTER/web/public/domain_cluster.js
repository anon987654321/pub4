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
  { id: "bsdports.org", label: "bsdports" }
];

function nodeActive(label, domainId) {
  if (domainId === "brgen.no") return label === "brgen.no";
  const root = domainId.split(".")[0];
  return label === root;
}

function renderDomainBar() {
  const bar = document.getElementById("domain-cluster-bar");
  if (!bar || bar.dataset.ready === "1") return;
  bar.dataset.ready = "1";
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
}

window.MASTERDomainCluster = { renderDomainBar, switchDomain, nodes: DOMAIN_NODES };

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", renderDomainBar, { once: true });
} else {
  renderDomainBar();
}