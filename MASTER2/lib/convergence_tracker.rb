# frozen_string_literal: true

module ConvergenceTracker
  DEFAULT_TOLERANCE = 1e-6
  DEFAULT_WINDOW = 5

  LINE_JOIN = " \\\n        "

  INVALID_OPTIONS_MESSAGE = [
    "Invalid options for ConvergenceTracker::Tracker. ",
    "Expected :tolerance (Numeric > 0) and :window (Integer > 0)."
  ].join

  class Tracker
    attr_reader :tolerance, :window, :values

    def initialize(tolerance: DEFAULT_TOLERANCE, window: DEFAULT_WINDOW)
      unless tolerance.is_a?(Numeric) && tolerance.positive? && window.is_a?(Integer) && window.positive?
        raise ArgumentError, INVALID_OPTIONS_MESSAGE
      end

      @tolerance = tolerance
      @window = window
      @values = []
    end

    def record(value)
      numeric_value =
        begin
          Float(value)
        rescue ArgumentError, TypeError
          raise ArgumentError, ["Value must be numeric.", "Got: #{value.inspect}"].join(LINE_JOIN)
        end

      @values << numeric_value
      @values.shift while @values.length > window
      numeric_value
    end

    def converged?
      return false if @values.length < window

      min_value = @values.min
      max_value = @values.max
      (max_value - min_value).abs <= tolerance
    end

    def delta
      return nil if @values.length < 2

      (@values[-1] - @values[-2]).abs
    end

    def reset
      @values.clear
      self
    end
  end
end