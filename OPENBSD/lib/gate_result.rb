# frozen_string_literal: true

module Deploy
  class GateResult
    attr_reader :failures, :warnings

    def initialize
      @failures = []
      @warnings = []
    end

    def fail(message)
      @failures << message
    end

    def warn(message)
      @warnings << message
    end

    def ok?
      @failures.empty?
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
