// print_controller under node: a stand-in window counts prints, the button
// starts hidden as the order page renders it.
let printed = 0
globalThis.window = { print: () => { printed += 1 } }
const button = { hidden: true }
const subject = new Subject(button)
subject.connect()
subject.print()
console.log(JSON.stringify({ hidden: button.hidden, printed }))
