import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"
import test from "node:test"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const OPENING_TRACK_ID = "9EGHwkDix78"

async function loadRadioModes() {
  const source = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_modes.js"), "utf8")
  const executable = source.replace(/^export\s+/gm, "")
  const api = vm.runInNewContext(`${executable}\n({ MODES, INK_FAR, INK_MID, INK_NEAR, RING_SHAPE_GLSL, modeAfterStep })`)
  return api
}

test("radio mode catalogue has 22 unique, finite, bounded modes", async () => {
  const { MODES, INK_FAR, INK_MID, INK_NEAR } = await loadRadioModes()
  assert.equal(MODES.length, 22)
  assert.equal(new Set(Array.from(MODES, (mode) => mode.name)).size, 22)
  for (const mode of MODES) {
    assert.equal(typeof mode.name, "string")
    assert.ok(mode.name.length > 0)
    assert.ok(Number.isFinite(mode.twist))
    assert.ok(mode.twist >= 0.9 && mode.twist <= 1.1)
  }
  for (const colour of [INK_FAR, INK_MID, INK_NEAR]) {
    for (const channel of ["r", "g", "b"]) {
      assert.ok(Number.isFinite(colour[channel]))
      assert.ok(colour[channel] >= 0 && colour[channel] <= 1)
    }
  }
})

test("radio mode stepping wraps in both directions and validates its inputs", async () => {
  const { modeAfterStep, MODES } = await loadRadioModes()
  assert.equal(modeAfterStep(0, -1), MODES.length - 1)
  assert.equal(modeAfterStep(MODES.length - 1, 1), 0)
  assert.equal(modeAfterStep(7, MODES.length), 7)
  assert.equal(modeAfterStep(7, -MODES.length), 7)
  assert.equal(modeAfterStep(0, -23), MODES.length - 1)
  assert.throws(() => modeAfterStep(0.5, 1), { name: "RangeError" })
  assert.throws(() => modeAfterStep(0, 1, 0), { name: "RangeError" })
})

test("all 22 mode indices have an ordered GLSL branch and the classic mode is neutral", async () => {
  const { RING_SHAPE_GLSL, MODES } = await loadRadioModes()
  const thresholds = Array.from(RING_SHAPE_GLSL.matchAll(/if \(m < ([0-9.]+)\)/g), (match) => Number(match[1]))
  assert.equal(thresholds.length, MODES.length - 1)
  assert.deepEqual(thresholds, Array.from({ length: MODES.length - 1 }, (_, index) => index + 0.5))
  assert.match(RING_SHAPE_GLSL, /if \(m < 0\.5\) return 0\.0;/)
  assert.match(RING_SHAPE_GLSL, /float ringShape\(float th, float i, float t\)/)
})

test("Radio tunnel wires the visual module and left/right keyboard controls", async () => {
  const source = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_tunnel.js"), "utf8")
  const visual = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_visual.js"), "utf8")
  assert.match(visual, /MODES, RING_SHAPE_GLSL, modeAfterStep/)
  assert.match(visual, /this\.mode = modeAfterStep\(this\.mode, step\)/)
  assert.match(visual, /gl\.uniform1f\(u\.uMode, this\.mode\)/)
  assert.match(visual, /gl\.uniform1f\(u\.uModeTwist, MODES\[this\.mode\]\.twist\)/)
  assert.match(source, /e\.code === "ArrowRight" \|\| e\.code === "ArrowLeft"/)
  assert.match(source, /this\.visualEngine\.shiftMode\(e\.code === "ArrowRight" \? 1 : -1\)/)
})


test("Radio audio, visual and integration responsibilities live in separate modules", async () => {
  const entry = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_tunnel.js"), "utf8")
  const audio = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_audio.js"), "utf8")
  const visual = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_visual.js"), "utf8")
  const imports = await readFile(resolve(ROOT, "brgen/config/importmap.rb"), "utf8")

  assert.match(entry, /import \{ AudioEngine \} from "radio_brgen_audio"/)
  assert.match(entry, /import \{ VisualEngine, MODES \} from "radio_brgen_visual"/)
  assert.match(audio, /export class AudioEngine/)
  assert.match(audio, /export function initialTrackIndex/)
  assert.doesNotMatch(audio, /class VisualEngine|createShader\(/)
  assert.match(visual, /export class VisualEngine/)
  assert.doesNotMatch(visual, /class AudioEngine|YT\.Player/)
  assert.match(imports, /pin "radio_brgen_audio", to: "radio_brgen_audio\.js"/)
  assert.match(imports, /pin "radio_brgen_visual", to: "radio_brgen_visual\.js"/)
})

async function loadInitialTrackIndex() {
  const source = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_audio.js"), "utf8")
  const match = source.match(/export function initialTrackIndex\(tracks, openingTrackId\) \{[\s\S]*?\n\}/)
  assert.ok(match, "radio tunnel exports the tested track-selection helper")
  return vm.runInNewContext("(" + match[0].replace(/^export\s+/, "") + ")")
}

test("radio queue prefers the legacy opener only when it is present", async () => {
  const initialTrackIndex = await loadInitialTrackIndex()
  const tracks = [{ id: "before" }, { id: OPENING_TRACK_ID }, { id: "after" }]
  assert.equal(initialTrackIndex(tracks, OPENING_TRACK_ID), 1)
})

test("curated queue starts at its first ordered item when opener is absent", async () => {
  const initialTrackIndex = await loadInitialTrackIndex()
  const tracks = [{ id: "curated-first" }, { id: "curated-second" }]
  assert.equal(initialTrackIndex(tracks, OPENING_TRACK_ID), 0)
})

test("single-track queues remain playable and source never randomizes its start", async () => {
  const initialTrackIndex = await loadInitialTrackIndex()
  assert.equal(initialTrackIndex([{ id: "only" }], OPENING_TRACK_ID), 0)
  const source = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_tunnel.js"), "utf8")
  assert.match(source, /this\.currentTrack\s*=\s*initialTrackIndex\(this\.tracks,\s*OPENING_TRACK_ID\)/)
  assert.doesNotMatch(source, /Math\.floor\(Math\.random\(\)\s*\*\s*this\.tracks\.length\)/)
})
