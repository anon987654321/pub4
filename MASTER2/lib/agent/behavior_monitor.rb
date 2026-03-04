# frozen_string_literal: true

module Agent
  class BehaviorMonitor
    DEFAULT_THRESHOLDS = {
      error_rate: 0.25,
      max_events: 1_000
    }.freeze

    attr_reader :thresholds

    def initialize(options = {})
      thresholds_option = options.fetch(:thresholds, nil)
      @thresholds = DEFAULT_THRESHOLDS.merge(thresholds_option || {})
      @events = []
    end

    def record(event)
      return false unless event.is_a?(Hash)

      normalized = normalize_event(event)
      @events << normalized
      prune_events
      true
    end

    def status
      total = @events.length
      return default_status if total.zero?

      error_count = @events.count { |evt| evt[:level] == :error }
      error_rate = error_count.to_f / total

      {
        total_events: total,
        error_events: error_count,
        error_rate: error_rate,
        healthy: healthy?(total, error_rate)
      }
    end

    def healthy?
      current = status
      current.fetch(:healthy)
    end

    private

    def normalize_event(event)
      {
        level: normalize_level(event.fetch(:level, nil)),
        name: event.fetch(:name, "unknown"),
        timestamp: event.fetch(:timestamp, Time.now),
        metadata: event.fetch(:metadata, {}) || {}
      }
    end

    def normalize_level(level)
      return :info if level.nil?

      sym = level.to_sym
      return sym if %i[debug info warn error fatal].include?(sym)

      :info
    end

    def prune_events
      max_events = thresholds.fetch(:max_events, DEFAULT_THRESHOLDS.fetch(:max_events))
      overflow = @events.length - max_events
      return if overflow <= 0

      @events.shift(overflow)
    end

    def healthy?(total_events, error_rate)
      max_events = thresholds.fetch(:max_events, DEFAULT_THRESHOLDS.fetch(:max_events))
      error_threshold = thresholds.fetch(:error_rate, DEFAULT_THRESHOLDS.fetch(:error_rate))

      total_events <= max_events && error_rate <= error_threshold
    end

    def default_status
      {
        total_events: 0,
        error_events: 0,
        error_rate: 0.0,
        healthy: true
      }
    end
  end
end