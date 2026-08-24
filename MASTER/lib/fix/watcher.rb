# frozen_string_literal: true

require "open3"
require "time"

module Master
  module Fix
    # Watcher — continuous OpenBSD load monitor.
    # Polls load avg, memory, disk, master service. Publishes system:sample
    # every interval, system:warn/crit on threshold crossings.
    class Watcher
      DEFAULT_INTERVAL = 30
      @last_sample = nil

      class << self
        attr_accessor :last_sample
      end

      # One-shot sample without a running watcher. Used by /status.
      def self.sample_once(root: Master::ROOT)
        new(bus: nil, root:).sample!
      end

      def initialize(bus:, root:, interval: nil)
        @bus = bus
        @root = root
        cfg = load_config
        @interval = interval || cfg["interval_seconds"] || DEFAULT_INTERVAL
        @thresholds = cfg["thresholds"] || {}
        @prev_level = :ok
      end

      def run_forever
        return unless ENV["MASTER_WATCHER"] == "1"

        loop do
          sample!
          sleep @interval
        end
      rescue StandardError => e
        @bus&.publish("watcher:error", error: e.message)
      end

      def sample!
        s     = build_sample
        self.class.last_sample = s
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
          mem_free_pct:,
          disk_root_pct:,
          master_rss_mb:,
          master_alive: master_alive?,
        }
      end

      def load_avg_1m
        out, _, st = Master::Io::Exec.capture3("/sbin/sysctl", "-n", "vm.loadavg")
        return unless st.success?

        load_average_1m(out)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Watcher.load_avg_1m")
        nil
      end

      # OpenBSD does not expose vm.uvmexp.free via sysctl — parse vmstat instead.
      def mem_free_pct
        out, _, st = Master::Io::Exec.capture3("/usr/bin/vmstat")
        return unless st.success?

        free = vmstat_free_bytes(out)
        return unless free

        total, _, st2 = Master::Io::Exec.capture3("/sbin/sysctl", "-n", "hw.physmem")
        return unless st2.success?

        memory_free_percent(free, physmem_bytes(total))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Watcher.mem_free_pct")
        nil
      end

      def load_average_1m(output)
        output.to_s[/\d+(?:\.\d+)?/]&.to_f
      end

      def vmstat_free_bytes(output)
        lines = output.to_s.lines.map(&:strip).reject(&:empty?)
        header_index = lines.index { |line| line.split.include?("fre") }
        columns = header_index ? lines[header_index].split : []
        free_index = columns.index("fre") || 4
        data = lines.drop((header_index || -1) + 1).find { |line| line.match?(/\A\s*\d/) } ||
               lines.reverse.find { |line| line.match?(/\A\s*\d/) }
        return unless data

        value = data.split[free_index]
        value ? parse_size(value) : nil
      end

      def physmem_bytes(output)
        bytes = output.to_s[/\d+(?:\.\d+)?/]&.to_f
        bytes&.positive? ? bytes : nil
      end

      def memory_free_percent(free_bytes, total_bytes)
        return unless free_bytes && total_bytes&.positive?

        pct = (free_bytes.to_f / total_bytes.to_f * 100.0).round(1)
        [[pct, 0.0].max, 100.0].min
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
        out, _, st = Master::Io::Exec.capture3("/bin/df", "-k", "/")
        return unless st.success?

        disk_percent(out)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Watcher.disk_root_pct")
        nil
      end

      def disk_percent(output)
        line = output.to_s.lines.drop(1).find { |entry| entry.include?("%") }
        line&.split&.find { |part| part.end_with?("%") }&.delete("%")&.to_f
      end

      # The master daemon runs as `falcon serve` on port 53187.
      def master_rss_mb
        out, _, st = Master::Io::Exec.capture3("/bin/ps", "-Ao", "rss,command")
        return unless st.success?

        master_rss_mb_from_ps(out)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Watcher.master_rss_mb")
        nil
      end

      def master_rss_mb_from_ps(output)
        rss_kb = output.to_s.lines
                       .select { |line| line.include?("falcon serve") || line.include?(":53187") }
                       .sum { |line| line.strip.split.first.to_i }
        return if rss_kb.zero?

        (rss_kb / 1024.0).round(1)
      end

      # nil = unknown (e.g. rcctl errored); false = explicitly down.
      def master_alive?
        _, _, st = Master::Io::Exec.capture3("/usr/sbin/rcctl", "check", "master")
        st.success?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Watcher.master_alive?")
        nil
      end

      def classify(s)
        return :crit if s[:master_alive] == false ||
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
        t = (@thresholds || {}).dig(key, level)
        v && t && v.to_f >= t.to_f
      end

      def under?(v, key, level)
        t = (@thresholds || {}).dig(key, level)
        v && t && v.to_f <= t.to_f
      end

      def load_config
        Master.load_yaml(File.join(@root, "data", "load.yml")) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Watcher.load_config")
        {}
      end
    end
  end
end
