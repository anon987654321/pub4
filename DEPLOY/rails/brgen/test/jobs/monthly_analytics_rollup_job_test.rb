# frozen_string_literal: true

require 'test_helper'

class MonthlyAnalyticsRollupJobTest < ActiveSupport::TestCase
  test 'writes monthly analytics rollup to cache' do
    cache = Minitest::Mock.new
    cache.expect(:write, true, [String, Hash, Hash])

    Rails.stub(:cache, cache) do
      MonthlyAnalyticsRollupJob.perform_now
    end

    cache.verify
  end
end
