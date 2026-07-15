import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const fsmSource = readFileSync(join(publicDir, "boot_fsm.js"), "utf8");

function loadBootFsm(now = 1000) {
  let clock = now;
  const listeners = {};
  const body = { dataset: {} };
  const html = { dataset: {} };
  const sandbox = {
    window: {
      addEventListener(type, fn) {
        (listeners[type] ||= []).push(fn);
      },
      dispatchEvent(ev) {
        (listeners[ev.type] || []).forEach((fn) => fn(ev));
        return true;
      },
      MASTER: {},
      MASTER_LOG: null,
      performance: { now: () => clock },
    },
    document: {
      body,
      documentElement: html,
      querySelector: () => null,
    },
    console: { debug: () => {} },
    performance: { now: () => clock },
    CustomEvent: class CustomEvent {
      constructor(type, opts = {}) {
        this.type = type;
        this.detail = opts.detail;
      }
    },
  };
  sandbox.window.window = sandbox.window;
  sandbox.window.document = sandbox.document;
  sandbox.window.CustomEvent = sandbox.CustomEvent;
  sandbox.window.performance = sandbox.performance;

  runInContext(fsmSource, createContext(sandbox));
  const boot = sandbox.window.MASTER.boot;
  return { boot, body, html, advance: (ms) => { clock += ms; } };
}

test("boot fsm happy path reaches READY when all gates signal", () => {
  const { boot, body } = loadBootFsm();
  assert.equal(boot.state(), "INIT");
  assert.ok(boot.transition("PRIMER", { source: "test" }));
  assert.ok(boot.transition("ASSETS", { source: "test" }));
  assert.ok(boot.transition("FACE", { source: "test" }));
  assert.ok(boot.transition("VOICE", { source: "test" }));
  assert.equal(boot.state(), "VOICE");
  boot.signal("voice_ready", { source: "test" });
  boot.signal("face_ready", { source: "test" });
  boot.signal("container_ready", { source: "test" });
  assert.equal(boot.state(), "READY");
  assert.equal(body.dataset.bootState, "READY");
});

test("boot fsm rejects illegal transitions", () => {
  const { boot } = loadBootFsm();
  assert.equal(boot.state(), "INIT");
  assert.equal(boot.transition("FACE", { source: "test" }), false);
  assert.equal(boot.state(), "INIT");
});

test("boot fsm retry path uses RECOVERING", () => {
  const { boot } = loadBootFsm();
  boot.transition("PRIMER");
  boot.transition("ASSETS");
  assert.ok(boot.transition("RECOVERING", { source: "retry" }));
  assert.ok(boot.transition("ASSETS", { source: "retry" }));
  assert.equal(boot.state(), "ASSETS");
});

test("boot fsm renderer_failed enters ERROR from any phase", () => {
  const { boot } = loadBootFsm();
  boot.transition("PRIMER");
  boot.transition("ASSETS");
  boot.signal("renderer_failed", { source: "test" });
  assert.equal(boot.state(), "ERROR");
});

test("boot fsm does not reach READY until all gates are set", () => {
  const { boot } = loadBootFsm();
  boot.transition("PRIMER");
  boot.transition("ASSETS");
  boot.transition("FACE");
  boot.transition("VOICE");
  boot.signal("voice_ready");
  boot.signal("face_ready");
  assert.equal(boot.state(), "VOICE");
  boot.signal("container_ready");
  assert.equal(boot.state(), "READY");
});