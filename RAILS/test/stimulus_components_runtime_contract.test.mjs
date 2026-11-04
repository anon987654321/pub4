import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { resolve } from "node:path"
import test from "node:test"

const ROOT = resolve(import.meta.dirname, "..")
const VENDOR = resolve(ROOT, "__shared/vendor/javascript")

const readVendor = (name) => readFile(resolve(VENDOR, name), "utf8")
const readSource = (relative) => readFile(resolve(ROOT, relative), "utf8")

test("heavy components stay self-contained and local", async () => {
  const sources = await Promise.all([
    readVendor("@stimulus-components--carousel.js"),
    readVendor("@stimulus-components--chartjs.js"),
    readVendor("@stimulus-components--color-picker.js"),
  ])
  for (const source of sources) {
    assert.match(source, /@hotwired\/stimulus/)
    // The bar is on third-party runtime imports and remote references, not on
    // a local adapter's property name: the carousel keeps the upstream API
    // surface (this.swiper.slideNext) over a scroll-snap implementation.
    assert.doesNotMatch(
      source,
      /from ["'](swiper|chart\.js|@simonwep\/pickr)["']|require\(["'](swiper|chart\.js|@simonwep\/pickr)["']\)|https?:\/\//,
    )
  }
})

test("carousel exposes the component surface without third-party runtime", async () => {
  const source = await readVendor("@stimulus-components--carousel.js")
  assert.match(source, /static values\s*=\s*\{\s*options\s*:\s*Object\s*\}/)
  assert.match(source, /this\.swiper/)
  assert.match(source, /slideNext/)
  assert.match(source, /slidePrev/)
  assert.match(source, /update/)
  assert.match(source, /destroy/)
  assert.match(source, /defaultOptions/)
})

test("chartjs exposes a canvas chart surface without Chart.js", async () => {
  const source = await readVendor("@stimulus-components--chartjs.js")
  assert.match(source, /static targets\s*=\s*\[\s*"canvas"\s*\]/)
  assert.match(source, /static values\s*=\s*\{\s*type:/)
  assert.match(source, /data\s*:\s*Object/)
  assert.match(source, /this\.chart/)
  assert.match(source, /update/)
  assert.match(source, /destroyChart/)
})

test("color picker exposes the picker lifecycle without Pickr", async () => {
  const source = await readVendor("@stimulus-components--color-picker.js")
  assert.match(source, /static targets\s*=\s*\[\s*"button"\s*,\s*"input"\s*\]/)
  assert.match(source, /this\.picker/)
  assert.match(source, /setColor/)
  assert.match(source, /show/)
  assert.match(source, /hide/)
  assert.match(source, /destroy/)
  assert.match(source, /swatches/)
})

test("Amber analytics mounts animated number on real metrics", async () => {
  const source = await readSource("amber/app/views/wardrobe_items/analytics.html.erb")
  assert.equal((source.match(/data-controller="animated-number"/g) || []).length, 3)
  assert.match(source, /data-animated-number-end-value="<%= @analytics\[:total_items\] %>"/)
  assert.match(source, /data-animated-number-end-value="<%= @analytics\[:active_items\] %>"/)
  assert.match(source, /data-animated-number-end-value="<%= @analytics\[:never_worn\] %>"/)
})

test("the timeago adapter keeps the canonical week duration and a real consumer", async () => {
  const source = await readVendor("@stimulus-components--timeago.js")
  assert.match(source, /\["week",604800000\]/)
  assert.doesNotMatch(source, /\["week",6048000000\]/)

  const reports = await readSource("brgen/app/views/admin/reports/index.html.erb")
  assert.match(reports, /data-controller="timeago"/)
  assert.match(reports, /data-timeago-refresh-interval-value="60000"/)
})
