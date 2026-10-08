import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"

const SOURCE = new URL("../public/gravity_field.js", import.meta.url)
const source = fs.readFileSync(SOURCE, "utf8")
const listeners = new Map()
const appended = []

const context = {
  clearRect() {},
  fillRect() {},
  setTransform() {},
  beginPath() {},
  moveTo() {},
  lineTo() {},
  stroke() {}
}

const body = {
  appendChild(node) {
    appended.push(node)
    return node
  }
}

const documentMock = {
  hidden: false,
  documentElement: {
    dataset: {}
  },
  body: {
    appendChild: body.appendChild.bind(body)
  },
  createElement(tag) {
    assert.equal(tag, "canvas")
    return {
      id: "",
      className: "",
      style: {},
      setAttribute() {},
      getContext() {
        return context
      }
    }
  },
  addEventListener(name, callback) {
    listeners.set(name, callback)
  }
}

globalThis.document = documentMock
globalThis.innerWidth = 1200
globalThis.innerHeight = 800
globalThis.devicePixelRatio = 1
globalThis.matchMedia = () => ({ matches: true })
globalThis.requestAnimationFrame = () => 1
globalThis.cancelAnimationFrame = () => {}
globalThis.addEventListener = (name, callback) => {
  listeners.set(name, callback)
}

await import("data:text/javascript," + encodeURIComponent(source))

test("gravity field boots as a deterministic reduced-motion renderer", () => {
  assert.equal(appended.length, 1)
  assert.equal(appended[0].id, "master-gravity-field")
  assert.match(source, /GOLDEN_ANGLE/)
  assert.doesNotMatch(source, /Math\.random\s*\(/)
})

test("gravity field reacts to semantic visual events", () => {
  const visual = listeners.get("master:visual")
  const emotion = listeners.get("master:emotion")
  const gravity = listeners.get("gravity:signal")

  assert.equal(typeof visual, "function")
  assert.equal(typeof emotion, "function")
  assert.equal(typeof gravity, "function")

  visual({ detail: { activity: 0.9, confidence: 0.2 } })
  assert.equal(document.documentElement.dataset.gravityState, "active")

  emotion({ detail: { activity: 0.4 } })
  gravity({ detail: { activity: 0.7 } })
  assert.equal(document.documentElement.dataset.gravityState, "active")
})

test("gravity field pauses continuous animation under reduced motion", () => {
  const resize = listeners.get("resize")
  assert.equal(typeof resize, "function")
  resize()
  assert.equal(appended.length, 1)
})
