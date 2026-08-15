# frozen_string_literal: true

require "test_helper"

class AuthTierControllerTest < ActionDispatch::IntegrationTest
  test "visitor cannot read dmesg" do
    get "/chat/dmesg"

    assert_response :unauthorized
  end

  test "authenticated client can read dmesg" do
    get "/chat/dmesg", headers: auth_headers

    assert_response :success
  end

  test "visitor cannot read chat history" do
    get "/chat/history"

    assert_response :unauthorized
  end

  test "authenticated client can read chat history" do
    get "/chat/history", headers: auth_headers

    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test "visitor cannot read metrics" do
    get "/chat/metrics"

    assert_response :unauthorized
  end

  test "authenticated client can read metrics" do
    get "/chat/metrics", headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "model", body["model"]
  end

  test "visitor cannot read dashboard live feed" do
    get "/dashboard/live"

    assert_response :unauthorized
  end

  test "visitor cannot scrape prometheus metrics" do
    get "/metrics"

    assert_response :unauthorized
  end

  test "authenticated client can scrape prometheus metrics" do
    get "/metrics", headers: auth_headers

    assert_response :success
    assert_includes response.body, "master_up"
  end

  test "visitor can still smoke ping chat stream" do
    get "/chat/message", params: { message: "ping" }

    assert_response :success
    assert_includes response.body, "pong"
  end

  test "visitor cannot post chat command" do
    post "/chat/command", params: { command: "/help" }, as: :json

    assert_response :forbidden
  end

  test "authenticated client can post chat command" do
    gateway = Class.new do
      def receive(channel:, message:)
        Master::Result.ok({ rendered: "help ok", client_actions: [] })
      end
    end.new
    Rails.application.config.x.master_container[:gateway] = gateway

    post "/chat/command", params: { command: "/help" }, headers: auth_headers, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "help ok", body["output"]
  end

  test "visitor can unlock with web token" do
    post "/chat/command",
         params: { command: "/unlock #{TEST_WEB_TOKEN}" },
         as: :json

    assert_response :success
    assert_includes response.body, "unlocked"
    refute_equal "1", cookies[:master_unlocked]
    assert cookies[:master_unlocked].to_s.match?(/\A[0-9a-f]{64}\z/)
  end

  test "a forged master_unlocked=1 cookie is not elevation" do
    cookies[:master_unlocked] = "1"
    post "/chat/command", params: { command: "/help" }, as: :json

    assert_response :forbidden
  end

  test "visitor cannot unlock with wrong token" do
    post "/chat/command", params: { command: "/unlock wrong-token" }, as: :json

    assert_response :unauthorized
    assert_includes response.body, "unlock denied"
  end

  test "visitor can post canvas mood events" do
    post "/canvas/event", params: { topic: "canvas:mood", payload: { mood: "calm" } }

    assert_response :accepted
  end
end
