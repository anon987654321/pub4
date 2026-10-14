// Optional spatial workspace behind the canonical face.
// Data is separate from conversation text and persists only when the user opts in.
(() => {
  "use strict";

  const KEY = "master:workspace:v1";
  let root = null;
  let selected = null;
  const memory = { nodes: [], relationships: [], version: 0 };

  function enabled() {
    try {
      const q = new URLSearchParams(location.search);
      return q.get("workspace") === "1" || localStorage.getItem("master:workspace") === "1";
    } catch (_) { return false; }
  }

  function persist() {
    if (!enabled()) return;
    try { localStorage.setItem(KEY, JSON.stringify(memory)); } catch (_) {}
  }

  function loadStored() {
    try {
      const value = JSON.parse(localStorage.getItem(KEY) || "{}");
      if (Array.isArray(value.nodes)) memory.nodes = value.nodes;
      if (Array.isArray(value.relationships)) memory.relationships = value.relationships;
      memory.version = Number(value.version || 0);
    } catch (_) {}
  }

  function ensureRoot() {
    if (root?.isConnected) return root;
    root = document.getElementById("master-workspace");
    if (!root) {
      root = document.createElement("section");
      root.id = "master-workspace";
      root.className = "master-workspace";
      root.hidden = true;
      root.setAttribute("aria-label", "MASTER workspace");
      root.tabIndex = -1;
      document.body.appendChild(root);
    }
    return root;
  }

  function nodeElement(node) {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "master-workspace-node";
    item.dataset.nodeId = node.id;
    item.setAttribute("aria-label", String(node.label || node.kind));
    item.style.insetInlineStart = node.x + "px";
    item.style.insetBlockStart = node.y + "px";
    item.textContent = node.label || node.kind;
    item.addEventListener("click", () => select(node.id));
    return item;
  }

  function render() {
    const host = ensureRoot();
    host.replaceChildren();
    if (!enabled()) { host.hidden = true; return; }
    host.hidden = false;
    memory.nodes.forEach((node) => host.appendChild(nodeElement(node)));
    if (selected) host.dataset.selected = selected;
  }

  function add(kind, data = {}, provenance = {}) {
    const node = {
      id: globalThis.crypto?.randomUUID?.() || "node-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8),
      kind: String(kind || "object"),
      label: String(data.label || kind || "object"),
      x: Number(data.x || 24), y: Number(data.y || 24),
      version: 1, createdAt: Date.now(), updatedAt: Date.now(),
      provenance: { ...provenance }, data: { ...data }
    };
    memory.nodes.push(node);
    memory.version += 1;
    persist(); render();
    window.MasterInteraction?.emit?.("workspace:node:created", node);
    return node.id;
  }

  function update(id, patch = {}) {
    const node = memory.nodes.find((row) => row.id === id);
    if (!node) return null;
    Object.assign(node, patch, { version: node.version + 1, updatedAt: Date.now() });
    memory.version += 1;
    persist(); render();
    window.MasterInteraction?.emit?.("workspace:node:updated", node);
    return node;
  }

  function remove(id) {
    const index = memory.nodes.findIndex((row) => row.id === id);
    if (index < 0) return false;
    memory.nodes.splice(index, 1);
    memory.relationships = memory.relationships.filter((row) => row.from !== id && row.to !== id);
    if (selected === id) selected = null;
    memory.version += 1;
    persist(); render();
    window.MasterInteraction?.emit?.("workspace:node:removed", { id });
    return true;
  }

  function relate(from, to, relation = "related") {
    if (!memory.nodes.some((n) => n.id === from) || !memory.nodes.some((n) => n.id === to)) return false;
    const row = {
      id: "rel-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 7),
      from, to, relation: String(relation), version: 1, createdAt: Date.now()
    };
    memory.relationships.push(row);
    memory.version += 1;
    persist();
    window.MasterInteraction?.emit?.("workspace:relation:created", row);
    return row.id;
  }

  function select(id) {
    if (!memory.nodes.some((n) => n.id === id)) return false;
    selected = id;
    render();
    window.MasterInteraction?.emit?.("workspace:focus", { id, node: memory.nodes.find((n) => n.id === id) });
    return true;
  }

  function moveSelected(dx, dy) {
    if (!selected) return false;
    const node = memory.nodes.find((n) => n.id === selected);
    if (!node) return false;
    update(selected, { x: Math.max(0, node.x + Number(dx || 0)), y: Math.max(0, node.y + Number(dy || 0)) });
    return true;
  }

  function toggle(on = ensureRoot().hidden) {
    if (!on) {
      try { localStorage.setItem("master:workspace", "0"); } catch (_) {}
    } else {
      try { localStorage.setItem("master:workspace", "1"); } catch (_) {}
    }
    render();
    return !ensureRoot().hidden;
  }

  function install() {
    loadStored(); render();
    document.addEventListener("keydown", (event) => {
      if (!(event.ctrlKey || event.metaKey) || !event.shiftKey || event.key.toLowerCase() !== "w") return;
      if (["INPUT", "TEXTAREA"].includes(event.target?.tagName)) return;
      event.preventDefault();
      toggle(ensureRoot().hidden);
    });
  }

  install();
  window.MASTER_WORKSPACE = Object.freeze({ enabled, add, update, remove, relate, select, moveSelected, toggle, render });
  window.MasterWorkspace = window.MASTER_WORKSPACE;
})();
