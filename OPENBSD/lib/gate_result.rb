# frozen_string_literal: true

module Deploy
  class GateResult
    attr_reader :failures, :warnings, :soft_failures

    # GATE_STRICT_SOFT=1 promotes soft failures to hard (merge-blocking).
    def self.strict_soft?(env = ENV)
      %w[1 true yes on].include?(env["GATE_STRICT_SOFT"].to_s.strip.downcase)
    end

    def initialize
      @failures = []
      @warnings = []
      @soft_failures = []
    end

    # severity: :hard (default, blocks) | :soft (warn unless GATE_STRICT_SOFT)
    def fail(message, severity: :hard)
      case severity.to_sym
      when :soft
        @soft_failures << message
        if self.class.strict_soft?
          @failures << "[soft→hard] #{message}"
        else
          @warnings << "[soft] #{message}"
        end
      else
        @failures << message
      end
    end

    def warn(message)
      @warnings << message
    end

    def ok?
      @failures.empty?
    end

    def merge!(other)
      Array(other.failures).each { |m| @failures << m }
      Array(other.warnings).each { |w| @warnings << w }
      Array(other.soft_failures).each { |m| @soft_failures << m } if other.respond_to?(:soft_failures)
      self
    end

    def report!(success_message)
      unless @warnings.empty?
        Kernel.warn "Warnings:"
        @warnings.each { |warning| Kernel.warn "  - #{warning}" }
      end

      if ok?
        puts success_message
      else
        Kernel.warn "Failures:"
        @failures.each { |failure| Kernel.warn "  - #{failure}" }
        exit 1
      end
    end
  end
end
