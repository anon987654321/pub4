# frozen_string_literal: true

module Master
  module Trace
  # /diag — composed snapshot of internal state. Replaces ad-hoc grep over logs.
    class Diag
      SECTIONS = %i[drives breaker cache rules ring].freeze
      RING_LINES = 8
      CACHE_EVENT_LIMIT = 12

      def initialize(homeostat:, breaker:, logging:, scan_registry: Master::Judge::Scan::Rule, event_bus: nil)
        @homeostat = homeostat
        @breaker = breaker
        @logging = logging
        @registry = scan_registry
        @cache_hits = []
        @cache_mutex = Mutex.new
        event_bus&.subscribe("cache:hit") { |payload| record_cache_hit(payload) }
      end

      def render(section = nil)
        keys = section.to_s.empty? ? SECTIONS : [section.to_sym].select { |k| SECTIONS.include?(k) }
        return "diag: unknown section -- valid: #{SECTIONS.join(", ")}" if keys.empty?
        lines = []
        lines.concat(keys.flat_map { |k| send("section_#{k}") })
        lines.join("\n")
      end

      private

      def record_cache_hit(payload)
        @cache_mutex.synchronize do
          @cache_hits << payload.dup
          @cache_hits.shift while @cache_hits.size > CACHE_EVENT_LIMIT
        end
      end

      def section_drives
        return ["drives: -- (no homeostat)"] unless @homeostat
        return [@homeostat.summary] if @homeostat.respond_to?(:summary)

        ["drives: #{@homeostat.to_h}"]
      end

      def section_breaker
        return ["breaker: -- (no breaker)"] unless @breaker
        open = @breaker.open_models
        total = @breaker.respond_to?(:session_total) ? @breaker.session_total.to_f : 0.0
        ["breaker: session=$#{format('%.4f', total)} open=(#{open.empty? ? "" : open.join(",")})"]
      end

      def section_cache
        hits = @cache_mutex.synchronize { @cache_hits.dup }
        return ["cache: hits=0 cached_tokens=0 cache_writes=0"] if hits.empty?

        cached = hits.sum { |hit| hit[:cached].to_i }
        writes = hits.sum { |hit| hit[:cache_write].to_i }
        models = hits.map { |hit| hit[:model] }.compact.uniq
        line = "cache: hits=#{hits.size} cached_tokens=#{cached} cache_writes=#{writes}"
        line = "#{line} models=#{models.join(",")}" unless models.empty?
        [line]
      end

      def section_rules
        return ["rules: -- (no registry)"] unless @registry
        count = @registry.respond_to?(:registry) ? @registry.registry.size : 0
        ["rules: #{count} registered"]
      end

      def section_ring
        return ["ring: -- (no logging)"] unless @logging
        tail = @logging.dmesg(RING_LINES).lines.map(&:chomp).reject(&:empty?)
        ["ring (last #{tail.size}):", *tail.map { |l| "  #{l}" }]
      end
    end
  end
end
