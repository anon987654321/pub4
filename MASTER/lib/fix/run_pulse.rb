# frozen_string_literal: true

require "etc"
require "socket"

module Master
  module Fix
    # What /fix is doing right now, as one dmesg line: pass, stage, file, fixes,
    # the lane a model call is waiting on, tokens, elapsed and load. RunBudget
    # asks for it on a timer so a run is never quiet; the bus feeds it.
    # Raw-then-human pairs, "tokens = 342191 (342K)", the way dmesg prints
    # "real mem = 17047633920 (16256MB)".
    class RunPulse
      WAITING_AFTER = 5
      FILE_CHARS = 24
      BUS_PATTERNS = %w[llm:* fix_loop:* law_loop:* scan:*].freeze
      NOT_SKIPS = %w[pass fixed clean applied ok].freeze

      def self.human_count(count)
        return count.to_s if count < 1000
        return "#{(count / 1000.0).round}K" if count < 1_000_000

        format("%.1fM", count / 1_000_000.0)
      end

      def self.human_time(seconds)
        hours, rest = seconds.to_i.divmod(3600)
        minutes, secs = rest.divmod(60)
        return "#{hours}h#{format("%02d", minutes)}m" if hours.positive?
        return "#{minutes}m#{format("%02d", secs)}s" if minutes.positive?

        "#{secs}s"
      end

      def initialize(max_passes:, clock:, load: method(:load_average), commits: -> { 0 })
        @max_passes = max_passes.to_i
        @clock = clock
        @load = load
        @commits = commits
        @lock = Mutex.new
        @calls = {}
        @pass = 0
        @unit = "fix0"
        @last_call_end = nil
        @model = nil
        @fixes = { ok: 0, failed: 0 }
        reset_pass
      end

      def attach(bus)
        BUS_PATTERNS.each { |pattern| bus.subscribe(pattern) { |payload| observe(payload[:event], payload) } }
      end

      def unit=(name)
        @lock.synchronize { @unit = name.to_s }
      end

      def observe(event, payload)
        @lock.synchronize { apply(event.to_s, payload) }
      end

      # The line itself. `eta` and `tokens` come from RunBudget, which owns the ledger.
      def line(elapsed:, tokens:, eta:)
        @lock.synchronize do
          parts = ["fix0: pass #{@pass}/#{@max_passes}", @unit, files_part, fixes_part, lane_part(elapsed),
                   "tokens = #{tokens} (#{self.class.human_count(tokens)})",
                   "elapsed = #{elapsed.round}s (#{self.class.human_time(elapsed)})", eta,
                   "load #{format("%.1f", @load.call)}"]
          parts.compact.join(" ")
        end
      end

      # Block closing a pass: violations before and after, fixes, skips, commits.
      def pass_summary(pass, tokens:)
        @lock.synchronize do
          fixed = @pass_fixed
          fixes = "fixes = #{@pass_ok} ok #{@pass_failed} failed #{@skips.sum { |_, n| n }} skipped"
          skipped = @skips.map { |reason, count| "#{reason} #{count}" }.join(", ")
          [
            "fix0: pass #{pass} done, violations = #{@pass_found} before #{[@pass_found - fixed, 0].max} after",
            "fix0: pass #{pass} #{fixes}#{skipped.empty? ? "" : " (#{skipped})"}",
            "fix0: pass #{pass} commits = #{[@commits.call - @commits_at_start, 0].max} tokens = #{tokens} (#{self.class.human_count(tokens)})",
          ]
        end
      end

      private

      # One-minute load: /proc where it exists, vm.loadavg on the BSDs and macOS.
      def load_average
        return File.read("/proc/loadavg").to_f if File.readable?("/proc/loadavg")

        out, status = Master::Io::Exec.capture2e("sysctl", "-n", "vm.loadavg")
        status.success? ? out[/\d+\.\d+/].to_f : 0.0
      rescue StandardError
        0.0
      end

      def apply(event, payload)
        case event
        when "llm:send" then @calls[Thread.current.object_id] = [payload[:model].to_s, @clock.call]
        when "llm:provider_outcome" then finish_call(payload)
        when "fix_loop:pass_start" then start_pass(payload)
        when "scan:progress" then scanned(payload)
        when "fix_loop:rule_result", "law_loop:pass" then ruled(payload)
        when "fix_loop:skip_breakdown" then skipped(payload)
        when "law_loop:fix_applied", "fix_loop:ast_fixed" then count_fix(:ok)
        when "law_loop:fix_rejected" then count_fix(:failed)
        end
      end

      def finish_call(payload)
        @calls.delete(Thread.current.object_id)
        @model = payload[:model].to_s
        @last_call_end = @clock.call
      end

      def start_pass(payload)
        @pass = payload[:pass].to_i
        reset_pass
        @file_total = payload[:file_count].to_i
        @commits_at_start = @commits.call
      end

      def reset_pass
        @file_total = 0
        @file_done = 0
        @file = nil
        @pass_found = 0
        @pass_fixed = 0
        @pass_ok = 0
        @pass_failed = 0
        @skips = Hash.new(0)
        @commits_at_start = 0
      end

      def scanned(payload)
        @file_done = payload[:done].to_i
        @file_total = payload[:total].to_i if payload[:total]
        @file = payload[:path].to_s
      end

      def ruled(payload)
        @pass_found += payload[:violations].to_i
        @pass_fixed += payload[:fixed].to_i
      end

      def skipped(payload)
        payload.except(:event, :ts).each do |reason, count|
          @skips[reason.to_s] += count if count.is_a?(Integer) && !NOT_SKIPS.include?(reason.to_s)
        end
      end

      def count_fix(kind)
        @fixes[kind] += 1
        kind == :ok ? @pass_ok += 1 : @pass_failed += 1
      end

      def files_part
        return if @file_total.zero?

        share = @file_total.positive? ? (100.0 * @file_done / @file_total).round : 0
        base = @file && File.basename(@file)
                name = base ? " #{base.length > FILE_CHARS ? "…#{base[-(FILE_CHARS - 1)..]}" : base}" : ""
        "files #{@file_done}/#{@file_total} (#{share}%)#{name}"
      end

      def fixes_part = "fixes #{@fixes[:ok]} ok #{@fixes[:failed]} failed"

      # Blocked on a model: name the lane and the wait. Otherwise the lane that
      # answered last, and how long ago.
      def lane_part(_elapsed)
        model, started = @calls.values.min_by { |_, at| at }
        now = @clock.call
        return "waiting on #{model} for #{(now - started).round}s" if model && now - started >= WAITING_AFTER
        return "lane #{model} in call" if model
        return unless @model

        "lane #{@model} last call #{(now - @last_call_end).round}s ago"
      end

      # The lines /fix prints when it starts, in the order an OpenBSD boot prints
      # them: version, an indented host line, real mem as bytes then megabytes,
      # then one attach line per device. A device that cannot work says
      # "not configured" and why, so silence never means absent.
      module Banner
        TRIANGLE = { "amber" => 61_352, "bsdports" => 47_312 }.freeze
        PROBE_TIMEOUT = 0.3
        BYTES_PER_MB = 1_048_576

        module_function

        def lines(root:, target:, max_passes:, limits:, now: Time.now, probes: {})
          [
            "MASTER #{Master::VERSION} (FIX) ##{probes[:sha] || head_sha(root)}: #{stamp(now)}",
            "    #{ENV.fetch("USER", "master")}@#{Socket.gethostname}:#{root}",
            mem_line(probes[:mem] || physical_bytes),
            "ncpu = #{Etc.nprocessors}",
            "fix0 at mainbus0: target #{target}, passes #{max_passes}, #{limits}",
            *lane_lines(probes[:states] || lane_states),
            *triangle_lines(target, probes[:ports] || probe_ports),
          ]
        end

        def stamp(now) = now.strftime("%a %b %e %H:%M:%S %Z %Y").squeeze(" ")

        def mem_line(bytes)
          return "real mem = unknown" unless bytes&.positive?

          "real mem = #{bytes} (#{bytes / BYTES_PER_MB}MB)"
        end

        # "claude-cli: live" attaches; any other state is a lane that is not configured.
        def lane_lines(states)
          index = -1
          states.map do |state|
            lane, detail = state.split(": ", 2)
            next "#{lane} at fix0: not configured, #{detail}" unless detail == "live"

            "lane#{index += 1} at fix0: #{lane}"
          end
        end

        def triangle_lines(target, ports)
          return [] unless target.to_s.include?("RAILS")

          TRIANGLE.filter_map do |app, port|
            "#{app}0 at triangle0: not configured, port #{port} not answering" unless ports.fetch(app, false)
          end
        end

        def probe_ports
          TRIANGLE.to_h { |app, port| [app, answering?(port)] }
        end

        def answering?(port)
          Socket.tcp("127.0.0.1", port, connect_timeout: PROBE_TIMEOUT, &:close)
          true
        rescue SystemCallError, Socket::ResolutionError, IOError
          false
        end

        def lane_states
          health = Master::Io::LaneHealth
          health.states(health.role_models)
        rescue StandardError
          []
        end

        def physical_bytes
          return proc_meminfo_bytes if File.readable?("/proc/meminfo")

          key = RUBY_PLATFORM.include?("openbsd") ? "hw.physmem" : "hw.memsize"
          out, status = Master::Io::Exec.capture2e("sysctl", "-n", key)
          status.success? ? out.to_i : nil
        rescue StandardError
          nil
        end

        def proc_meminfo_bytes
          File.foreach("/proc/meminfo").grep(/\AMemTotal:/).first.to_s[/\d+/].to_i * 1024
        end

        def head_sha(root)
          out, status = Master::Io::Exec.capture2e("git", "-C", root, "rev-parse", "--short", "HEAD")
          status.success? ? out.strip : "unknown"
        rescue StandardError
          "unknown"
        end
      end
    end
  end
end
