// MASTER face state bridge: status text drives body masterState.
(() => {
  function classify(text, attr) {
    const raw = `${attr || ""} ${text || ""}`.toLowerCase();
    if (/fail|error|blocked|unsafe|abort|crit|phantom/.test(raw)) return "fail";
    if (/warn|risk|careful|retry|fallback/.test(raw)) return "warn";
    if (/busy|thinking|running|loading|stream|agent|model|working|stage/.test(raw)) return "busy";
    return "idle";
  }

  function applyFrom(el) {
    if (!el) return;
    const state = classify(el.textContent, el.dataset.runtimeStatus);
    el.dataset.runtimeStatus = state;
    document.body.dataset.masterState = state;
    document.body.dataset.visualRuntime = state === "fail" ? "frozen" : "rails";
  }

  function apply() {
    applyFrom(document.getElementById("status"));
    applyFrom(document.getElementById("ui-status"));
    const stage = document.getElementById("pipeline-stage");
    if (stage?.textContent) applyFrom(stage);
  }

  function observe(el) {
    if (!el) return;
    new MutationObserver(apply).observe(el, { childList: true, subtree: true, characterData: true, attributes: true });
  }

  window.addEventListener("DOMContentLoaded", () => {
    observe(document.getElementById("status"));
    observe(document.getElementById("ui-status"));
    observe(document.getElementById("pipeline-stage"));
    apply();
  });
})();