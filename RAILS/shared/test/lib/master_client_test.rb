# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/shared/master_client"

class MasterClientTest < Minitest::Test
  def test_health_uses_ingress_health
    calls = []
    client = Shared::MasterClient.new(base_url: "https://master.test", token: "t" * 16)

    client.stub(:get, ->(path) { calls << path; { "ok" => true } }) do
      assert client.available?
    end

    assert_equal ["/ingress/health"], calls
  end

  def test_turn_uses_ingress_webhook
    calls = []
    client = Shared::MasterClient.new(base_url: "https://master.test", token: "t" * 16)

    client.stub(:post, lambda { |path, body|
      calls << [path, body]
      { "ok" => true, "output" => "answer" }
    }) do
      result = client.turn("What changed?", session_key: "brgen:conversation:1", channel: "brgen-messenger")
      assert result["ok"]
    end

    path, body = calls.fetch(0)
    assert_equal "/ingress/webhook/rails_master", path
    assert_equal "What changed?", body.fetch(:message)
    assert_equal "brgen:conversation:1", body.fetch(:session_key)
    assert_equal "brgen-messenger", body.fetch(:channel)
  end

  def test_uses_only_the_ingress_token
    previous = %w[MASTER_INGRESS_TOKEN MASTER_BRIDGE_TOKEN MASTER_INTERNAL_TOKEN].to_h { |k| [k, ENV.fetch(k, nil)] }

    ENV.delete("MASTER_INGRESS_TOKEN")
    ENV["MASTER_BRIDGE_TOKEN"] = "legacy-bridge-token"
    ENV["MASTER_INTERNAL_TOKEN"] = "internal-token"

    assert_equal "", Shared::MasterClient.token
    refute Shared::MasterClient.configured?
  ensure
    previous.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
end
