# frozen_string_literal: true

require "open3"
require "time"

module Master
  module Loop
    # Watcher — continuous OpenBSD load monitor.
    # Polls load avg, memory, disk, master service. Publishes system:sample
    # every interval, system:warn/crit on threshold crossings.
    class Watcher
      DEFAULT_INTERVAL = 30
      @@last_sample = nil

      def self.last_sample = @@last_sample

      # One-shot sample without a running watcher. Used by /status.
      def self.sample_once(root: Master::ROOT)
        new(bus: nil, root:).sample!
      end

      def initialize(bus:, root:, interval: nil)
        @bus        = bus
        @root       = root
        cfg         = load_config
        @interval   = interval || cfg["interval_seconds"] || DEFAULT_INTERVAL
        @thresholds = cfg["thresholds"] || {}
        @prev_level = :ok
      end

      def run_forever
        loop do
          sample!
          sleep @interval
        end
      rescue StandardError => e
        @bus&.publish("watcher:error", error: e.message)
      end

      def sample!
        s     = build_sample
        @@last_sample = s
        level = classify(s)
        case level
        when :crit then @bus&.publish("system:crit", s.merge(level: "crit"))
        when :warn then @bus&.publish("system:warn", s.merge(level: "warn")) if @prev_level != :warn
        else            @bus&.publish("system:sample", s)
        end
        @prev_level = level
        s
      end

      private

      def build_sample
        {
          ts: Time.now.utc.iso8601,
          load_1m: load_avg_1m,
          mem_free_pct: mem_free_pct,
          disk_root_pct: disk_root_pct,
          master_rss_mb: master_rss_mb,
          master_alive: master_alive?
        }
      end

      def load_avg_1m
        out, _, st = Open3.capture3("/sbin/sysctl", "-n", "vm.loadavg")
        return nil unless st.success?
        out.tr("{}", "").strip.split.first&.to_f
      rescue StandardError
        nil
      end

      # OpenBSD does not expose vm.uvmexp.free via sysctl — parse vmstat instead.
      def mem_free_pct
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

      def parse_size(str)
        case str
        when /\A(\d+(?:\.\d+)?)G\z/i then Regexp.last_match(1).to_f * 1_073_741_824
        when /\A(\d+(?:\.\d+)?)M\z/i then Regexp.last_match(1).to_f * 1_048_576
        when /\A(\d+(?:\.\d+)?)K\z/i then Regexp.last_match(1).to_f * 1024
        else str.to_f
        end
      end

      def disk_root_pct
        out, _, st = Open3.capture3("/bin/df", "-k", "/")
        return nil unless st.success?
        out.lines[1].to_s.split[4].to_s.tr("%", "").to_i
      rescue StandardError
        nil
      end

      # The master daemon runs as `falcon serve` on port 53187.
      def master_rss_mb
        out, _, st = Open3.capture3("/bin/ps", "-Ao", "rss,command")
        return nil unless st.success?
        rss_kb = out.lines
                    .select { |l| l.include?("falcon serve") || l.include?(":53187") }
                    .sum { |l| l.strip.split.first.to_i }
        return nil if rss_kb.zero?
        (rss_kb / 1024.0).round
      rescue StandardError
        nil
      end

      # nil = unknown (e.g. rcctl errored); false = explicitly down.
      def master_alive?
        _, _, st = Open3.capture3("/usr/sbin/rcctl", "check", "master")
        st.success?
      rescue StandardError
        nil
      end

      def classify(s)
        return :crit if s[:master_alive] == false ||
                        over?(s[:load_1m], "load_avg_1m", "crit") ||
                        under?(s[:mem_free_pct], "mem_free_pct", "crit") ||
                        over?(s[:disk_root_pct], "disk_root_pct", "crit") ||
                        over?(s[:master_rss_mb], "master_rss_mb", "crit")
        return :warn if over?(s[:load_1m], "load_avg_1m", "warn") ||
                        under?(s[:mem_free_pct], "mem_free_pct", "warn") ||
                        over?(s[:disk_root_pct], "disk_root_pct", "warn") ||
                        over?(s[:master_rss_mb], "master_rss_mb", "warn")
        :ok
      end

      def over?(v, key, level)
        t = @thresholds.dig(key, level)
        v && t && v.to_f >= t.to_f
      end

      def under?(v, key, level)
        t = @thresholds.dig(key, level)
        v && t && v.to_f <= t.to_f
      end

      def load_config
        Master.load_yaml(File.join(@root, "data", "load.yml")) || {}
      rescue StandardError
        {}
      end
    end
  end
end
