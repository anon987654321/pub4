track("delivered")
track("cancelled")
const finished = seen.intervals

track("preparing", true)
const hidden = seen.intervals

document.hidden = false
listeners.visibilitychange()
console.log(JSON.stringify({ finished, hidden, shown: seen.intervals }))
