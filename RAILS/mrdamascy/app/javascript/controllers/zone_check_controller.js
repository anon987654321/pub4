import { Controller } from "@hotwired/stimulus"

// Zone check (§8): as the postcode is typed, GET /checkout/zone?postcode=…
// (json: { ok, fee_ore, eta, name }) and render fee/eta or failure inline.
// Copy templates arrive as i18n values with %{eta}/%{fee}/%{postcode} tokens.
// Also toggles the address fields off in pickup mode.
export default class extends Controller {
  static targets = ["postcode", "feedback", "addressWrap"]
  static values = {
    url: String,
    ok: String,
    fail: String,
    checking: String,
    pickup: String,
  }

  connect() {
    if (this.hasPostcodeTarget && this.postcodeTarget.value.trim().length >= 4) {
      this.check()
    }
    this.toggleAddress()
  }

  check() {
    if (!this.hasFeedbackTarget) return
    const postcode = (this.hasPostcodeTarget ? this.postcodeTarget.value : "").trim()

    if (postcode.length < 4) {
      this.feedbackTarget.textContent = ""
      this.feedbackTarget.classList.remove("zone-ok", "zone-fail")
      return
    }

    this.feedbackTarget.classList.remove("zone-ok", "zone-fail")
    this.feedbackTarget.textContent = this.checkingValue || "…"

    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      fetch(`${this.urlValue}?postcode=${encodeURIComponent(postcode)}`, {
        headers: { Accept: "application/json" },
      })
        .then((response) => response.json())
        .then((data) => {
          if (data?.ok) {
            this.feedbackTarget.textContent = this.interpolate(this.okValue, {
              eta: data.eta != null ? data.eta : "",
              fee: data.fee_ore != null ? `${Math.round(data.fee_ore / 100)} kr` : "",
              name: data.name || "",
            })
            this.feedbackTarget.classList.add("zone-ok")
          } else {
            this.feedbackTarget.textContent = this.interpolate(this.failValue, { postcode: postcode })
            this.feedbackTarget.classList.add("zone-fail")
          }
        })
        .catch(() => {
          this.feedbackTarget.textContent = ""
        })
    }, 250)
  }

  modeChanged() {
    this.toggleAddress()
  }

  // private

  toggleAddress() {
    const pickupInput = this.element.querySelector('input[name="mode"]:checked')
    const pickup = pickupInput ? pickupInput.value === "pickup" : false
    this.addressWrapTargets.forEach((element) => {
      element.hidden = pickup
    })
    if (this.hasFeedbackTarget) {
      if (pickup) {
        this.feedbackTarget.textContent = this.pickupValue || ""
        this.feedbackTarget.classList.add("zone-ok")
      } else if (this.hasPostcodeTarget && this.postcodeTarget.value.trim().length >= 4) {
        this.check()
      }
    }
  }

  interpolate(template, values) {
    return Object.entries(values || {}).reduce(
      (text, [key, value]) => text.split(`%{${key}}`).join(String(value)),
      template || ""
    )
  }
}
