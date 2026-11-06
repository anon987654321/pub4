import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

// Runs public/dashboard_live.js against fake timers, fetch and EventSource:
// the test reads which delays it scheduled and which requests it made.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(join(root, "public", "dashboard_live.js"), "utf8");

function node() {
  return { textContent: "", dataset: {}, replaceChildren() {} };
}

function loadDashboard({ answers = [] } = {}) {
  const timers = [];
  const fetches = [];
  const streams = [];
  const nodes = {};

  class FakeEventSource {
    constructor(url) { this.url = url; this.closed = false; streams.push(this); }
    close() { this.closed = true; }
  }

  const ok = { status: 200, ok: true, json: async () => ({ model: "m", mission: {} }) };

  const document = {
    hidden: false,
    getElementById: (id) => (nodes[id] ||= node()),
    createElement: () => node(),
    addEventListener() {}
  };

  const context = {
    document,
    fetch: async (url) => { fetches.push(url); return answers.shift() || ok; },
    EventSource: FakeEventSource,

    setTimeout: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearTimeout: (id) => { if (timers[id - 1]) timers[id - 1].cleared = true; },
    setInterval: () => { throw new Error("the dashboard must not poll on a fixed interval"); },
    clearInterval() {},

    Date, Number, JSON, Math
  };
  vm.runInNewContext(source, context);

  const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
  const live = () => timers.filter((timer) => !timer.cleared && !timer.ran);
  const run = async (timer) => { timer.ran = true; timer.fn(); await settle(); };
  return { timers, fetches, streams, live, run, settle };
}

const failing = { status: 503, ok: false, json: async () => ({ error: "warming up" }) };

test("the dashboard listens on the event stream instead of an 8 s interval", async () => {
  const page = loadDashboard();
  await page.settle();

  assert.equal(page.streams.length, 1);
  assert.equal(page.streams[0].url, "/events/stream");
  assert.deepEqual(page.fetches, ["/dashboard/live"]);
  assert.deepEqual(page.live().map((timer) => timer.ms), [60000], "only a slow safety poll is armed");
});

test("bus events refresh the panels once, debounced", async () => {
  const page = loadDashboard();
  await page.settle();
  for (let i = 0; i < 5; i += 1) page.streams[0].onmessage({ data: "{}" });

  const debounced = page.live().filter((timer) => timer.ms === 1500);
  assert.equal(debounced.length, 1, "five events, one pending refresh");
  await page.run(debounced[0]);
  assert.deepEqual(page.fetches, ["/dashboard/live", "/dashboard/live"]);
});

test("a failing fetch backs off and recovers to the safety poll", async () => {
  const page = loadDashboard({ answers: [failing, failing, failing] });
  await page.settle();
  const delays = [];
  for (let i = 0; i < 3; i += 1) {
    const [next] = page.live();
    delays.push(next.ms);
    await page.run(next);
  }

  assert.deepEqual(delays, [2000, 4000, 8000]);
  assert.deepEqual(page.live().map((timer) => timer.ms), [60000], "a good answer resets the backoff");
});

test("a failing stream reconnects on a growing delay, not EventSource's own retry", async () => {
  const page = loadDashboard();
  await page.settle();
  const delays = [];
  for (let i = 0; i < 3; i += 1) {
    const stream = page.streams.at(-1);
    stream.onerror();
    assert.equal(stream.closed, true);
    const reconnect = page.live().find((timer) => timer.ms !== 60000);
    delays.push(reconnect.ms);
    await page.run(reconnect);
  }

  assert.deepEqual(delays, [2000, 4000, 8000]);
  assert.equal(page.streams.length, 4);
});

test("an authentication failure stops both the poll and the stream", async () => {
  const page = loadDashboard({ answers: [{ status: 401, ok: false, json: async () => ({}) }] });
  await page.settle();

  assert.equal(page.streams[0].closed, true);
  assert.deepEqual(page.live(), []);
});
