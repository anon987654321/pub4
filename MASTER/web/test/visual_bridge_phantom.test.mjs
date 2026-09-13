// visual_bridge.js turns the bus's phantom topics into a flinch on the face.
// The bus publishes detected, halt, occurrence and recovery; phantom:retry was
// never a topic, so the handler is driven with what the bus actually sends.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const bridgeSource = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");

function loadBridge() {
  const dispatched = [];
  const element = () => ({ dataset: {}, style: { setProperty: () => {} } });
  const document = {
    hidden: false,
    body: element(),
    documentElement: element(),
    head: { appendChild: () => {} },
    getElementById: () => null,
    createElement: element,
    addEventListener: () => {},
  };
  class CustomEvent {
    constructor(type, init = {}) {
      this.type = type;
      this.detail = init.detail;
    }
  }
  const window = {
    document,
    location: { search: "", protocol: "https:", host: "test" },
    dispatchEvent: (event) => dispatched.push(event),
    addEventListener: () => {},
  };
  window.window = window;
  const sandbox = {
    window, document, CustomEvent, URLSearchParams,
    requestAnimationFrame: () => 1,
    setTimeout: () => 0,
    setInterval: () => 0,
    clearInterval: () => {},
    addEventListener: () => {},
  };
  runInContext(bridgeSource, createContext(sandbox));
  return { visual: window.MASTERVisual, dispatched };
}

test("a phantom topic from the bus makes the face flinch", () => {
  const { visual, dispatched } = loadBridge();

  visual.runtime({ type: "phantom:detected" });

  const flinch = dispatched.find((event) => event.type === "master:visual" && event.detail?.mode === "phantom");
  assert.ok(flinch, "phantom:detected dispatched no phantom visual");
  assert.equal(flinch.detail.flinch, 1);
  assert.equal(flinch.detail.name, "phantom:detected");
});

test("halt and recovery flinch too, and a topic the bus never sends does not", () => {
  for (const type of ["phantom:halt", "phantom:recovery"]) {
    const { visual, dispatched } = loadBridge();
    visual.runtime({ type });
    assert.ok(dispatched.some((event) => event.detail?.mode === "phantom" && event.detail?.flinch === 1), type);
  }

  const { visual, dispatched } = loadBridge();
  visual.runtime({ type: "phantom:retry" });
  assert.equal(dispatched.some((event) => event.detail?.flinch === 1), false);
});
