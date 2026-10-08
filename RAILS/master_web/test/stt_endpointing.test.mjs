import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

// quietMsFor lives inside the `if (SpeechRecognition in window)` block in
// face.part5.txt, so it cannot be imported — it only exists in a browser that
// has speech recognition. Lift the declarations out by source and evaluate
// those, which keeps the test reading the shipped regex rather than a copy of
// it that drifts the first time someone adds a word.
const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const source = readFileSync(join(publicDir, "face.part5.txt"), "utf8");

function extract(name, pattern) {
  const match = source.match(pattern);
  assert.ok(match, `${name} not found in face.part5.txt`);
  return match[0];
}

const endpointer = [
  extract("STT_QUIET_MS", /const STT_QUIET_MS = \d+;/),
  extract("STT_QUIET_MS_MIN", /const STT_QUIET_MS_MIN = \d+;/),
  extract("STT_QUIET_MS_MAX", /const STT_QUIET_MS_MAX = \d+;/),
  extract("HOLDING_FLOOR_RE", /const HOLDING_FLOOR_RE =\s*\n\s*\/.*\/i;/),
  extract("HANDED_OVER_RE", /const HANDED_OVER_RE = \/.*\/;/),
  extract("quietMsFor", /function quietMsFor\(text\) \{[\s\S]*?\n  \}/),
].join("\n");

const sandbox = runInNewContext(
  `${endpointer}\n({ quietMsFor, STT_QUIET_MS, STT_QUIET_MS_MIN, STT_QUIET_MS_MAX })`
);
const { quietMsFor, STT_QUIET_MS, STT_QUIET_MS_MIN, STT_QUIET_MS_MAX } = sandbox;

test("a sentence left hanging on a function word waits longer", () => {
  // Norwegian first — nb is the default locale.
  for (const held of [
    "jeg tenkte at vi kunne dra til",
    "fordi",
    "kan du fortelle meg litt om",
    "I was thinking that we could",
    "it depends on whether the",
  ]) {
    assert.equal(quietMsFor(held), STT_QUIET_MS_MAX, `should hold the floor: ${held}`);
  }
});

test("a finished question or statement commits sooner", () => {
  for (const done of ["hva heter du?", "det stemmer.", "what is your name?", "stopp!"]) {
    assert.equal(quietMsFor(done), STT_QUIET_MS_MIN, `should be finished: ${done}`);
  }
});

test("a short answer is a whole turn", () => {
  for (const short of ["ja", "nei takk", "det stemmer"]) {
    assert.equal(quietMsFor(short), STT_QUIET_MS_MIN, `should commit fast: ${short}`);
  }
});

test("anything unclear keeps the original generous window", () => {
  assert.equal(quietMsFor("jeg lurer på om du kan hjelpe meg med noe"), STT_QUIET_MS);
  assert.equal(quietMsFor(""), STT_QUIET_MS);
  assert.equal(quietMsFor(null), STT_QUIET_MS);
});

// Cutting someone off loses what they said and makes them repeat it; waiting
// too long is only a pause. The asymmetry is the design, so it is asserted.
test("punctuation the speaker typed beats a trailing function word", () => {
  assert.equal(quietMsFor("er det fordi?"), STT_QUIET_MS_MIN);
});

test("shortening never goes below the floor and holding never exceeds the ceiling", () => {
  const samples = [
    "", "ja", "hva?", "og", "jeg tenkte at", "det var veldig hyggelig å høre",
    "eh", "hmm", "well", "the", "nei.", "kan du",
  ];
  for (const s of samples) {
    const ms = quietMsFor(s);
    assert.ok(ms >= STT_QUIET_MS_MIN, `${s} -> ${ms} below floor`);
    assert.ok(ms <= STT_QUIET_MS_MAX, `${s} -> ${ms} above ceiling`);
  }
});
