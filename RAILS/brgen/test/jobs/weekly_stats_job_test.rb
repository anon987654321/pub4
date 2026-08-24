# frozen_string_literal: true

require "test_helper"

class WeeklyStatsJobTest < ActiveSupport::TestCase
  test "writes weekly stats to cache" do
    written = nil
    cache = Object.new
    cache.define_singleton_method(:write) do |key, value, **options|
      written = { key: key, value: value, options: options }
      true
    end

    Rails.stub(:cache, cache) do
      WeeklyStatsJob.perform_now
    end

    assert_equal "brgen:weekly_stats", written[:key]
    assert_kind_of Hash, written[:value]
    assert written[:options].key?(:expires_in)
  end
end
