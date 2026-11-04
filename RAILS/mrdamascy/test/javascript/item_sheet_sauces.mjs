// Three sauce chips: picking two locks the third and says so once in the
// polite notice; dropping one unlocks it and clears the notice. The price
// follows the money() rule, øre included.
const sauce = () => ({ checked: false, disabled: false, dataset: { kind: "sauce", priceOre: "0" } })
const sauces = [sauce(), sauce(), sauce()]
const sheet = new Subject({})
Object.assign(sheet, {
  optionTargets: sauces, quantityTarget: { value: "1" }, baseValue: 1550, templateValue: "",
  hasPriceTarget: true, priceTarget: { textContent: "" }, hasSubmitTarget: false,
  hasSauceNoticeTarget: true, sauceNoticeTarget: { textContent: "" }, sauceLimitValue: "two chosen",
})
sheet.connect()

sauces[0].checked = true
sauces[1].checked = true
sheet.recalc()
const full = { locked: sauces[2].disabled, notice: sheet.sauceNoticeTarget.textContent }

sauces[1].checked = false
sheet.recalc()
console.log(JSON.stringify({
  full,
  unlocked: !sauces[2].disabled,
  cleared: sheet.sauceNoticeTarget.textContent,
  price: sheet.priceTarget.textContent,
}))
