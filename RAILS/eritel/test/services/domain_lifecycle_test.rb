# frozen_string_literal: true

require "test_helper"

class DomainLifecycleTest < ActiveSupport::TestCase
  setup do
    Domain.delete_all
    AuditEvent.delete_all
    @domain = Domain.create!(name: "example.er", state: "pending")
  end

  test "permits the normal registration path" do
    Eritel::DomainLifecycle.transition!(@domain, to: "active", actor: "test")

    assert_equal "active", @domain.reload.state
    event = AuditEvent.order(:id).last
    assert_equal "state_transition", event.event_type
    assert_equal "pending", event.data.fetch("from")
    assert_equal "active", event.data.fetch("to")
  end

  test "rejects an invalid transition" do
    assert_raises ArgumentError do
      Eritel::DomainLifecycle.transition!(@domain, to: "parked")
    end

    assert_equal "pending", @domain.reload.state
    assert_empty AuditEvent.all
  end
end
