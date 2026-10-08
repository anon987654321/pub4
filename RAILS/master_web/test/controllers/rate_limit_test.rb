# frozen_string_literal: true

require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @prev_cache
  end

  test "chat rate limit blocks after threshold" do
    limit, = ApplicationController.web_rate_limit(:chat)
    limit.times do
      get "/chat/message", params: { message: "ping" }
      assert_response :success, "ping #{_1} should succeed"
    end

    get "/chat/message", params: { message: "ping" }
    assert_response :too_many_requests
    assert_match(/rate limit exceeded/, response.body)
  end

  test "the budgets are the ones security.yml declares" do
    declared = Master.load_yaml(Master.data_path("security.yml")).fetch("web_rate_limits")

    declared.each do |name, row|
      assert_equal [row["per_window"], row["window_seconds"]], ApplicationController.web_rate_limit(name.to_sym)
    end
    assert_equal ApplicationController::WEB_RATE_LIMIT_DEFAULTS.keys.map(&:to_s).sort, declared.keys.sort
  end
end
