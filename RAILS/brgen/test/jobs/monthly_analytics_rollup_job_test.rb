# frozen_string_literal: true

require "test_helper"

class MonthlyAnalyticsRollupJobTest < ActiveSupport::TestCase
  test "writes monthly analytics rollup to cache" do
    written = nil
    cache = Object.new
    cache.define_singleton_method(:write) do |key, value, **options|
      written = { key: key, value: value, options: options }
      true
    end

    Rails.stub(:cache, cache) do
      MonthlyAnalyticsRollupJob.perform_now
    end

    assert_match(/\Abrgen:analytics:monthly:/, written[:key])
    assert_kind_of Hash, written[:value]
    assert written[:options].key?(:expires_in)
  end
end
