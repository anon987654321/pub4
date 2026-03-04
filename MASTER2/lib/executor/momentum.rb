# frozen_string_literal: true

module Executor
  class Momentum
    LOOKBACK_PERIOD = 14
    MIN_PRICE_POINTS = 2
    PERCENT_SCALE = 100.0
    MIN_MOMENTUM_PERCENT = 1.0

    def initialize(price_series:)
      @price_series = price_series
    end

    def call
      return unless enough_data?

      momentum_percent = momentum_percent(@price_series.last(LOOKBACK_PERIOD))
      return unless momentum_percent.abs >= MIN_MOMENTUM_PERCENT

      momentum_percent
    end

    private

    def enough_data?
      @price_series.size >= MIN_PRICE_POINTS
    end

    def momentum_percent(series)
      first = series.first.to_f
      last = series.last.to_f

      return 0.0 if first.zero?

      ((last - first) / first) * PERCENT_SCALE
    end
  end
end