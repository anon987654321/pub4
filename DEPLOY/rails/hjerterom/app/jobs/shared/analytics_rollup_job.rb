# frozen_string_literal: true

module Shared
  class AnalyticsRollupJob < ApplicationJob
    queue_as :bulk

    def perform(period: "monthly")
      Shared::SearchAnalytics.rollup!(period: period)
    end
  end
end