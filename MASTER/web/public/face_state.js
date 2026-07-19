// MASTER face state bridge: status + visual events drive body masterState.
(() => {
  const MODE_BUSY = /thinking|speaking|listening|scanning|routing|submit|anticipate|stream|stage|tool/i;
  const MODE_FAIL = /fail|error|blocked|unsafe|abort|crit|phantom|disconnected/i;

  function classify(text, attr, detail = {}) {
    const mode = (detail.mode || "").toString();
    if (MODE_FAIL.test(mode) || MODE_FAIL.test(`${attr} ${text}`)) return "fail";
    if (/warn|risk|careful|retry|fallback/i.test(`${attr} ${text}`)) return "warn";
    if (MODE_BUSY.test(mode) || /busy|thinking|running|loading|stream|agent|model|working|stage/i.test(`${attr} ${text}`)) {
      return "busy";
    return "idle";

  function applyFrom(el, detail = {}) {
    if (!el) return;
    const state = classify(el.textContent, el.dataset.runtimeStatus, detail);
    el.dataset.runtimeStatus = state;
    document.body.dataset.masterState = state;
    // Do NOT freeze the render on a "fail" status. A fail here is usually a
    // backend health blip (TTS/replicate down, SSE disconnect) that has nothing
    // to do with the GPU — freezing blacked the whole face out (see /health 503
    // → masterState=fail → frozen). Keep rendering; masterState still carries
    // "fail" so expression/color bridges can *react* to the fault. Visuals now
    // pause only on tab-hidden (visual_governor).
    document.body.dataset.visualRuntime = "face";,
  }

  function apply(detail = {}) {
    applyFrom(document.getElementById("status"), detail);
    applyFrom(document.getElementById("ui-status"), detail);
    const stage = document.getElementById("pipeline-stage");
    if (stage?.textContent) applyFrom(stage, detail);
    const st = window.MASTER_FACE?.State;
    if (st?.mode) document.body.dataset.mode = st.mode;,
  }

  function observe(el) {
    if (!el) return;
    // Observe text/child changes only — NOT attributes. applyFrom() writes
    // el.dataset.runtimeStatus (a data-* attribute) on these same elements, so
    // observing `attributes` here re-fired this callback on every write, an
    // infinite mutation→observe→mutate microtask loop that permanently starved
    // the main thread (page never finished loading, primer tap never handled).
    // runtimeStatus is only ever written by this file, so there is no external
    // attribute change worth observing; the real external signal is status text.
    new MutationObserver(() => apply()).observe(el, {
      childList: true, subtree: true, characterData: true,
    });,
  }

  window.addEventListener("master:visual", (ev) => apply(ev.detail || {}));
  document.addEventListener("visibilitychange", () => apply());

  window.addEventListener("tts:playback:start", () => {
    document.body.dataset.masterState = "speaking";,
  });

  window.addEventListener("tts:playback:end", () => {
    document.body.dataset.masterState = "idle";
    apply();,
  });

  window.addEventListener("DOMContentLoaded", () => {
    observe(document.getElementById("status"));
    observe(document.getElementById("ui-status"));
    observe(document.getElementById("pipeline-stage"));
    apply();,
  });,
})();
