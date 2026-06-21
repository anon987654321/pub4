# frozen_string_literal: true

require "open3"

module Master
  module Loop
    module SystemPressure
      DEFAULT_THRESHOLDS = {
        "mem_free_pct" => { "warn" => 20, "crit" => 10 },
      }.freeze

      module_function

      def memory_pressure?(mem_free_pct, thresholds = DEFAULT_THRESHOLDS)
        crit = thresholds.dig("mem_free_pct", "crit").to_f
        mem_free_pct.to_f <= crit
      end

      def sample(thresholds: DEFAULT_THRESHOLDS)
        mem_free_pct = current_mem_free_pct
        {
          mem_free_pct: mem_free_pct,
          memory_pressure: memory_pressure?(mem_free_pct, thresholds),
          thresholds: thresholds,
        }
      end

      def current_mem_free_pct
        return 100.0 unless RUBY_PLATFORM.include?("openbsd")

        out, status = Open3.capture2("sysctl", "-n", "hw.physmem", "vm.stats.vm.v_free_count", "vm.stats.vm.v_page_size")
        return 100.0 unless status.success?

        physmem, free_count, page_size = out.lines.map(&:strip).map(&:to_f)
        return 100.0 if physmem <= 0

        ((free_count * page_size) / physmem) * 100.0
      rescue StandardError
        100.0
      end
    end
  end
end