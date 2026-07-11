# frozen_string_literal: true

require_relative "test_helper"

class TestOpenclawBridge < Minitest::Test
  def test_trust_defaults_untrusted
    body = { message: "hi", channel: "telegram" }
    assert_equal :untrusted, Master::Reach::OpenclawBridge.trust(body)
    refute Master::Reach::OpenclawBridge.elevated?(body)
  end

  def test_trust_owner_elevated
    body = { message: "hi", metadata: { trust: "owner" } }
    assert Master::Reach::OpenclawBridge.elevated?(body)
  end

  def test_gateway_metadata_maps_session
    body = {
      session_key: "oc:telegram:peer:99",
      channel: "telegram",
      message: "scan lib/",
      metadata: { sender: "operator", openclaw_turn_id: "t1" },
    }
    meta = Master::Reach::OpenclawBridge.gateway_metadata(body)
    assert_equal "oc:telegram:peer:99", meta[:openclaw_session]
    assert_equal "telegram", meta[:openclaw_channel]
    assert_equal "t1", meta[:openclaw_turn_id]
  end
end