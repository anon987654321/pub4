# frozen_string_literal: true

require "open3"

module Master
  module Loop
    # OpenBSD-aware host pressure sampling. OpenBSD VMM guests often have no swap
    # and ~1GB RAM — free-memory percentage is the primary back-off signal.
    module SystemPressure
      module_function

      def sample(root: Master::ROOT)
        thresholds = load_thresholds(root)
        mem_free_pct = mem_free_pct_openbsd
        {
          mem_free_pct:,
          load_1m: load_avg_1m,
          thresholds:,
          memory_pressure: memory_pressure?(mem_free_pct, thresholds)
        }
      end

      def memory_pressure?(mem_free_pct = nil, thresholds = nil)
        thresholds ||= load_thresholds(Master::ROOT)
        pct = mem_free_pct.nil? ? mem_free_pct_openbsd : mem_free_pct
        return false unless pct
        crit = thresholds.dig("mem_free_pct", "crit") || thresholds.dig(:mem_free_pct, :crit)
        warn = thresholds.dig("mem_free_pct", "warn") || thresholds.dig(:mem_free_pct, :warn)
        return true if crit && pct <= crit.to_f
        return true if warn && pct <= warn.to_f
        false
      end

      def mem_free_pct_openbsd
        out, _, st = Open3.capture3("/usr/bin/vmstat")
        return nil unless st.success?
        cols = out.lines.last.to_s.strip.split
        return nil if cols.length < 4
        free_bytes = parse_size(cols[3])
        total, _, st2 = Open3.capture3("/sbin/sysctl", "-n", "hw.physmem")
        return nil unless st2.success? && total.to_f.positive?
        ((free_bytes / total.to_f) * 100).round(1)
      rescue StandardError
        nil
      end

      def load_avg_1m
        out, _, st = Open3.capture3("/sbin/sysctl", "-n", "vm.loadavg")
        return nil unless st.success?
        out.tr("{}", "").strip.split.first&.to_f
      rescue StandardError
        nil
      end

      def parse_size(str)
        case str
        when /\A(\d+(?:\.\d+)?)G\z/i then Regexp.last_match(1).to_f * 1_073_741_824
        when /\A(\d+(?:\.\d+)?)M\z/i then Regexp.last_match(1).to_f * 1_048_576
        when /\A(\d+(?:\.\d+)?)K\z/i then Regexp.last_match(1).to_f * 1024
        else str.to_f
        end
      end

      def load_thresholds(root)
        Master.load_yaml(File.join(root, "data", "load.yml"))&.fetch("thresholds", {}) || {}
      rescue StandardError
        {}
      end
    end
  end
end