# frozen_string_literal: true

module Master
  module Trace
  # /diag — composed snapshot of internal state. Replaces ad-hoc grep over logs.
    class Diag
      SECTIONS = %i[drives breaker rules ring].freeze
      RING_LINES = 8

      def initialize(homeostat:, breaker:, logging:, scan_registry: Master::Judge::Scan::Rule)
        @homeostat = homeostat
        @breaker = breaker
        @logging = logging
        @registry = scan_registry
      end

      def render(section = nil)
        keys = section.to_s.empty? ? SECTIONS : [section.to_sym].select { |k| SECTIONS.include?(k) }
        return "diag: unknown section -- valid: #{SECTIONS.join(", ")}" if keys.empty?
        lines.concat(keys.flat_map { |k| send("section_#{k}") })
        lines.join("\n")
      end

      private

      def section_drives
        return ["drives: -- (no homeostat)"] unless @homeostat
      end

      def section_breaker
        return ["breaker: -- (no breaker)"] unless @breaker
        open = @breaker.open_models
        ["breaker: session=$#{total} open=(#{open.empty? ? "" : open.join(",")})"]
      end

      def section_rules
        return ["rules: -- (no registry)"] unless @registry
      end

      def section_ring
        return ["ring: -- (no logging)"] unless @logging
        ["ring (last #{tail.size}):", *tail.map { |l| "  #{l}" }]
      end
    end
  end
end
