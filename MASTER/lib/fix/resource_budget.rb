# frozen_string_literal: true

require "open3"
require "socket"

module Master
  module Fix
    # Measures cheap host/process signals before expensive optional work.
    # Critical pressure sheds model work; deterministic scans and file fixes can
    # still finish and report truthfully.
    class ResourceBudget
      DEFAULTS = {
        fd_count: { warn: 512, crit: 1024 },
        thread_count: { warn: 32, crit: 64 },
        process_count: { warn: 256, crit: 512 },
        disk_free_pct: { warn: 15, crit: 5 },
      }.freeze
 attr_reader :root

      def initialize(root:, config: nil, clock: Process::CLOCK_MONOTONIC)
        @root = root
        @config = config || Master::Ops::ProcessBudget.config
        @clock = clock
      end

      def measure
        values = {
          load_avg_1m: load_average,
          rss_mb: rss_mb,
          fd_count: fd_count,
          thread_count: Thread.list.size,
          process_count: process_count,
          disk_free_pct: disk_free_pct,
          network: network_available,
          llm_quota_exhausted: llm_quota_exhausted,
        }
        classify(values).merge(measured_at: Process.clock_gettime(@clock), values:)
      rescue StandardError => e
        { state: :degraded, reasons: ["resource measurement failed: #{e.message}"], values: {} }
      end

      def critical?(measurement) = measurement[:state] == :critical
      def warning?(measurement) = measurement[:state] == :warning

      private

      def classify(values)
        reasons = []
        state = :ok
        checks = [
          [:load_avg_1m, limit("load_avg_1m", "warn", DEFAULTS[:load_avg_warn]),
           limit("load_avg_1m", "crit", DEFAULTS[:load_avg_crit])],
          [:rss_mb, limit("master_rss_mb", "warn", DEFAULTS[:rss_mb_warn]),
           limit("master_rss_mb", "crit", DEFAULTS[:rss_mb_crit])],
          [:fd_count, resource_limit("fd_count", "warn"), resource_limit("fd_count", "crit")],
          [:thread_count, resource_limit("thread_count", "warn"), resource_limit("thread_count", "crit")],
          [:process_count, resource_limit("process_count", "warn"), resource_limit("process_count", "crit")],
        ]
        checks.each do |name, warn_at, crit_at|
          value = values[name]
          next unless value

          if value >= crit_at
            state = :critical
            reasons << "#{name}=#{value} >= #{crit_at}"
          elsif value >= warn_at && state == :ok
            state = :warning
            reasons << "#{name}=#{value} >= #{warn_at}"
          end
        end

        disk = values[:disk_free_pct]
        if disk && disk <= resource_limit("disk_free_pct", "crit")
          state = :critical
          reasons << "disk_free_pct=#{disk} <= #{resource_limit("disk_free_pct", "crit")}"
        elsif disk && disk <= resource_limit("disk_free_pct", "warn") && state == :ok
          state = :warning
          reasons << "disk_free_pct=#{disk} <= #{resource_limit("disk_free_pct", "warn")}"
        end

        if values[:network] == false && state == :ok
          state = :warning
          reasons << "network=offline"
        end

        exhausted = values[:llm_quota_exhausted].to_i
        if exhausted.positive? && state == :ok
          state = :warning
          reasons << "llm_quota_exhausted=#{exhausted}"
        end
        { state:, reasons: }
      end

      def resource_limit(name, level)
        configured = @config.dig("resources", name, level).to_f
        return configured if configured.positive?

        DEFAULTS.fetch(name).fetch(level)
      end

      def limit(section, key, fallback)
        @config.dig("load", section, key).to_f.then { |value| value.positive? ? value : fallback }
      end

      def load_average
        command = if File.executable?("/sbin/sysctl")
          ["/sbin/sysctl", "-n", "vm.loadavg"]
        else
          nil
        end
        if command
          out, status = Open3.capture2e(*command)
          return out.to_s[/\d+(?:\.\d+)?/]&.to_f if status.success?
        end
        return File.read("/proc/loadavg").to_f if File.file?("/proc/loadavg")

        nil
      rescue StandardError
        nil
      end

      def rss_mb
        if File.file?("/proc/self/status")
          kb = File.read("/proc/self/status")[/^VmRSS:\s+(\d+) kB$/, 1]
          return kb.to_i / 1024.0 if kb
        end
        out, status = Open3.capture2e("ps", "-o", "rss=", "-p", Process.pid.to_s)
        status.success? ? out.to_i / 1024.0 : nil
      rescue StandardError
        nil
      end

      def fd_count
        fd_dir = "/proc/self/fd"
        return Dir.children(fd_dir).size if Dir.exist?(fd_dir)

        fd_dir = "/dev/fd"
        return Dir.children(fd_dir).size if Dir.exist?(fd_dir)

        nil
      rescue StandardError
        nil
      end

      def process_count
        out, status = Open3.capture2e("ps", "-axo", "pid=")
        status.success? ? out.lines.size : nil
      rescue StandardError
        nil
      end

      def network_available
        Socket.tcp("1.1.1.1", 53, connect_timeout: 0.5) { true }
      rescue StandardError
        false
      end

      def llm_quota_exhausted
        return 0 unless defined?(Master::Io::ModelQuota)

        Master::Io::ModelQuota.exhausted_models.size
      rescue StandardError
        nil
      end

      def disk_free_pct
        out, status = Open3.capture2e("df", "-kP", @root)
        return unless status.success?

        row = out.lines.last.to_s.split
        used = row[4].to_s.delete_suffix("%").to_f
        used.positive? ? (100.0 - used).round(1) : nil
      rescue StandardError
        nil
      end
    end
  end
end
