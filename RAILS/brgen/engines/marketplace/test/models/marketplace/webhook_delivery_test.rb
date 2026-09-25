# frozen_string_literal: true

require "test_helper"

class Marketplace::WebhookDeliveryTest < ActiveSupport::TestCase
  test "provider retry ceiling is exhausted on the fifth delivery" do
    delivery = Marketplace::WebhookDelivery.new(
      provider: "dintero",
      event_delivery: SecureRandom.uuid,
      event: "checkout_transaction",
      received_at: Time.current
    )

    delivery.attempts = 3
    assert_not delivery.provider_attempts_exhausted?

    delivery.attempts = 4
    assert delivery.provider_attempts_exhausted?
  end
end
