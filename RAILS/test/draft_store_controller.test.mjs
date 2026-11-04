import assert from "node:assert/strict"
import { mkdtemp, readFile, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

// The shared draft-store controller's snapshot, with Stimulus and idb-keyval
// replaced by stand-ins. A draft is restored into a later page whose form has
// its own CSRF token; carrying the saved one back would replace it with a
// token from another page, so the snapshot leaves it out.

const controllerPath = "../__shared/frontend/draft_store_controller.js"
const source = await readFile(new URL(controllerPath, import.meta.url), "utf8")
const loadable = source
  .replace(/^import \{ Controller \}.*$/m, "class Controller {}")
  .replace(/^import \{ get, set, del \}.*$/m, "const get = async () => null\nconst set = get\nconst del = get")
const dir = await mkdtemp(join(tmpdir(), "draft-store-"))
const file = join(dir, "draft_store_controller.mjs")
await writeFile(file, loadable)
const { default: DraftStore } = await import(pathToFileURL(file).href)

test("a draft keeps what was written and leaves the CSRF token behind", () => {
  const controller = new DraftStore()
  controller.element = {
    querySelectorAll: () => [
      { name: "authenticity_token", type: "hidden", value: "old-token" },
      { name: "post[content]", type: "textarea", value: "Hei Bergen" },
      { name: "post[image]", type: "file", value: "" },
    ],
  }

  assert.deepEqual(controller.snapshot(), { "post[content]": "Hei Bergen" })
})
