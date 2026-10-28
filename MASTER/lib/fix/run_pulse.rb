# frozen_string_literal: true

require "etc"
require "socket"
require_relative "run_ledger"

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
      BUS_PATTERNS = %w[llm:* fix_loop:* repair_loop:* scan:* council:*].freeze
      # No file finished (fixed, failed or rejected) in this long is a stall.
      FINISH_WINDOW_SECONDS = 300
      # A run with this many attempts and nothing fixed after this long has no yield worth waiting for.
      NOYIELD_SECONDS = 1200
      NOYIELD_ATTEMPTS = 5
      ERROR_EVENTS = %w[repair_loop:file_timeout repair_loop:fix_error repair_loop:error repair_loop:fail_fast repair_loop:write_error].freeze
      # The stages that name themselves with a "fix_loop:phase" event, as the log words them.
      PHASES = {
        "fast_fixes" => "fast fixes", "structure" => "structure", "council" => "council", "council_improve" => "council",
        "model_fixes" => "fix", "improvements_fix" => "fix", "opportunities" => "opportunity", "visual" => "visual",
        "wishlist" => "wish", "stream" => "scan + stream fixes"
      }.freeze
      # Stages that make model calls themselves; in any other stage a call in
      # flight is another activity, and the label says so.
      MODEL_STAGES = %w[council model_fixes improvements_fix opportunities visual wishlist stream].freeze
      # Advisory stages: a stall here is cut short (PassClock.cancel!), never waited out.
      SKIPPABLE = %w[council council_improve opportunities wishlist].freeze
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
        @pass_started_at = clock.call
        @stage = nil
        @law = nil
        @council = nil
        @model = nil
        @fixes = { ok: 0, failed: 0 }
        @run_started = clock.call
        @finished = []
        @rejected = 0
        @errored = 0
        @model_ok = 0
        @first_attempt_at = nil
        reset_pass
      end

      def attach(bus)
        Master::Io::LaneSelection.watch_free_class!
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
          parts = ["fix0: pass #{@pass}/#{@max_passes}", @unit, phase_part, files_part, fixes_part, lane_part(elapsed),
                   "tokens = #{tokens} (#{self.class.human_count(tokens)})",
                   "elapsed = #{elapsed.round}s (#{self.class.human_time(elapsed)})", eta,
                   "load #{format("%.1f", @load.call)}"]
          parts.compact.join(" ")
        end
      end

      # Set when the run is stalled: { line:, skippable:, abort: } to print every
      # heartbeat, else nil. Three kinds, most serious first:
      #   no yield   NOYIELD_ATTEMPTS attempts and nothing fixed after NOYIELD_SECONDS
      #              (MASTER_FIX_NOYIELD_S, MASTER_FIX_NOYIELD_ATTEMPTS); the run ends.
      #   none ever  a pass past MASTER_FIX_STALL_S with no file attempted.
      #   none lately  the same pass has attempted files, but none finished in the last
      #              five minutes.
      # Advisory stages are cancelled; every sustained non-advisory stall aborts.
      def stall(now = @clock.call)
        @lock.synchronize do
          no_yield(now) || pass_stall(now)
        end
      end

      # Fixed + failed + rejected, for the machine heartbeat and the exit summary.
      def counts
        @lock.synchronize { { fixed: @fixes[:ok], failed: @errored, rejected: @rejected, attempts: @model_ok + @rejected + @errored } }
      end

      # The one-line heartbeat a script can split on whitespace and `=`.
      def machine_line(elapsed)
        @lock.synchronize do
          "fix0 phase=#{@stage || "start"} fixed=#{@fixes[:ok]} failed=#{@errored} rejected=#{@rejected} lane=#{lane_id} elapsed=#{elapsed.round}"
        end
      end

      # Block closing a pass: violations before and after, fixes, skips, commits.
      def pass_summary(pass, tokens:)
        @lock.synchronize do
          fixed = @pass_fixed
          fixes = "fixes = #{@pass_ok} ok #{@pass_failed} failed #{@skips.sum { |_, n| n }} skipped"
          skipped = @skips.map { |reason, count| "#{reason} #{count}" }.join(", ")
          lines = [
            "fix0: pass #{pass} done, violations = #{@pass_found} before #{[@pass_found - fixed, 0].max} after",
            "fix0: pass #{pass} #{fixes}#{skipped.empty? ? "" : " (#{skipped})"}",
            "fix0: pass #{pass} commits = #{[@commits.call - @commits_at_start, 0].max} tokens = #{tokens} (#{self.class.human_count(tokens)})",
          ]
          lines.insert(2, listed_line(pass)) if @listed.any?
          lines
        end
      end

      private

      # One model attempt reached an end: stamped for the finish window, and the
      # first one starts the no-yield clock.
      def attempted
        yield
        @first_attempt_at ||= @clock.call
        @finished << @clock.call
        @finished.shift while @finished.size > 500
      end

      def no_yield(now)
        attempts = @model_ok + @rejected + @errored
        minimum = Integer(ENV.fetch("MASTER_FIX_NOYIELD_ATTEMPTS", NOYIELD_ATTEMPTS.to_s), exception: false) || NOYIELD_ATTEMPTS
        limit = Integer(ENV.fetch("MASTER_FIX_NOYIELD_S", NOYIELD_SECONDS.to_s), exception: false) || NOYIELD_SECONDS
        return unless @model_ok.zero? && attempts >= minimum && @first_attempt_at && now - @first_attempt_at >= limit

        { line: "fix0: STALLED no yield: 0 fixed after #{((now - @first_attempt_at) / 60).floor}m, #{attempts} attempts",
          skippable: false, abort: true }
      end

      def pass_stall(now)
        seconds = FixTime.stall_s
        waited = now - @pass_started_at
        return unless @pass.positive? && waited > seconds

        pass_attempts = @pass_ok + @pass_failed + @pass_rejected + @pass_errored
        # The semantic scan reads one file at a time at a minute or so each, and a clean
        # file queues no repair: a scan that keeps finishing files is working, not stalled.
        # That holds after the pass's first repairs too: the pass's budgeted semantic reads
        # run after them, and Opus reading two files was cut as "0 files finished in 5m".
        # A repair that hangs is the file budget's to end.
        return if scan_advancing?(now)

        window = finish_window
        recent = @finished.count { |at| now - at <= window }
        tail = if pass_attempts.zero? then "0 files attempted"
               elsif recent.zero? then "0 files finished in #{window / 60}m"
               end
        return unless tail

        skippable = SKIPPABLE.include?(@stage)
        {
          line: "fix0: STALLED pass #{@pass} phase #{phase_name} for #{(waited / 60).floor}m, #{tail}",
          skippable: skippable,
          # A non-advisory pass that has made no progress cannot recover by
          # waiting indefinitely for the same provider call. End it here;
          # wrapper-only watchdogs do not cover direct CLI invocations.
          abort: !skippable
        }
      end

      def scan_advancing?(now)
        !@scan_completed_at.nil? && now - @scan_completed_at <= finish_window
      end

      # One file may spend its whole budget before it finishes, so the window is never shorter
      # than that budget and a minute: at Opus's 900 s a file, five minutes cut working repairs.
      def finish_window = [FINISH_WINDOW_SECONDS, RunLedger.file_budget_s + 60].max

      def lane_id
        model, = @calls.values.min_by { |_, at| at }
        (model || @model).to_s.then { |id| id.empty? ? "none" : id }
      end

      # Findings whose repair is the operator's call: listed, never attempted.
      def listed_line(pass)
        "fix0: pass #{pass} listed for the operator, not attempted = #{@listed.sum { |_, n| n }} (#{@listed.map { |law, n| "#{law} #{n}" }.join(", ")})"
      end

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
        when "fix_loop:terminal", "fix_loop:crash" then end_tree
        when "fix_loop:phase" then enter_phase(payload)
        when "council:progress" then @council = [payload[:answered].to_i, payload[:total].to_i]
        when "scan:progress" then scanned(payload)
        when "scan:complete" then @scan_completed_at = @clock.call
        when "fix_loop:rule_result", "repair_loop:pass" then ruled(payload)
        when "fix_loop:skip_breakdown" then skipped(payload)
        when "repair_loop:fix_applied" then attempted { count_fix(:ok); @model_ok += 1 }
        when "fix_loop:ast_fixed" then count_fix(:ok)
        when "repair_loop:fix_rejected" then count_fix(:failed)
        when "repair_loop:proposal_rejected" then attempted { @rejected += 1; @pass_rejected += 1 }
        when *ERROR_EVENTS then attempted { @errored += 1; @pass_errored += 1 }
        when "repair_loop:operator_gap" then @listed[payload[:law].to_s] += 1
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
        @pass_started_at = @clock.call
        @stage = "scan"
        @council = nil
        @file_total = payload[:file_count].to_i
        @commits_at_start = @commits.call
      end

      # One pulse spans every tree of a multi-tree /fix. A tree that ended, crashed or not,
      # leaves no pass to stall and no call to wait on; the next tree's pass_start begins anew.
      def end_tree
        @pass = 0
        @stage = nil
        @calls.clear
        reset_pass
        @pass_started_at = @clock.call
      end

      def reset_pass
        @file_total = 0
        @file_done = 0
        @file = nil
        @pass_found = 0
        @pass_fixed = 0
        @pass_ok = 0
        @pass_failed = 0
        @pass_rejected = 0
        @pass_errored = 0
        @skips = Hash.new(0)
        @listed = Hash.new(0)
        @commits_at_start = 0
        @scan_completed_at = nil
      end

      def scanned(payload)
        @file_done = payload[:done].to_i
        @file_total = payload[:total].to_i if payload[:total]
        @file = payload[:path].to_s
      end

      def enter_phase(payload)
        @stage = payload[:stage].to_s
        @council = nil if @stage.start_with?("council")
      end

      def phase_name
        return "council (#{@council[0]} of #{@council[1]} personas answered)" if @stage.to_s.start_with?("council") && @council

        name = PHASES.fetch(@stage.to_s, @stage.to_s)
        name == "fix" && @law ? "fix #{@law}#{@file ? " #{File.basename(@file)}" : ""}" : name
      end

      def phase_part = (@stage ? "phase #{phase_name}#{in_flight_note}" : nil)

      # The heartbeat names every activity in flight: a model call under a stage
      # that makes none is said aloud, never hidden behind the stage.
      def in_flight_note
        return if @calls.empty? || MODEL_STAGES.any? { |stage| @stage.to_s.start_with?(stage) }

        " + #{@calls.size} model #{@calls.size == 1 ? "call" : "calls"}"
      end

      def ruled(payload)
        @law = payload[:law].to_s unless payload[:law].to_s.empty?
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
            model_line(probes[:choice] || boot_choice),
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

        # The lane /fix starts on and what chose it, so a run on a free model
        # shows its cause on the first screen.
        def model_line(choice)
          lane, source = choice
          return "model0 at fix0: no live lane (source: #{source || "availability"})" if lane.to_s.empty?

          "model0 at fix0: #{lane} (source: #{source == "MASTER_MODEL" ? Master::Io::LaneSelection.pin_label : source})"
        end

        def boot_choice
          Master::Io::LaneSelection.boot_choice(saved: saved_model)
        rescue StandardError
          []
        end

        # The model the operator saved in config.yml, not the built-in default.
        def saved_model
          saved = Master::Ground::Config.new(Master::ROOT)["model"].to_s
          saved == Master::Ground::Config::DEFAULTS["model"] ? nil : saved
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
          refuses = ->(model) { !Master::Io::LaneState.usable?(model, sources: Master::Io::LaneState::DOWN) }
          health.states(Master::Io::LaneSelection.order(Master::Io::LaneSelection.catalogue), refuses:)
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
