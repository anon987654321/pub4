# frozen_string_literal: true

require "test_helper"
require_relative "stimulus_node"

class ZoneCheckControllerTest < ActiveSupport::TestCase
  include StimulusNode

  # Two lookups in flight: the earlier postcode's answer arrives last.
  SCRIPT = <<~JS
    const later = globalThis.setTimeout
    const tick = () => new Promise((resolve) => later(resolve, 0))
    globalThis.setTimeout = (callback) => { callback(); return 0 }
    globalThis.clearTimeout = () => {}

    const pending = []
    globalThis.fetch = (url, options) => new Promise((resolve, reject) => {
      pending.push((data) => resolve({ json: () => Promise.resolve(data) }))
      options?.signal?.addEventListener("abort", () => reject(new Error("aborted")))
    })

    const line = () => ({ textContent: "", hidden: false, classList: { add() {}, remove() {} } })
    const zone = new Subject({ querySelector: () => null })
    Object.assign(zone, {
      urlValue: "/checkout/zone", okValue: "ok %{fee}", failValue: "fail %{postcode}", checkingValue: "…",
      hasPostcodeTarget: true, postcodeTarget: { value: "5004" }, hasFeedbackTarget: true, feedbackTarget: line(),
      hasFeeTarget: true, feeTarget: line(), hasTotalTarget: true, totalTarget: line(),
      hasEtaTarget: true, etaTarget: line(), hasMinimumTarget: true, minimumTarget: line(),
      hasVippsTarget: true, vippsTarget: line(), hasStripeTarget: true, stripeTarget: line(),
    })

    zone.check()
    zone.postcodeTarget.value = "5005"
    zone.check()
    pending[1]({ ok: true, fee_text: "29 kr", total_text: "158 kr", eta_text: "Ca. 20 min til døren",
                 minimum_text: null, vipps_label: "Betal 158 kr med Vipps", stripe_label: "Betal 158 kr med kort" })
    await tick()

    pending[0]({ ok: false })
    await tick()
    console.log(JSON.stringify({
      feedback: zone.feedbackTarget.textContent, fee: zone.feeTarget.textContent,
      total: zone.totalTarget.textContent, eta: zone.etaTarget.textContent,
      minimum_hidden: zone.minimumTarget.hidden, vipps: zone.vippsTarget.textContent,
      stripe: zone.stripeTarget.textContent,
    }))
  JS

  test "the current postcode's answer wins and fills the fee, total, ETA and buttons" do
    seen = run_stimulus("zone_check", SCRIPT)

    assert_equal "ok 29 kr", seen["feedback"], "the earlier postcode's late answer must not overwrite"
    assert_equal "29 kr", seen["fee"]
    assert_equal "158 kr", seen["total"]
    assert_equal "Ca. 20 min til døren", seen["eta"]
    assert seen["minimum_hidden"]
    assert_equal "Betal 158 kr med Vipps", seen["vipps"]
    assert_equal "Betal 158 kr med kort", seen["stripe"]
  end

  test "pickup hides the address fields and disables their inputs" do
    seen = run_stimulus("zone_check", "zone_check_pickup.mjs")

    assert_equal [ true, true ], seen["hidden"]
    assert_equal [ true, true ], seen["disabled"], "hidden required fields must not block a pickup order"
  end
end
