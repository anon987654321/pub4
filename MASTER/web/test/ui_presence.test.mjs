// visual_bridge turns MASTER's own events into presence. Nothing turned the
// person into presence, so the face held an attending expression at a tab
// nobody had in front of them.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const feltSource = readFileSync(join(publicDir, "felt_state.js"), "utf8");
const uiSource = readFileSync(join(publicDir, "ui_presence.js"), "utf8");

function load({ withLog = true } = {}) {
  const listeners = { window: {}, document: {} };
  const events = [];
  const html = { dataset: {} };
  const logListeners = {};
  const log = {
    scrollHeight: 1000,
    clientHeight: 200,
    scrollTop: 800,
    addEventListener(type, fn) { (logListeners[type] ||= []).push(fn); },
  };

  const sandbox = {
    window: {
      addEventListener(type, fn) { (listeners.window[type] ||= []).push(fn); },
      dispatchEvent(ev) { events.push(ev); return true; },
      MASTER_LOG: null,
    },
    document: {
      hidden: false,
      readyState: "complete",
      body: { dataset: {} },
      documentElement: { ...html, style: { getPropertyValue: () => "" } },
      addEventListener(type, fn) { (listeners.document[type] ||= []).push(fn); },
      getElementById: (id) => (withLog && id === "chat-log" ? log : null),
    },
    localStorage: { getItem: () => null },
    CustomEvent: class CustomEvent {
      constructor(type, opts = {}) { this.type = type; this.detail = opts.detail; }
    },
  };
  sandbox.window.window = sandbox.window;
  sandbox.window.document = sandbox.document;
  sandbox.window.localStorage = sandbox.localStorage;
  sandbox.window.CustomEvent = sandbox.CustomEvent;

  const ctx = createContext(sandbox);
  runInContext(feltSource, ctx);
  runInContext(uiSource, ctx);

  const fire = (target, type) => (listeners[target][type] || []).forEach((fn) => fn({}));
  return {
    ui: sandbox.window.MASTERUiPresence,
    felt: sandbox.window.MASTERFeltState,
    doc: sandbox.document,
    html: sandbox.document.documentElement,
    log,
    events,
    fire,
    scroll: (top) => { log.scrollTop = top; (logListeners.scroll || []).forEach((fn) => fn({})); },
  };
}

test("a present window is full attention", () => {
  const h = load();
  assert.equal(h.ui.level(), h.ui.LEVELS.PRESENT);
});

test("a hidden tab is no attention and says so", () => {
  const h = load();
  h.doc.hidden = true;
  h.fire("document", "visibilitychange");

  assert.equal(h.ui.level(), h.ui.LEVELS.HIDDEN);
  assert.equal(h.events.at(-1).type, "ui:away");
  assert.equal(h.events.at(-1).detail.attention, 0);
});

// A blurred window is still on screen, often beside an editor. Treating it as
// hidden would say nobody is there when somebody is.
test("a blurred window is reduced attention, not absent", () => {
  const h = load();
  h.fire("window", "blur");

  assert.equal(h.ui.level(), h.ui.LEVELS.BLURRED);
  assert.ok(h.ui.LEVELS.BLURRED > h.ui.LEVELS.HIDDEN);
  assert.equal(h.events.at(-1).type, "ui:away");
});

test("returning restores attention and announces it", () => {
  const h = load();
  h.fire("window", "blur");
  h.fire("window", "focus");

  assert.equal(h.ui.level(), h.ui.LEVELS.PRESENT);
  assert.equal(h.events.at(-1).type, "ui:return");
});

test("scrolling back through the log reads as attention on the conversation", () => {
  const h = load();
  h.scroll(100);

  assert.equal(h.events.at(-1).type, "ui:reading");
  assert.equal(h.ui.level(), h.ui.LEVELS.READING);
});

// A resting scroll position sits a few pixels off the bottom; without slack it
// would flap between reading and live on every frame of momentum.
test("a few pixels off the bottom is still the live edge", () => {
  const h = load();
  h.scroll(790);

  assert.equal(h.ui.level(), h.ui.LEVELS.PRESENT);
  assert.equal(h.events.length, 0, "no crossing, no announcement");
});

test("scrolling within one side of the threshold announces once", () => {
  const h = load();
  h.scroll(100);
  h.scroll(120);
  h.scroll(90);

  assert.equal(h.events.filter((e) => e.type === "ui:reading").length, 1);
});

test("attention reaches the presence store and the root element", () => {
  const h = load();
  h.doc.hidden = true;
  h.fire("document", "visibilitychange");

  assert.equal(h.felt.snapshot().attention, 0);
  assert.equal(h.html.dataset.attention, "0.00");
});

// chat_service.rb splits the felt string by position, so a seventh field would
// shift hist_entropy into arousal's place on the server.
test("attention stays off the positional wire format", () => {
  const h = load();
  h.doc.hidden = true;
  h.fire("document", "visibilitychange");

  assert.equal(h.felt.collectFeltState().split("|").length, h.felt.FIELD_COUNT);
  assert.ok(h.felt.validateFeltState(h.felt.collectFeltState()));
});

test("a shell without a chat log still tracks window attention", () => {
  const h = load({ withLog: false });
  h.fire("window", "blur");

  assert.equal(h.ui.level(), h.ui.LEVELS.BLURRED);
});
