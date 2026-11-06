import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";

// smart_turn.js can fetch ~21MB (a WASM runtime and an ONNX model). It is on
// only by ?smart_turn=1 or the master:smart-turn flag, and the shell must never
// load either download itself.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = join(root, "public");

async function loadSmartTurn({ search = "", stored = null } = {}) {
  const fetched = [];
  globalThis.window = { location: { search }, MASTER_LOG: null };
  globalThis.localStorage = { getItem: () => stored, setItem() {} };
  globalThis.fetch = async (url) => { fetched.push(String(url)); throw new Error("no network in tests"); };

  // The module imports "/whisper_mel.js" root-absolute, which is right for the
  // browser and names the filesystem root under node; point it at the real file.
  const source = readFileSync(join(publicDir, "smart_turn.js"), "utf8")
    .replace('from "/whisper_mel.js"', `from ${JSON.stringify(pathToFileURL(join(publicDir, "whisper_mel.js")).href)}`);
  const dir = mkdtempSync(join(tmpdir(), "smart_turn-"));
  const copy = join(dir, `smart_turn_${Date.now()}_${Math.random().toString(36).slice(2)}.mjs`);
  writeFileSync(copy, source);
  const mod = await import(pathToFileURL(copy).href);
  return { mod, fetched };
}

test("smart turn is off by default and downloads nothing", async () => {
  const { mod, fetched } = await loadSmartTurn();

  assert.equal(mod.smartTurnEnabled(), false);
  assert.equal(await mod.warmUp(), false);
  assert.equal(await mod.predictEndpoint(), null);
  assert.deepEqual(fetched, []);
});

test("the query flag and the stored flag each switch it on", async () => {
  assert.equal((await loadSmartTurn({ search: "?smart_turn=1" })).mod.smartTurnEnabled(), true);
  assert.equal((await loadSmartTurn({ stored: "1" })).mod.smartTurnEnabled(), true);
});

test("the shell never loads the runtime or the model", () => {
  const view = readFileSync(join(root, "app", "views", "chat", "index.html.erb"), "utf8");
  const tags = view.match(/<(?:script|link)\b[^>]*>/g) || [];

  for (const tag of tags) {
    assert.doesNotMatch(tag, /onnx|ort\.wasm|\.wasm|smart_turn|smart-turn/i, `the shell loads a smart-turn download: ${tag}`);
  }
});
