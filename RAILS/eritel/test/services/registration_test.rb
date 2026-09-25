# frozen_string_literal: true

require "test_helper"

class RegistrationTest < ActiveSupport::TestCase
  setup do
    AuditEvent.delete_all
    RegistryOperation.delete_all
    Order.delete_all
    Domain.delete_all
    Registrant.delete_all
    Participant.delete_all

    @registrant = Registrant.create!(
      email: "verified@example.test",
      country_code: "NO",
      verification_status: "verified"
    )
  end

  test "creates a pending order for a verified direct registrant" do
    order = Eritel::Registration.create(
      domain: " Example.ER ",
      registrant: @registrant,
      idempotency_key: "order-1"
    )

    assert_equal "pending", order.state
    assert_equal "pending", order.domain.state
    assert_equal "example.er", order.domain.name
  end

  test "rejects an unverified registrant before order creation" do
    @registrant.update!(verification_status: "pending")

    assert_raises Eritel::Registration::Rejected do
      Eritel::Registration.create(
        domain: "example.er",
        registrant: @registrant,
        idempotency_key: "order-2"
      )
    end

    assert_empty Order.all
  end

  test "rejects an inactive registrar" do
    registrar = Participant.create!(
      name: "Example Registrar",
      kind: "registrar",
      status: "suspended"
    )

    assert_raises Eritel::Registration::Rejected do
      Eritel::Registration.create(
        domain: "example.er",
        registrant: @registrant,
        participant: registrar,
        mode: "registrar",
        idempotency_key: "order-3"
      )
    end

    assert_empty Order.all
  end
end

  test "rejects an existing active domain" do
    Domain.create!(name: "taken.er", state: "active")

    assert_raises Eritel::Registration::Rejected do
      Eritel::Registration.create(
        domain: "taken.er",
        registrant: @registrant,
        idempotency_key: "order-4"
      )
    end

    assert_empty Order.all
  end
