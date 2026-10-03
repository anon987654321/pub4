import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

// pickBrowserVoice lives mid-file in face_speech_runtime.js, which is not a
// module and touches window on load. Lift the function and its two lists out by
// source so the test runs the shipped code rather than a paraphrase of it.
const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const source = readFileSync(join(publicDir, "face_speech_runtime.js"), "utf8");

function extract(name, pattern) {
  const match = source.match(pattern);
  assert.ok(match, `${name} not found in face_speech_runtime.js`);
  return match[0];
}

// c4700163a split PREFERRED_VOICE_RE into a neural tier and a decent tier so
// a premium voice cannot lose to a 2009 one by array position; the test lifts
// what the runtime actually declares.
const code = [
  extract("NOVELTY_VOICE_RE", /const NOVELTY_VOICE_RE = \/.*\/i;/),
  extract("NEURAL_VOICE_RE", /const NEURAL_VOICE_RE = \/.*\/i;/),
  extract("DECENT_VOICE_RE", /const DECENT_VOICE_RE = \/.*\/i;/),
  extract("pickBrowserVoice", /function pickBrowserVoice\(lang\) \{[\s\S]*?\n\}/),
].join("\n");

function pickerWith(voices) {
  const sandbox = {
    speechSynthesis: { getVoices: () => voices },
    console,
  };
  return runInNewContext(`${code}\npickBrowserVoice`, sandbox);
}

const voice = (name, lang, extra = {}) => ({ name, lang, voiceURI: name, default: false, ...extra });

// The list macOS actually hands Chrome: novelty voices interleaved with real
// ones, all tagged en-US, with a joke voice early enough to win a naive find().
const MAC_LIKE = [
  voice("Albert", "en-US"),
  voice("Bad News", "en-US"),
  voice("Bubbles", "en-US"),
  voice("Whisper", "en-US"),
  voice("Samantha", "en-US", { default: true }),
  voice("Zarvox", "en-US"),
  voice("Nora", "nb-NO"),
  voice("Daniel", "en-GB"),
];

test("a novelty voice is never chosen when a real one exists", () => {
  const pick = pickerWith(MAC_LIKE);
  const chosen = pick("en-US");
  assert.ok(chosen, "nothing chosen");
  assert.doesNotMatch(chosen.name, /whisper|albert|bad news|bubbles|zarvox/i,
    `chose the novelty voice ${chosen.name}`);
  assert.equal(chosen.name, "Samantha");
});

test("Norwegian picks the Norwegian voice, not an English one", () => {
  const chosen = pickerWith(MAC_LIKE)("nb-NO");
  assert.equal(chosen.name, "Nora");
});

test("a preferred voice outranks the platform default", () => {
  const chosen = pickerWith([
    voice("Fred", "en-US", { default: true }),
    voice("Google US English", "en-US"),
  ])("en-US");
  assert.equal(chosen.name, "Google US English");
});

test("falls back through the base language when the locale is absent", () => {
  const chosen = pickerWith([voice("Daniel", "en-GB")])("en-US");
  assert.equal(chosen.name, "Daniel");
});

// Silence is worse than a strange voice: returning nothing makes
// speakWithBrowserTTS give up, and nothing is spoken at all.
test("a list of nothing but novelty voices still yields one", () => {
  const chosen = pickerWith([voice("Zarvox", "en-US"), voice("Bubbles", "en-US")])("en-US");
  assert.ok(chosen, "returned nothing when only novelty voices exist");
});

test("an empty voice list returns null so the caller can retry", () => {
  assert.equal(pickerWith([])("en-US"), null);
});
