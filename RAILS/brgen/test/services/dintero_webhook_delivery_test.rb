# frozen_string_literal: true

require "test_helper"

class DinteroWebhookDeliveryTest < ActiveSupport::TestCase
  test "only a fresh first delivery is active" do
    delivery = Marketplace::WebhookDelivery.new(
      provider: "dintero",
      event_delivery: SecureRandom.uuid,
      event: "checkout_transaction",
      received_at: Time.current,
      attempts: 0,
      status: "processing"
    )

    assert delivery.active?

    delivery.attempts = 1
    assert_not delivery.active?
  end

  test "fifth provider attempt is terminal" do
    delivery = Marketplace::WebhookDelivery.new(
      provider: "dintero",
      event_delivery: SecureRandom.uuid,
      event: "checkout_transaction",
      received_at: Time.current,
      attempts: 4,
      status: "processing"
    )

    assert delivery.provider_attempts_exhausted?

    delivery.status = "failed"
    assert_not delivery.active?
  end
end
