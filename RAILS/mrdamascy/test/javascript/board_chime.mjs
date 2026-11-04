// The board grid as nested stand-ins: a new card in the placed column
// chimes once; a card moving on to another column does not. Ages tick from
// each card's placed-at time.
let observe
globalThis.MutationObserver = class { constructor(callback) { observe = callback } observe() {} disconnect() {} }
globalThis.setInterval = () => 0
globalThis.clearInterval = () => {}
const chimes = []
globalThis.window = { AudioContext: undefined }

const card = (id, column) => ({ dataset: { orderId: id }, column })
let cards = [card("1", "placed")]
const time = { dateTime: new Date(Date.now() - 7 * 60_000).toISOString(), textContent: "" }
const board = new Subject({
  querySelectorAll: (selector) => (selector.startsWith("time") ? [time] : cards.filter((c) => c.column === "placed")),
})
board.ageTemplateValue = "%{minutes} min siden"
board.chime = () => chimes.push("chime")
board.connect()

cards = [card("1", "confirmed")]
observe()
const moved = chimes.length

cards = [card("1", "confirmed"), card("2", "placed")]
observe()
console.log(JSON.stringify({ moved, landed: chimes.length, age: time.textContent }))
