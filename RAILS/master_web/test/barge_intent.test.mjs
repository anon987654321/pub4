import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

// bargeIntent lives inside the `if (SpeechRecognition in window)` block in
// face.part5.txt, so it cannot be imported. Lift the declarations out by source
// and evaluate those, so the test reads the shipped vocabulary rather than a
// copy that drifts the first time someone adds a word — same approach as
// stt_endpointing.test.mjs.
const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const source = readFileSync(join(publicDir, "face.part5.txt"), "utf8");

function extract(name, pattern) {
  const match = source.match(pattern);
  assert.ok(match, `${name} not found in face.part5.txt`);
  return match[0];
}

const decls = [
  extract("BARGE_IN_MIN_CHARS", /const BARGE_IN_MIN_CHARS = \d+;/),
  extract("normaliseHeard", /const normaliseHeard = \(s\) =>[\s\S]*?\.trim\(\);/),
  extract("BARGE_IN_STOP_RE", /const BARGE_IN_STOP_RE = \/.*\/;/),
  extract("BACKCHANNEL_WORDS", /const BACKCHANNEL_WORDS = new Set\(\[[\s\S]*?\]\);/),
  extract("isBackchannelOnly", /function isBackchannelOnly\(said\) \{[\s\S]*?\n  \}/),
  extract("bargeIntent", /function bargeIntent\(said\) \{[\s\S]*?\n  \}/),
].join("\n");

const { bargeIntent, normaliseHeard, BARGE_IN_MIN_CHARS } = runInNewContext(
  `${decls}\n({ bargeIntent, normaliseHeard, BARGE_IN_MIN_CHARS })`
);

const intent = (heard) => bargeIntent(normaliseHeard(heard));

// The floor is 8 characters. "no wait" is 7, so the one thing a person says
// when they need the sentence to stop was the one thing that did not stop it.
test("a refusal yields the turn even though it is under the length floor", () => {
  for (const said of ["No, wait", "no", "Stop.", "Nei!", "Vent litt", "Hold on", "Hey —"]) {
    assert.ok(normaliseHeard(said).length < BARGE_IN_MIN_CHARS || said.length < 12, `${said} should be short`);
    assert.equal(intent(said), "stop", `should stop: ${said}`);
  }
});

// "yeah yeah okay" is 14 characters, over the floor, so signalling attention
// used to cut the sentence off.
test("an agreement never yields the turn however long it runs", () => {
  for (const said of [
    "yeah yeah okay",
    "mm hmm right",
    "yes exactly, absolutely",
    "ja ja greit",
    "okay okay got it",
    "oh I see",
  ]) {
    assert.ok(normaliseHeard(said).length >= BARGE_IN_MIN_CHARS, `${said} should clear the floor`);
    assert.equal(intent(said), "backchannel", `should not stop: ${said}`);
  }
});

test("a real attempt at the turn still yields on length", () => {
  for (const said of [
    "can you check the event bridge instead",
    "kan du se på hendelsesbroen",
    "actually the deploy already finished",
  ]) {
    assert.equal(intent(said), "turn", `should take the turn: ${said}`);
  }
});

test("a fragment too short to be an attempt is bleed, not a turn", () => {
  for (const said of ["th", "and", "a b"]) {
    assert.equal(intent(said), "none", `should be ignored: ${said}`);
  }
});

test("empty input is never a barge-in", () => {
  assert.equal(intent(""), "none");
  assert.equal(intent("   "), "none");
  assert.equal(intent("..."), "none");
});

// A stop word leading a longer sentence is still a stop — the urgency is in the
// opener, and waiting for the rest of the clause is the delay it exists to skip.
test("a refusal that opens a longer sentence still stops immediately", () => {
  assert.equal(intent("no no that is the wrong file entirely"), "stop");
  assert.equal(intent("wait, go back to the previous one"), "stop");
});

// Ordering: stop is checked before the backchannel vocabulary, or "no" reaching
// the word set would matter. It does not, but the precedence is the contract.
test("a refusal outranks agreement words that follow it", () => {
  assert.equal(intent("no yeah okay"), "stop");
});
