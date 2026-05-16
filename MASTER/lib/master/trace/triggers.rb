# frozen_string_literal: true

module Master
  module Trace
  class Triggers
    DEFAULTS       = %i[after_scan on_error budget_low tool_after].freeze
    ERROR_TRUNCATE = 200

    def initialize(event_bus:, scanner: nil, agent: nil)
      @bus     = event_bus
      @scanner = scanner
      @agent   = agent
      @rules   = []
    end

    def install_defaults!
      register(:after_scan) do |ctx|
        count = ctx[:violations].to_i
        @bus.publish("triggers:violations_found", count: count) if count > 0
      end

      register(:on_error) do |ctx|
        @bus.publish("triggers:error_logged", error: ctx[:error].to_s[0, ERROR_TRUNCATE])
      end

      register(:budget_low) do |_ctx|
        @bus.publish("triggers:budget_low", action: "switch_to_free_tier")
      end

      @bus.subscribe("tool:after") { |ev| fire(:tool_after, ev) }
      self
    end

    def register(event, &handler)
      @rules << { event: event.to_sym, handler: handler }
    end

    def fire(event, context = {})
      @rules.select { |r| r[:event] == event.to_sym }.each do |rule|
        rule[:handler].call(context)
      rescue StandardError => e
        @bus.publish("triggers:handler_error", event: event, error: e.message)
      end
    end

    def list
      @rules.map { |r| r[:event].to_s }.tally.map { |e, n| "#{e}: #{n} handler(s)" }.join("\n")
    end

    def clear! = @rules.clear
  end
  end
end
