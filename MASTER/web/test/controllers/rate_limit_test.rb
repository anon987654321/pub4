# frozen_string_literal: true

require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  setup do
    @prev_cache_store = Rails.application.config.cache_store
    Rails.application.config.cache_store = :memory_store
    Rails.cache.clear
  end

  teardown do
    Rails.application.config.cache_store = @prev_cache_store
    Rails.cache.clear
  end

  test "chat rate limit blocks after threshold" do
    limit = ApplicationController::CHAT_RATE_LIMIT
    limit.times do
      get "/chat/message", params: { message: "ping" }
      assert_response :success, "ping #{_1} should succeed"
    end

    get "/chat/message", params: { message: "ping" }
    assert_response :too_many_requests
    assert_match(/rate limit exceeded/, response.body)
  end
end