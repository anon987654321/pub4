# frozen_string_literal: true

require "test_helper"

class RegistryCommandTest < ActiveSupport::TestCase
  setup do
    AuditEvent.delete_all
    RegistryOperation.delete_all
    Order.delete_all
    Domain.delete_all
    Registrant.delete_all

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
    assert_equal first.request_id, @order.reload.registry_request_id
  end

  test "successful creation activates the order and domain" do
    Eritel::RegistryCommand.call(order: @order)

    assert_equal "active", @order.reload.state
    assert_equal "active", @order.domain.reload.state
    assert_equal 2, AuditEvent.count
    assert_equal "registry_operation", AuditEvent.order(:id).last.event_type
  end
end
