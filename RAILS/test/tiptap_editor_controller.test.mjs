import assert from "node:assert/strict"
import { mkdtemp, readFile, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

// The shared tiptap-editor controller, with Stimulus and the vendored Tiptap
// replaced by stand-ins. What is exercised is the toolbar contract: buttons
// report the editor's active marks through aria-pressed, and holding mousedown
// keeps focus in the editor so the click can apply the mark.

class Button {
  constructor(mark) {
    this.dataset = { tiptapEditorMark: mark }
    this.attributes = {}
  }

  setAttribute(name, value) {
    this.attributes[name] = value
  }
}

let options = null
globalThis.__tiptap = {
  StarterKit: { configure: () => ({}) },
  Editor: class {
    constructor(given) {
      options = given
      this.commands = { focus() {} }
    }
  },
}
globalThis.window = {}

const controllerPath = "../__shared/frontend/tiptap_editor_controller.js"
const source = await readFile(new URL(controllerPath, import.meta.url), "utf8")
const loadable = source
  .replace(/^import .*$/gm, "class Controller {}")
  .replace('await import("tiptap")', "globalThis.__tiptap")
const dir = await mkdtemp(join(tmpdir(), "tiptap-editor-"))
const file = join(dir, "tiptap_editor_controller.mjs")
await writeFile(file, loadable)
const { default: TiptapEditor } = await import(pathToFileURL(file).href)

const hidden = () => ({ hidden: true, classList: { add() {} }, setAttribute() {} })

async function mounted() {
  const controller = new TiptapEditor()
  const buttons = ["bold", "italic", "bulletList"].map((mark) => new Button(mark))
  controller.element = { removeEventListener() {} }
  controller.fieldTarget = { ...hidden(), value: "", getAttribute: () => "", tabIndex: 0 }
  controller.mountTarget = hidden()
  controller.hasToolbarTarget = true
  controller.toolbarTarget = { hidden: true, querySelectorAll: () => buttons }

  await controller.mount()
  return { controller, buttons }
}

test("the toolbar reports which marks are on at the caret", async () => {
  const { buttons } = await mounted()
  const active = new Set(["bold"])

  options.onTransaction({ editor: { isActive: (mark) => active.has(mark) } })
  assert.deepEqual(buttons.map((button) => button.attributes["aria-pressed"]), ["true", "false", "false"])

  active.delete("bold")
  active.add("bulletList")
  options.onTransaction({ editor: { isActive: (mark) => active.has(mark) } })
  assert.deepEqual(buttons.map((button) => button.attributes["aria-pressed"]), ["false", "false", "true"])
})

test("mousedown on a button is held so the editor keeps its selection", async () => {
  const { controller } = await mounted()
  let held = false

  controller.hold({ preventDefault: () => { held = true } })
  assert.equal(held, true)
})
