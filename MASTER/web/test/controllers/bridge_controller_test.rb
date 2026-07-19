# frozen_string_literal: true

require "test_helper"

class BridgeControllerTest < ActionDispatch::IntegrationTest
  def setup
    @token = MasterBridgeToken.read
    skip "bridge token not configured" if @token.empty?
  end

  def test_health_without_auth
    get "/bridge/health"
    assert_response :success
    body = JSON.parse(response.body)
    assert body["ok"]
    assert_equal "master-bridge", body["service"]
  end

  def test_turn_requires_token
    post "/bridge/turn", params: { message: "ping" }, as: :json
    assert_response :unauthorized
  end

  def test_turn_with_token
    post "/bridge/turn",
         params: { message: "/help", session_key: "oc:test:1", channel: "telegram" },
         headers: { "Authorization" => "Bearer #{@token}" },
         as: :json
    assert_includes [200, 503], response.status
    return if response.status == 503

    body = JSON.parse(response.body)
    assert body["ok"]
    assert body["output"].to_s.length.positive?
    assert body["constitutional"]
  end
end