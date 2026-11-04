// Two chips and their sections: the section reported in view marks its
// chip current and clears the other.
let report
globalThis.IntersectionObserver = class {
  constructor(callback) { report = callback }
  observe() {}
  disconnect() {}
}
const sections = { "cat-wraps": { id: "cat-wraps" }, "cat-drikke": { id: "cat-drikke" } }
globalThis.document = { getElementById: (id) => sections[id] }

const chip = (href) => {
  const attributes = { href }

  return {
    getAttribute: (name) => attributes[name] ?? null,
    setAttribute: (name, value) => { attributes[name] = value },
    removeAttribute: (name) => { delete attributes[name] },
    current: () => attributes["aria-current"] ?? null,
  }
}
const chips = [chip("#cat-wraps"), chip("#cat-drikke")]
const spy = new Subject({})
spy.chipTargets = chips
spy.connect()

report([{ isIntersecting: true, target: sections["cat-wraps"] }])
const first = chips.map((c) => c.current())
report([
  { isIntersecting: false, target: sections["cat-wraps"] },
  { isIntersecting: true, target: sections["cat-drikke"] },
])
console.log(JSON.stringify({ first, then: chips.map((c) => c.current()) }))
