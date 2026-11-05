import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

// Runs public/sw.js against a fake worker scope: its fetch handler is called
// with a request, and the test reads what it answered and what it cached.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(join(root, "public", "sw.js"), "utf8");
const ORIGIN = "https://ai.brgen.no";

const pathOf = (request) => (typeof request === "string" ? request : new URL(request.url).pathname);

function loadWorker({ cached = {}, network }) {
  const store = new Map(Object.entries(cached));
  const puts = [];
  const listeners = {};

  const cache = {
    put: async (request, response) => {
      puts.push(pathOf(request));
      store.set(pathOf(request), response);
    },

    add: async () => {}
  };

  const caches = {
    open: async () => cache,
    keys: async () => [],
    delete: async () => true,
    match: async (request) => store.get(pathOf(request))
  };

  const scope = {
    location: new URL(`${ORIGIN}/sw.js?v=test`),
    addEventListener: (type, handler) => { listeners[type] = handler; },
    skipWaiting: () => {},
    clients: { claim: async () => {}, matchAll: async () => [] }
  };

  const context = { self: scope, caches, fetch: network, URL, Response, Promise };
  vm.runInNewContext(source, context);

  return {
    puts,
    async request(path, { mode = "cors", method = "GET" } = {}) {
      let answer;
      const request = { url: `${ORIGIN}${path}`, mode, method };
      listeners.fetch({ request, respondWith: (value) => { answer = value; } });

      const response = await answer;
      await new Promise((resolve) => setTimeout(resolve, 0));
      return response;
    }
  };
}

const offline = () => Promise.reject(new TypeError("offline"));
const online = (body) => async () => new Response(body, { status: 200 });

test("an offline navigation falls back to the cached offline page", async () => {
  const page = new Response("offline page");
  const worker = loadWorker({ cached: { "/offline.html": page }, network: offline });
  assert.equal(await worker.request("/", { mode: "navigate" }), page);
});

test("an offline navigation prefers a cached shell over the offline page", async () => {
  const shell = new Response("shell");
  const worker = loadWorker({ cached: { "/": shell, "/offline.html": new Response("offline") }, network: offline });
  assert.equal(await worker.request("/dashboard", { mode: "navigate" }), shell);
});

for (const path of ["/api/key", "/api/v1/lint", "/pair", "/pair/list", "/chat/history", "/events/stream"]) {
  test(`${path} passes through and is never written to Cache Storage`, async () => {
    const worker = loadWorker({ network: online("secret") });
    const response = await worker.request(path);
    assert.equal(await response.text(), "secret");
    assert.deepEqual(worker.puts, []);
  });
}

test("a plain static GET is still cached after a successful fetch", async () => {
  const worker = loadWorker({ network: online("icon") });
  await worker.request("/icon.svg");
  assert.deepEqual(worker.puts, ["/icon.svg"]);
});

test("non-GET requests are left to the network", async () => {
  const worker = loadWorker({ network: online("posted") });
  assert.equal(await worker.request("/chat/message", { method: "POST" }), undefined);
});
