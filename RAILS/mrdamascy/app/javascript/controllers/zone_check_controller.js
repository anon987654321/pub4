import { Controller } from "@hotwired/stimulus"

// Zone check (§8): as the postcode is typed, GET /checkout/zone?postcode=…
// (json: { ok, eta, name, fee_text, total_text, eta_text, minimum_text,
// vipps_label, stripe_label }) and render the feedback, the fee, total and
// ETA lines, the basket-minimum warning and the pay-button labels from it;
// the server words and formats every amount. Each lookup aborts the one
// before, so a slow answer for an earlier postcode cannot land last.
// Copy templates arrive as i18n values with %{eta}/%{fee}/%{postcode} tokens.
// Also toggles the address fields off in pickup mode.
export default class extends Controller {
  static targets = ["postcode", "feedback", "addressWrap", "fee", "total", "eta", "minimum", "vipps", "stripe"]
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
      this.lookup?.abort()
      const lookup = new AbortController()
      this.lookup = lookup
      fetch(`${this.urlValue}?postcode=${encodeURIComponent(postcode)}`, {
        headers: { Accept: "application/json" },
        signal: lookup.signal,
      })
        .then((response) => response.json())
        .then((data) => {
          if (lookup.signal.aborted) return
          if (data?.ok) {
            this.feedbackTarget.textContent = this.interpolate(this.okValue, {
              eta: data.eta != null ? data.eta : "",
              fee: data.fee_text || "",
              name: data.name || "",
            })
            this.feedbackTarget.classList.add("zone-ok")
          } else {
            this.feedbackTarget.textContent = this.interpolate(this.failValue, { postcode: postcode })
            this.feedbackTarget.classList.add("zone-fail")
          }
          this.showLines(data || {})
        })
        .catch(() => {
          if (!lookup.signal.aborted) this.feedbackTarget.textContent = ""
        })
    }, 250)
  }

  showLines(data) {
    if (this.hasFeeTarget && data.fee_text) this.feeTarget.textContent = data.fee_text
    if (this.hasTotalTarget && data.total_text) this.totalTarget.textContent = data.total_text

    if (this.hasEtaTarget) {
      this.etaTarget.textContent = data.eta_text ?? ""
      this.etaTarget.hidden = !data.eta_text
    }

    if (this.hasMinimumTarget) {
      this.minimumTarget.textContent = data.minimum_text ?? ""
      this.minimumTarget.hidden = !data.minimum_text
    }

    if (this.hasVippsTarget && data.vipps_label) this.vippsTarget.textContent = data.vipps_label
    if (this.hasStripeTarget && data.stripe_label) this.stripeTarget.textContent = data.stripe_label
  }

  disconnect() {
    clearTimeout(this.timer)
    this.lookup?.abort()
  }

  modeChanged() {
    this.toggleAddress()
  }

  // private

  toggleAddress() {
    const pickupInput = this.element.querySelector('input[name="mode"]:checked')
    const pickup = pickupInput ? pickupInput.value === "pickup" : false
    // Hidden fields are disabled too, so their required rules do not
    // block a pickup order.
    this.addressWrapTargets.forEach((element) => {
      element.hidden = pickup
      element.querySelectorAll("input").forEach((input) => {
        input.disabled = pickup
      })
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
