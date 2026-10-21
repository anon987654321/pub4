# frozen_string_literal: true

require "test_helper"

class NvdRateLimitTest < ActiveSupport::TestCase
  setup do
    NvdRateLimit.delete_all
    @now = Time.zone.parse("2026-10-21 12:00:00")
    @original_key = ENV["NVD_API_KEY"]
  end

  teardown do
    @original_key.nil? ? ENV.delete("NVD_API_KEY") : ENV["NVD_API_KEY"] = @original_key
  end

  test "anonymous requests are assigned distinct six-second slots without sleeping" do
    ENV.delete("NVD_API_KEY")

    Time.stub(:current, @now) do
      assert_nil NvdRateLimit.claim_or_defer
      assert_equal @now + 6.seconds, NvdRateLimit.claim_or_defer
    end
  end

  test "keyed requests use a more conservative subsecond interval" do
    ENV["NVD_API_KEY"] = "test-key"

    Time.stub(:current, @now) do
      assert_nil NvdRateLimit.claim_or_defer
      assert_equal @now + 0.6.seconds, NvdRateLimit.claim_or_defer
    end
  end
end
