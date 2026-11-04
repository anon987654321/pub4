// Pickup checked: the address fields hide and their inputs are disabled,
// so their required rules cannot block the pickup order.
const input = () => ({ disabled: false })
const wrap = () => {
  const inputs = [input()]
  return { hidden: false, inputs, querySelectorAll: () => inputs }
}

const wraps = [wrap(), wrap()]
const zone = new Subject({ querySelector: () => ({ value: "pickup" }) })
Object.assign(zone, { addressWrapTargets: wraps, hasFeedbackTarget: false })

zone.modeChanged()
console.log(JSON.stringify({
  hidden: wraps.map((element) => element.hidden),
  disabled: wraps.flatMap((element) => element.inputs.map((field) => field.disabled)),
}))
