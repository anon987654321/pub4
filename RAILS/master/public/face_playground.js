/* Developer-only face controls. Inert without ?playground=1 or an explicit enable(). */
(() => {
  "use strict";
  const FALLBACK_STATES = Object.freeze(["idle", "listening", "thinking", "working", "speaking", "warning", "error", "sleeping", "ready"]);
  const CONTRACT_STATES = window.MASTER_FACE_CONTRACT?.state?.modes;
  const STATES = Object.freeze(Array.from(new Set(
    (Array.isArray(CONTRACT_STATES) ? CONTRACT_STATES : FALLBACK_STATES)
      .map((name) => String(name).toLowerCase())
      .filter((name) => /^[a-z][a-z0-9_-]{0,31}$/.test(name))
  )));
  let panel = null;
  const el = (tag, text) => {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    return node;
  };

  function slider(label, min, max, value, key, step = 0.01) {
    const row = el("label");
    row.className = "master-stipple-field";
    const title = el("span", label);
    const input = el("input");
    input.type = "range";
    input.min = String(min); input.max = String(max); input.step = String(step); input.value = String(value);
    const output = el("output", Number(value).toFixed(2));
    input.addEventListener("input", () => {
      output.value = Number(input.value).toFixed(2);
      window.MASTER_FACE_STIPPLE?.configure({ [key]: Number(input.value) });
    });
    row.append(title, input, output);
    return row;
  }

  function setState(name) {
    const value = String(name || "").toLowerCase();
    if (!STATES.includes(value)) return false;
    const bridge = window.MASTER_FACE_STATE;
    if (typeof bridge?.setMode === "function") {
      bridge.setMode(value, { source: "face-playground" });
    } else {
      // Compatibility for older face shells without the canonical state bridge.
      const state = window.MASTER_FACE?.State;
      if (state) { state.mode = value; state.mood = value; }
    }
    window.dispatchEvent(new CustomEvent("master:stipple-state", { detail: { mode: value, source: "face-playground" } }));
    return true;
  }

  function enable(force = false) {
    if (!force && new URLSearchParams(location.search).get("playground") !== "1") return false;
    if (panel?.isConnected) return true;
    if (!window.MASTER_FACE_STIPPLE) {
      window.setTimeout(() => enable(force), 250);
      return false;
    }

    panel = el("aside");
    panel.className = "master-face-stipple-playground";
    panel.setAttribute("aria-label", "Face stipple developer playground");
    const title = el("strong", "Face stipple");
    const stateLabel = el("label", "State");
    const select = el("select");
    select.setAttribute("aria-label", "Stipple test state");
    STATES.forEach((name) => select.append(el("option", name)));
    select.addEventListener("change", () => setState(select.value));
    const status = el("p", "Additive layer; ParticleKernel retained");
    status.className = "master-stipple-status";
    status.setAttribute("aria-live", "polite");
    const diagnostics = el("pre", "Use Refresh diagnostics to inspect the current renderer state.");
    diagnostics.id = "master-face-stipple-diagnostics";
    diagnostics.className = "master-stipple-diagnostics";
    diagnostics.setAttribute("aria-label", "Face stipple runtime diagnostics");
    const refresh = el("button", "Refresh diagnostics");
    refresh.type = "button";
    refresh.setAttribute("aria-controls", diagnostics.id);
    refresh.addEventListener("click", () => {
      const report = window.MASTER_FACE_STIPPLE?.snapshot?.();
      diagnostics.textContent = report ? JSON.stringify(report, null, 2) : "Diagnostics unavailable";
      status.textContent = report ? "Diagnostics refreshed." : "Diagnostics unavailable.";
    });
    const close = el("button", "Close");
    close.type = "button";
    close.addEventListener("click", () => { panel?.remove(); panel = null; });
    stateLabel.append(select);
    panel.append(title, stateLabel, status, refresh, diagnostics,
      slider("Density", 0.08, 0.98, 0.44, "density"),
      slider("Ripple", 0, 1, 0.03, "ripple"),
      slider("Turbulence", 0, 1, 0.04, "turbulence"),
      slider("Luminosity", 0.2, 1.2, 0.76, "luminosity"),
      slider("Opacity", 0.1, 1, 0.74, "opacity"), close);
    document.body.append(panel);
    setState("idle");
    return true;
  }

  window.FacePlayground = Object.freeze({ enable, setState, states: STATES });
  if (new URLSearchParams(location.search).get("playground") === "1") {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => enable(true), { once: true });
    else enable(true);
  }
})();
