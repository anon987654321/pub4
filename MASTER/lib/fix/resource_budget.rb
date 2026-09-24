# frozen_string_literal: true

require "etc"
require "open3"
require_relative "../ground/boot_receipt"

module Master
  module Fix
    # Measures cheap host/process signals before expensive optional work.
    # Critical pressure sheds model work; deterministic scans and file fixes can
    # still finish and report truthfully.
    class ResourceBudget
      DEFAULTS = {
        load_avg_1m: { warn: 1.5, crit: 2.5 },
        master_rss_mb: { warn: 512, crit: 768 },
        fd_count: { warn: 512, crit: 1024 },
        thread_count: { warn: 32, crit: 64 },
        process_count: { warn: 256, crit: 512 },
        disk_free_pct: { warn: 15, crit: 5 },
      }.freeze

      attr_reader :root
      MEASURE_TTL_S = 2

      def initialize(root:, config: nil, clock: Process::CLOCK_MONOTONIC, cpus: Etc.nprocessors, platform: RUBY_PLATFORM)
        @root = root
        @config = config || Master::Ops::ProcessBudget.config
        @clock = clock
        @cpus = [cpus.to_i, 1].max
        @platform = platform.to_s[/darwin|openbsd|linux/]
        @last_measurement_at = nil
        @last_measurement = nil
      end

      def measure
        now = Process.clock_gettime(@clock)
        return @last_measurement if @last_measurement && @last_measurement_at &&
          now - @last_measurement_at < MEASURE_TTL_S

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
        @last_measurement = classify(values).merge(measured_at: now, values:)
        @last_measurement_at = now
        @last_measurement
      rescue StandardError => e
        { state: :critical, reasons: ["resource measurement failed: #{e.message}"], values: {} }
      end

      def critical?(measurement) = measurement[:state] == :critical
      def warning?(measurement) = measurement[:state] == :warning

      private

      # state only ever escalates within one classify call (:ok -> :warning ->
      # :critical), never downgrades -- each helper below takes the
      # accumulated [state, reasons] and returns the same or an escalated
      # pair, in the exact same check order the single method used to run
      # inline, so a later warn-level check can never undo an earlier
      # critical the way `state == :ok` guards already prevented.
      def classify(values)
        state, reasons = classify_resource_checks(values)
        state, reasons = classify_disk(values, state, reasons)
        classify_network_and_quota(values, state, reasons)
      end

      def resource_checks_table
        [
          # Load average counts runnable work across every CPU, so the limits
          # are per CPU: vm23's one vCPU reads them as written.
          [:load_avg_1m, limit("load_avg_1m", "warn", DEFAULTS[:load_avg_1m][:warn]) * @cpus,
           limit("load_avg_1m", "crit", DEFAULTS[:load_avg_1m][:crit]) * @cpus],
          [:rss_mb, limit("master_rss_mb", "warn", DEFAULTS[:master_rss_mb][:warn]),
           limit("master_rss_mb", "crit", DEFAULTS[:master_rss_mb][:crit])],
          [:fd_count, resource_limit("fd_count", "warn"), resource_limit("fd_count", "crit")],
          [:thread_count, resource_limit("thread_count", "warn"), resource_limit("thread_count", "crit")],
          [:process_count, resource_limit("process_count", "warn"), resource_limit("process_count", "crit")],
        ]
      end

      def classify_resource_checks(values)
        reasons = []
        state = :ok
        resource_checks_table.each do |name, warn_at, crit_at|
          value = values[name]
          next unless value

          state, note = classify_one_check(state, name, value, warn_at, crit_at)
          reasons << note if note
        end
        [state, reasons]
      end

      def classify_one_check(state, name, value, warn_at, crit_at)
        if value >= crit_at
          [:critical, "#{name}=#{value} >= #{crit_at}"]
        elsif value >= warn_at && state == :ok
          [:warning, "#{name}=#{value} >= #{warn_at}"]
        else
          [state, nil]
        end
      end

      def classify_disk(values, state, reasons)
        disk = values[:disk_free_pct]
        if disk && disk <= resource_limit("disk_free_pct", "crit")
          state = :critical
          reasons += ["disk_free_pct=#{disk} <= #{resource_limit("disk_free_pct", "crit")}"]
        elsif disk && disk <= resource_limit("disk_free_pct", "warn") && state == :ok
          state = :warning
          reasons += ["disk_free_pct=#{disk} <= #{resource_limit("disk_free_pct", "warn")}"]
        end
        [state, reasons]
      end

      def classify_network_and_quota(values, state, reasons)
        if values[:network] == false && state == :ok
          state = :warning
          reasons += ["network=offline"]
        end

        exhausted = values[:llm_quota_exhausted].to_i
        if exhausted.positive? && state == :ok
          state = :warning
          reasons += ["llm_quota_exhausted=#{exhausted}"]
        end
        { state:, reasons: }
      end

      def resource_limit(name, level)
        platform = @platform && @config.dig("resources", name, @platform, level).to_f
        return platform if platform&.positive?

        configured = @config.dig("resources", name, level).to_f
        return configured if configured.positive?

        DEFAULTS.fetch(name.to_sym).fetch(level.to_sym)
      end

      def limit(section, key, fallback)
        @config.dig("load", section, key).to_f.then { |value| value.positive? ? value : fallback }
      end

      def load_average
        # OpenBSD keeps sysctl in /sbin, macOS in /usr/sbin.
        sysctl = ["/sbin/sysctl", "/usr/sbin/sysctl"].find { |path| File.executable?(path) }
        if sysctl
          out, status = Open3.capture2e(sysctl, "-n", "vm.loadavg")
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
        Master::Ground::BootReceipt.network?
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
