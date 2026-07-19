# frozen_string_literal: true

require "test_helper"

class RateLimitIncrementTest < ActiveSupport::TestCase
  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @controller = ApplicationController.new
  end

  teardown do
    Rails.cache = @prev_cache
  end

  def test_increment_rate_limit_counts_without_atomic_increment
    key = "master:rl:test:#{SecureRandom.hex(4)}"

    3.times do |index|
      count = @controller.send(:increment_rate_limit!, key, window: 60)
      assert_equal index + 1, count
    end
  end
end