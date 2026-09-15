// visual_bridge.js reacts to bus topics that arrive on /events/stream. A name
// it listens for that nothing publishes is a reaction that never happens, and
// the source reads as though it does. The handlers are driven with what the bus
// actually sends, and every topic the bridge tests for is held against the
// topics MASTER's Ruby publishes.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const masterDir = join(publicDir, "..", "..");
const bridgeSource = readFileSync(join(publicDir, "visual_bridge.js"), "utf8");

const TOPIC = /\b[a-z][a-z0-9_]*:[a-z0-9_]+(?::[a-z0-9_]+)*/g;

// Names the bridge tests for that are not bus topics, each with its reason. An
// entry that stops appearing in the bridge fails the test, so none outlives
// its subject.
const NOT_BUS_TOPICS = {
  "runtime:event": "the type handleRuntimeEvent gives a frame that names none",
};

function publishedTopics() {
  const topics = new Set();
  for (const tree of ["lib", "web/app", "web/lib"]) {
    const base = join(masterDir, tree);
    for (const name of readdirSync(base, { recursive: true })) {
      if (!name.endsWith(".rb")) continue;
      const code = readFileSync(join(base, name), "utf8").replace(/^\s*#.*$/gm, "");
      for (const match of code.matchAll(/\bpublish!?\(?\s*["']([a-z][a-z0-9_]*:[a-z0-9_:]+)/g)) topics.add(match[1]);
      for (const match of code.matchAll(/\bevent:\s*["']([a-z][a-z0-9_]*:[a-z0-9_:]+)["']/g)) topics.add(match[1]);
    }
  }
  return topics;
}

// The topic names the bridge compares an incoming type against. Comments go
// first, because a comment naming a removed topic is prose about it. Names the
// bridge mints itself go next: a CustomEvent it dispatches or listens to on the
// window, a visual it emits and a log context are page events, not topics it
// waits for. A regex alternation such as rule_loop:(pass|error) stands for one
// name per branch.
function bridgeListenerNames() {
  const code = bridgeSource
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'`\\])\/\/.*$/gm, "$1")
    .replace(/(?:new CustomEvent|addEventListener)\(\s*(["'`])[^"'`]*\1/g, "")
    .replace(/emitVisual(?:Now)?\([^,{)]*/g, "")
    .replace(/MASTER_LOG\?\.\w+\?\.\(\s*"[^"]*"/g, "");
  const names = new Set();
  const alternation = /\b([a-z][a-z0-9_]*):\((?:\?:)?([a-z0-9_|]+)\)/g;
  for (const [, namespace, branches] of code.matchAll(alternation)) {
    for (const branch of branches.split("|")) names.add(`${namespace}:${branch}`);
  }
  for (const [name] of code.replace(alternation, " ").matchAll(TOPIC)) names.add(name);
  return names;
}

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

test("every topic the bridge listens for is one the bus publishes", () => {
  const published = publishedTopics();
  const listened = bridgeListenerNames();

  // Both censuses have to see what they count before an empty difference
  // means anything. phantom:retry and council:deliberation survive only in
  // comments, and events:connected and master:visual are page events the bridge
  // emits and hears.
  assert.ok(published.size > 200 && published.has("phantom:detected") && published.has("rule_loop:fix_rejected"),
    `publish census is blind: ${published.size} topics`);
  for (const name of ["phantom:halt", "council:start", "rule_loop:autofix_skipped", "tts:job_cancelled"]) {
    assert.ok(listened.has(name), `bridge census missed ${name}`);
  }
  for (const name of ["phantom:retry", "council:deliberation", "events:connected", "master:visual", "visual_bridge:sse_frame"]) {
    assert.equal(listened.has(name), false, `bridge census counted ${name}, which the bridge does not listen for`);
  }

  const unpublished = [...listened].filter((name) =>
    !Object.hasOwn(NOT_BUS_TOPICS, name) && ![...published].some((topic) => topic.startsWith(name)));
  assert.deepEqual(unpublished, [], "visual_bridge.js listens for topics nothing publishes");

  const expired = Object.keys(NOT_BUS_TOPICS).filter((name) => !listened.has(name));
  assert.deepEqual(expired, [], "NOT_BUS_TOPICS excuses names the bridge no longer uses");
});

// EventsController writes each bus event as { t, type, data: event }, so the
// fields a listener reads sit under data. A handler that re-dispatched the
// whole frame gave user:expression listeners no expression to apply.
test("a frame from /events/stream hands listeners the bus event, not the frame", () => {
  const { visual, dispatched } = loadBridge();

  visual.runtime({ t: 1, type: "user:expression", data: { event: "user:expression", expression: "smile" } });
  visual.runtime({ t: 2, type: "ctx:footer", data: { event: "ctx:footer", pct: 42 } });

  const expression = dispatched.find((event) => event.type === "user:expression");
  assert.equal(expression?.detail?.expression, "smile");
  const pressure = dispatched.find((event) => event.type === "master:pressure");
  assert.equal(pressure?.detail?.pct, 42);
});
