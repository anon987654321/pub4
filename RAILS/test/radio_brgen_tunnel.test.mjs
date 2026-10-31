import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"
import test from "node:test"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const OPENING_TRACK_ID = "9EGHwkDix78"

async function loadInitialTrackIndex() {
  const source = await readFile(resolve(ROOT, "brgen/app/javascript/radio_brgen_tunnel.js"), "utf8")
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
