import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const source = readFileSync(join(publicDir, "chat_actions.js"), "utf8");

// The face runtime owns the prompt's Enter and submit handlers. If it never
// loads, chat_actions must still carry a typed message to the stream, and must
// step aside the moment the runtime exists so nothing is sent twice.
test("chat_actions sends from the prompt while the face runtime is absent", () => {
  assert.match(source, /faceOwnsSend = \(\) => typeof window\.MASTER_FACE\?\.sendMessage === "function"/);
  assert.match(source, /form\.addEventListener\("submit", \(event\) => \{\s*if \(faceOwnsSend\(\)\) return;/);
  assert.match(source, /input\.addEventListener\("keydown", \(event\) => \{\s*if \(faceOwnsSend\(\) \|\|/);
});

test("the degraded stream drops the trace frame like the face runtime does", () => {
  assert.match(source, /JSON\.parse\(raw\)\?\.type === "trace"/);
});

test("a tap on the prompt strip beside the one-line textarea focuses it", () => {
  assert.match(source, /form\.addEventListener\("click", \(event\) => \{\s*if \(event\.target\.closest\("button, a, input, textarea, select"\)\) return;\s*input\.focus\(\)/);
});
