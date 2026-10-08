import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

// The inline primer script in chat/index.html.erb, run as shipped. Autostart,
// pointerdown, click, touchend and Enter all call go(); the `fired` guard is
// the only thing standing between a double tap and two face imports, two
// primer dismissals and two PRIMER transitions on boot_fsm.
const view = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "app", "views", "chat", "index.html.erb"), "utf8");

function primerScript() {
  const start = view.indexOf("window.MASTER_CACHE_VERSION");
  const end = view.indexOf("</script>", start);
  assert.ok(start > 0 && end > start, "the primer script moved; this test reads it from the view");
  return view.slice(start, end).replace(/"?<%=.*?%>"?/g, '"v2"');
}

function element(id) {
  const listeners = {};
  const added = [];
  return {
    id,
    added,
    listeners,
    dataset: {},
    textContent: "",
    tabIndex: 0,
    parentNode: null,
    classList: { add: (name) => added.push(name), remove: () => {} },
    addEventListener(type, fn) { (listeners[type] ||= []).push(fn); },
    setAttribute() {},
    getAttribute: () => null,
    remove() {},
    focus() {},
  };
}

function loadPrimer({ search = "" } = {}) {
  const timers = [];
  const transitions = [];
  const primer = element("primer");
  const nodes = { primer, zsh: element("zsh"), "ui-status": element("ui-status"), "primer-title": element("primer-title") };
  const windowListeners = {};
  const sandbox = {
    document: {
      getElementById: (id) => nodes[id] || null,
      body: { classList: { add() {}, remove() {} }, dataset: {} },
    },
    location: { search },
    URLSearchParams,
    CustomEvent: class { constructor(type) { this.type = type; } },
    setTimeout: (fn) => { timers.push(fn); return timers.length; },
    clearTimeout() {},
    setInterval: () => 0,
    clearInterval() {},
    addEventListener(type, fn) { (windowListeners[type] ||= []).push(fn); },
    removeEventListener() {},
    dispatchEvent() { return true; },
    MASTER: { boot: { transition: (phase) => transitions.push(phase) } },
  };
  sandbox.window = sandbox;
  runInContext(primerScript(), createContext(sandbox));
  // Only the autostart timer: the rest are the 8s hint and the 35s watchdog,
  // whose fallback dismisses the primer on purpose when the face never paints.
  const runAutostart = () => timers.shift()();
  return { primer, transitions, runAutostart, sandbox };
}

test("autostart plus every tap event dismisses the primer once", () => {
  const { primer, transitions, runAutostart } = loadPrimer();
  runAutostart();
  for (const type of ["pointerdown", "click", "touchend"]) primer.listeners[type].forEach((fn) => fn({}));

  assert.equal(transitions.filter((p) => p === "PRIMER").length, 1);
  assert.equal(primer.added.filter((c) => c === "gone").length, 1);
});

test("with ?primer=1 the first tap fires and a second tap does nothing", () => {
  const { primer, transitions } = loadPrimer({ search: "?primer=1" });
  assert.equal(transitions.length, 0, "the overlay waits for a tap");

  primer.listeners.pointerdown[0]({});
  primer.listeners.click[0]({});

  assert.equal(transitions.filter((p) => p === "PRIMER").length, 1);
  assert.equal(primer.added.filter((c) => c === "gone").length, 1);
});
