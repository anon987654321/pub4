// MASTER face state bridge: text status drives face state, not decoration.
(() => {
  function classify(text, attr) {
    const raw = `${attr || ""} ${text || ""}`.toLowerCase();
    if (/fail|error|blocked|unsafe|abort|crit/.test(raw)) return "fail";
    if (/warn|risk|careful|retry|fallback/.test(raw)) return "warn";
    if (/busy|thinking|running|loading|stream|agent|model|working/.test(raw)) return "busy";
    return "idle";
  }

  function apply() {
    const status = document.getElementById("status");
    if (!status) return;

    const state = classify(status.textContent, status.dataset.runtimeStatus);
    status.dataset.runtimeStatus = state;
    document.body.dataset.masterState = state;
    document.body.dataset.visualRuntime = state === "fail" ? "frozen" : "rails";
  }

  function installProcessShortcut() {
    const face = document.querySelector(".face-plate");
    const input = document.getElementById("input");
    if (!face || !input) return;

    face.setAttribute("role", "button");
    face.setAttribute("tabindex", "0");
    face.setAttribute("aria-label", "Show process status");
    face.addEventListener("click", () => {
      input.value = "/process";
      input.focus();
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    face.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        face.click();
      }
    });
  }

  window.addEventListener("DOMContentLoaded", () => {
    const status = document.getElementById("status");
    if (status) new MutationObserver(apply).observe(status, { childList: true, subtree: true, attributes: true });
    installProcessShortcut();
    apply();
  });
})();
