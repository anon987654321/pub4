// The pay-bar pulses only for a cart form whose submission succeeded, and
// redraws its total by the money() rule.
const classes = new Set()
globalThis.window = {
  location: { href: "https://mrdamascy.test/menu" },
  addEventListener() {},
  removeEventListener() {},
}
const total = { textContent: "" }
const bar = new Subject({
  classList: { add: (name) => classes.add(name), remove: (name) => classes.delete(name) },
  querySelector: (selector) => (selector === "[data-cart-bar-total]" ? total : null),
})
bar.cartPathValue = "/cart"

const submitted = (action, success) => ({ target: { action }, detail: { success } })
const pulsed = (event) => {
  classes.clear()
  bar.pulse(event)
  return classes.has("cart-bar-pulse")
}

const seen = {
  refused: pulsed(submitted("https://mrdamascy.test/cart/add_item", false)),
  other_form: pulsed(submitted("https://mrdamascy.test/session/request_code", true)),
  added: pulsed(submitted("https://mrdamascy.test/cart/add_item", true)),
}
bar.changed({ detail: { total_ore: 1550 } })
seen.total = total.textContent
console.log(JSON.stringify(seen))
