import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(join(root, "public", "topology_registry.js"), "utf8");
const yaml = readFileSync(join(root, "..", "data", "topologies.yml"), "utf8");

// /runtime/topologies renders data/topologies.yml verbatim, so the keys arrive
// in the YAML's lower_snake_case. This file reads them in the JS convention for
// a constant. For six merges that mismatch meant `|| {}` swallowed everything
// and the remote topology feature had never changed a value.
//
// Asserted against the real YAML rather than a fixture: the defect was that the
// two files disagreed, so a fixture that agreed with one of them would have
// passed throughout.
test("every key the registry merges exists in topologies.yml", () => {
  const merged = [...source.matchAll(/remoteKey\(remote,\s*"([A-Z_]+)"\)/g)].map((m) => m[1]);
  assert.ok(merged.length >= 6, `expected six or more merged keys, found ${merged.length}`);

  for (const name of merged) {
    const key = name.toLowerCase();
    assert.match(yaml, new RegExp(`^${key}:`, "m"),
                 `topology_registry merges ${name}, and topologies.yml has no ${key}:`);
  }
});

// The bug, stated as a test: reading remote.TOPOLOGIES directly is what failed.
test("the registry does not read remote keys in the JS constant case", () => {
// Code only. The first draft matched the names inside the comment that
// explains why the names are wrong — the check reading its own
// documentation, which is the same fault three separate checks in this repo
// shipped today.
const code = source.split("\n").filter((line) => !line.trim().startsWith("//")).join("\n");
const direct = [...code.matchAll(/remote\.([A-Z_]{4,})/g)].map((m) => m[1]);
  assert.deepEqual(direct, [],
                   `remote.${direct[0]} is undefined — the payload is lower_snake_case`);
});

// remoteKey must accept either, because a future endpoint that upcases its keys
// should not silently stop merging the way this one silently never started.
test("remoteKey falls back to the literal name", () => {
  assert.match(source, /remote\[name\.toLowerCase\(\)\]\s*\?\?\s*remote\[name\]/);
});
