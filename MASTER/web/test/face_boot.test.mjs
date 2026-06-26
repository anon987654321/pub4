import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "public");

function partSources() {
  return [1, 2, 3, 4, 5].map((part) => readFileSync(join(root, `face.part${part}.txt`), "utf8"));
}

test("face.part tail imports are single-quoted for MODULE_PATHS replacement", () => {
  const tail = partSources().join("\n");
  const imports = [...tail.matchAll(/import\(['"]([^'"]+)['"]\)/g)].map((m) => m[1]);
  const rootImports = imports.filter((path) => path.startsWith("/"));
  assert.deepEqual(rootImports, [
    "/face_semantics.js",
    "/face_minimal_ui.js",
    "/face_loops_music.js",
    "/face_loops_nudge.js"
  ]);
});

test("face.js loader replaces every tail import path", () => {
  const source = partSources().join("\n");
  const faceModules = Object.fromEntries(
    readdirSync(join(root, "assets"))
      .filter((name) => name.endsWith(".js") && name.startsWith("face_"))
      .map((name) => [name.replace(/-[0-9a-f]{8}\.js$/, ".js"), `/assets/${name}`])
  );
  const replaced = Object.entries(faceModules).reduce(
    (out, [name, path]) => out.replaceAll(`'/${name}'`, JSON.stringify(`https://example.test${path}`)),
    source
  );
  assert.doesNotMatch(replaced, /import\('\/face_/);
});