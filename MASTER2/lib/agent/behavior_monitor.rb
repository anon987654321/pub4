# frozen_string_literal: true

module Agent
  class BehaviorMonitor
    DEFAULT_WINDOW_SECONDS = 60
    DEFAULT_MAX_EVENTS = 100
    DEFAULT_MAX_ERROR_RATE = 0.25

    def initialize(window_seconds: DEFAULT_WINDOW_SECONDS, max_events: DEFAULT_MAX_EVENTS, max_error_rate: DEFAULT_MAX_ERROR_RATE)
      @window_seconds = window_seconds
      @max_events = max_events
      @max_error_rate = max_error_rate
      @events = []
    end

    def record(event)
      @events << normalize_event(event)
      prune_old_events!
      nil
    end

    def check
      prune_old_events!
      return ok(:no_data) if @events.empty?

      totals = summarize(@events)
      return ok(:insufficient_data) if totals[:count] < @max_events

      error_rate = totals[:errors].to_f / totals[:count]
      return alert(:high_error_rate, error_rate: error_rate, totals: totals) if error_rate > @max_error_rate

      ok(:healthy, error_rate: error_rate, totals: totals)
    end

    private

    def normalize_event(event)
      h = event.is_a?(Hash) ? event : { type: event }
      { type: h[:type], ok: h.key?(:ok) ? !!h[:ok] : true, ts: h[:ts] || Time.now }
    end

    def prune_old_events!
      cutoff = Time.now - @window_seconds
      @events.shift while @events.first && @events.first[:ts] < cutoff
    end

    def summarize(events)
      count = events.length
      errors = events.count { |e| !e[:ok] }
      { count: count, errors: errors }
    end

    def ok(status, payload = {})
      { status: status, **payload }
    end

    def alert(status, payload = {})
      { status: status, severity: :alert, **payload }
    end
  end
end