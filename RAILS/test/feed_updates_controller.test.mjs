import assert from "node:assert/strict"
import { mkdtemp, readFile, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

// brgen's feed_updates_controller, run against a small fake DOM. Stimulus and
// the catch-up helper are replaced by stand-ins, so what is exercised is the
// controller's own counting, de-duplication, title and focus behaviour.

class Node {

  constructor(tag, id = "") {
    this.tag = tag
    this.id = id
    this.children = []
    this.parent = null

    this.hidden = false
    this.textContent = ""
    this.attributes = {}
    this.focused = false
    this.scrolled = false
  }

  detach() {
    const parent = this.parent
    if (!parent) return

    const siblings = parent.children
    siblings.splice(siblings.indexOf(this), 1)
    this.parent = null
  }

  appendChild(child) {
    child.detach()
    child.parent = this
    this.children.push(child)
    return child
  }

  prepend(child) {
    child.detach()
    child.parent = this
    this.children.unshift(child)
  }

  remove() {
    this.detach()
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value)
  }

  querySelector(selector) {
    const id = selector.match(/^\[id="(.+)"\]$/)?.[1]
    for (const child of this.children) {
      if (child.id === id) return child
      const found = child.querySelector(selector)
      if (found) return found
    }
    return null
  }

  focus() {
    this.focused = true
  }

  scrollIntoView() {
    this.scrolled = true
  }
}

let reloads = 0
globalThis.window = { location: { reload: () => { reloads += 1 } } }
globalThis.document = {

  title: "Bergen",
  hidden: false,
  listeners: {},
  addEventListener(type, handler) { this.listeners[type] = handler },
  removeEventListener(type) { delete this.listeners[type] },
  createElement: (tag) => new Node(tag),
}
globalThis.MutationObserver = class { observe() {} disconnect() {} }

const controllerPath = "../brgen/app/javascript/controllers/feed_updates_controller.js"
const source = await readFile(new URL(controllerPath, import.meta.url), "utf8")
const stubs = [

  "class Controller {}",
  "const fetchMissed = () => {}",
  "const newestId = () => 0",
  "const watchForCatchUp = () => () => {}",
].join("\n")
const dir = await mkdtemp(join(tmpdir(), "feed-updates-"))
const file = join(dir, "feed_updates_controller.mjs")
await writeFile(file, stubs + "\n" + source.replace(/^import .*$/gm, ""))
const { default: FeedUpdates } = await import(pathToFileURL(file).href)

function mount({ feed = true } = {}) {
  const controller = new FeedUpdates()
  controller.element = new Node("section")
  controller.pendingTarget = new Node("div")
  controller.chipTarget = new Node("p")
  controller.countTarget = new Node("span")

  controller.hasSourceTarget = false
  controller.hasFeedTarget = feed
  if (feed) controller.feedTarget = new Node("ul")

  controller.oneValue = "1 nytt innlegg"
  controller.otherValue = "%{count} nye innlegg"
  document.title = "Bergen"
  document.hidden = false
  controller.connect()
  return controller
}

function stage(controller, id) {
  controller.pendingTarget.prepend(new Node("turbo-frame", id))
  controller.refreshChip()
}

test("a hidden tab carries the pending count in its title", () => {
  const controller = mount()
  document.hidden = true
  stage(controller, "post_1")
  stage(controller, "post_2")
  assert.equal(document.title, "(2) Bergen")

  document.hidden = false
  document.listeners.visibilitychange()
  assert.equal(document.title, "Bergen")
})

test("a card the feed already shows is neither counted nor added twice", () => {
  const controller = mount()
  const row = controller.feedTarget.appendChild(new Node("li"))
  row.appendChild(new Node("turbo-frame", "post_7"))

  stage(controller, "post_7")
  assert.equal(controller.chipTarget.hidden, true, "the chip offers a post already on screen")

  stage(controller, "post_8")
  assert.equal(controller.countTarget.textContent, "1 nytt innlegg")

  controller.show()
  const ids = controller.feedTarget.children.map((li) => li.children[0].id)
  assert.deepEqual(ids, ["post_8", "post_7"])
})

test("pressing the chip on an empty feed reloads instead of throwing", () => {
  const controller = mount({ feed: false })
  stage(controller, "post_3")
  reloads = 0

  assert.doesNotThrow(() => controller.show())
  assert.equal(reloads, 1)
})

test("the newest card takes focus and is scrolled into view", () => {
  const controller = mount()
  stage(controller, "post_4")
  stage(controller, "post_5")

  controller.show()
  const top = controller.feedTarget.children[0].children[0]
  assert.equal(top.id, "post_5")
  assert.equal(top.focused, true)
  assert.equal(top.scrolled, true)
  assert.equal(top.attributes.tabindex, "-1")
})
