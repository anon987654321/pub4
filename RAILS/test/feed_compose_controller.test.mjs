import assert from "node:assert/strict"
import { mkdtemp, readFile, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

// The shared feed-compose controller in its dialog shape (brgen), with
// Stimulus replaced by a stand-in. What is exercised is closing: a dialog that
// holds text or an attached file asks before it closes, by the close button,
// a backdrop click or Esc, and an empty one closes without asking.

const asked = []
let answer = true
globalThis.window = {
  confirm: (question) => {
    asked.push(question)
    return answer
  },
}

const controllerPath = "../__shared/frontend/feed_compose_controller.js"
const source = await readFile(new URL(controllerPath, import.meta.url), "utf8")
const dir = await mkdtemp(join(tmpdir(), "feed-compose-"))
const file = join(dir, "feed_compose_controller.mjs")
await writeFile(file, source.replace(/^import .*$/gm, "class Controller {}"))
const { default: FeedCompose } = await import(pathToFileURL(file).href)

function composer({ text = "", files = 0 } = {}) {
  const controller = new FeedCompose()
  const dialog = { open: true, close() { this.open = false } }
  const upload = { files: { length: files } }

  controller.hasDialogTarget = true
  controller.dialogTarget = dialog
  controller.hasInputTarget = true
  controller.inputTarget = { value: text }
  controller.element = { querySelectorAll: () => [upload] }
  controller.discardValue = "Forkaste innlegget?"
  asked.length = 0
  answer = true
  return { controller, dialog }
}

test("an empty composer closes without asking", () => {
  const { controller, dialog } = composer()

  controller.close()
  assert.equal(dialog.open, false)
  assert.equal(asked.length, 0)
})

test("written text is not lost to the close button without a yes", () => {
  const { controller, dialog } = composer({ text: "<p>Hei Bergen</p>" })
  answer = false

  controller.close()
  assert.equal(dialog.open, true)
  assert.deepEqual(asked, ["Forkaste innlegget?"])

  answer = true
  controller.close()
  assert.equal(dialog.open, false)
})

test("a backdrop click with an attached file asks first", () => {
  const { controller, dialog } = composer({ files: 1 })
  answer = false

  controller.backdropClose({ target: dialog })
  assert.equal(dialog.open, true)
  assert.equal(asked.length, 1)
})

test("Esc on a written composer is held when the writer declines", () => {
  const { controller } = composer({ text: "utkast" })
  let held = false
  answer = false

  controller.cancel({ preventDefault: () => { held = true } })
  assert.equal(held, true)
})
