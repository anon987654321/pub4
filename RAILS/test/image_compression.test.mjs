import { test } from "node:test"
import assert from "node:assert/strict"
import { MAX_EDGE, compressible, compressImage, fitWithin, smaller } from "../__shared/frontend/image_compression.js"

test("a photo is fitted within the long edge and never upscaled", () => {
  assert.deepEqual(fitWithin(4032, 3024), { width: MAX_EDGE, height: 1200 })
  assert.deepEqual(fitWithin(3024, 4032), { width: 1200, height: MAX_EDGE })
  assert.deepEqual(fitWithin(800, 600), { width: 800, height: 600 })
})

test("animated and vector images pass through; rasters are compressible", () => {
  assert.equal(compressible(new File([""], "a.jpg", { type: "image/jpeg" })), true)
  assert.equal(compressible(new File([""], "a.heic", { type: "image/heic" })), true)
  assert.equal(compressible(new File([""], "a.gif", { type: "image/gif" })), false)
  assert.equal(compressible(new File([""], "a.svg", { type: "image/svg+xml" })), false)
  assert.equal(compressible(new File([""], "a.pdf", { type: "application/pdf" })), false)
})

test("a result that is not smaller is dropped for the original", () => {
  const original = new File(["x".repeat(100)], "a.jpg", { type: "image/jpeg" })
  const bigger = new File(["x".repeat(200)], "a.webp", { type: "image/webp" })
  const less = new File(["x".repeat(10)], "a.webp", { type: "image/webp" })

  assert.equal(smaller(original, bigger), original)
  assert.equal(smaller(original, less), less)
  assert.equal(smaller(original, null), original)
})

test("without a canvas the picked file is handed back untouched", async () => {
  const file = new File(["photo"], "a.jpg", { type: "image/jpeg" })

  assert.equal(await compressImage(file), file)
})
