# frozen_string_literal: true

require "test_helper"

class WeeklyStatsJobTest < ActiveSupport::TestCase
  test "writes weekly stats to cache" do
    cache = Minitest::Mock.new
    cache.expect(:write, true, ["brgen:weekly_stats", Hash, Hash])

    Rails.stub(:cache, cache) do
      WeeklyStatsJob.perform_now
    end

    cache.verify
  end
end
