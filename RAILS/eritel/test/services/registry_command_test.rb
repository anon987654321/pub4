# frozen_string_literal: true

require "test_helper"

class RegistryCommandTest < ActiveSupport::TestCase
  setup do
    Domain.delete_all
    Registrant.delete_all
    Order.delete_all
    RegistryOperation.delete_all

    domain = Domain.create!(name: "example.er", state: "pending")
    registrant = Registrant.create!(
      email: "owner@example.test",
      country_code: "NO",
      verification_status: "verified"
    )

    @order = Order.create!(
      domain: domain,
      registrant: registrant,
      operation: "create",
      state: "pending",
      idempotency_key: SecureRandom.uuid
    )
  end

  test "creates one registry operation and reuses it" do
    first = Eritel::RegistryCommand.call(order: @order)
    second = Eritel::RegistryCommand.call(order: @order)

    assert_equal first.id, second.id
    assert_equal 1, RegistryOperation.count
    assert_equal "succeeded", second.state
  end
end
