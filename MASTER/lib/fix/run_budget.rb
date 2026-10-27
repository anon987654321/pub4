# frozen_string_literal: true

require "json"
require "open3"
require_relative "run_pulse"
require_relative "autofix_guard"
require_relative "run_ledger"
require_relative "refusals"
require_relative "tool_breaker"
require_relative "resource_budget"
require_relative "../review/llm_dispatcher/pass_clock"

module Master
  module Fix
    # What one /fix run has spent: model dollars and tokens (read from the
    # costs ledger the session writes), wall time per dmesg unit, and an ETA
    # from the passes already finished. It speaks at every pass boundary, prints
    # a RunPulse line every HEARTBEAT_SECONDS so the run is never quiet, and it stops the run, loudly, past either limit.
    # ResourceBudget measures the host; this measures the run.
    class RunBudget
      DEFAULT_MAX_COST = 50.0
      DEFAULT_MAX_MINUTES = 480.0
      HEARTBEAT_SECONDS = 28
      MACHINE_BEAT_SECONDS = 60
      GUARD_CHECK_SECONDS = 300
      RESOURCE_CHECK_SECONDS = 30
      WARN_SHARE = 0.8
      UNIT = "budget0"
      DEFAULT_LAW_SHARE = 0.10 # data/limits.yml#fix_budget overrides both
      DEFAULT_RUN_TOKENS = 10_000_000
      COSTS = File.join(".master", "costs.jsonl")
      # A stalled run is asked to stop and prove what it did; it is killed only if it has not
      # wound down after this many seconds (MASTER_FIX_STOP_GRACE_S; 0 kills at once).
      STOP_GRACE_SECONDS = 300
      # How long an abort waits on the committer to roll back the open pass before its TERM.
      ROLLBACK_WAIT_SECONDS = 30

      class << self
        attr_reader :current

        def begin_run(root:, max_passes:, bus: nil, target: nil)
          # Nested tree passes and check re-entries belong to the command's one
          # budget. Do not restart its clock, watchdog, lane failures, or ledger.
          return @current if (@shared_depth || 0).to_i.positive? && @current

          finish_run
          ToolBreaker.reset!
          RunLedger.begin_run!
          Refusals.begin_run!
          Master::Review::LLMDispatcher::PassClock.cap_calls!(call_cap_s)
          @current = new(root:, max_passes:).start!.tap { |run| run.announce(target:, bus:) }
        end

        # Every model call of a run ends inside a file's repair budget, and that budget inside the
        # stall window: a call that outlived both ended a whole tree while the pass waited on it.
        def call_cap_s = [RunLedger.file_budget_s, RunPulse::FINISH_WINDOW_SECONDS * 4 / 5].min

        def with_shared_run(root:, max_passes:, bus: nil, target: nil)
          outer = (@shared_depth || 0).to_i.zero?
          begin_run(root:, max_passes:, bus:, target:) if outer
          @shared_depth = (@shared_depth || 0).to_i + 1
          # A startup disk/protected-path abort is already a terminal safety
          # decision. Do not run trace, research, checks, or model work afterwards.
          result = if @current&.stopping
                     Master::Result.err(@current.stopping, category: @current.stop_category)
                   else
                     yield
                   end
          result
        ensure
          if outer
            @shared_depth = 0
            @shared_finishing = true
            begin
              finish_run(reason: "command scope ended")
            ensure
              @shared_finishing = false
            end
          else
            @shared_depth = [(@shared_depth || 0).to_i - 1, 0].max
          end
        end

        def pass_end(pass)
          @current&.pass_end(pass)
        end

        # Why the run is winding down after a stall, or nil.
        def stopping = @current&.stopping

        # A Result.err naming the exhausted limit, or nil while the run may go on.
        def pass_boundary(pass)
          reason = @current&.stopping || @current&.boundary(pass)
          reason && Master::Result.err(reason, category: @current&.stopping ? @current.stop_category : :timeout)
        end

        def finish_run(reason: "completed")
          return @current if (@shared_depth || 0).to_i.positive? && !@shared_finishing

          run = @current
          begin
            run&.finish!(reason)
          ensure
            # Reporting is part of finalization and can itself fail (for
            # example, a full log filesystem). Never leave a dead budget as
            # the current run after its watchdog has been stopped.
            @current = nil if @current.equal?(run)
            Master::Review::LLMDispatcher::PassClock.cap_calls!(nil) unless @current
          end
        end

        def note_output(unit, text)
          @current&.note_output(unit, text)
        end

        def run_spend = @current&.spend || [0.0, 0]

        # Monotonic elapsed time for the one active run, including preflight. The pass deadline
        # takes off what elapsed after its journal opened (FixLoop#repair_seconds_left).
        def elapsed_seconds = @current&.elapsed_seconds || 0.0

        def note_law_cost(law_id, usd, tokens = 0) = @current&.note_law_cost(law_id, usd, tokens)

        def law_limit_exceeded?(law_id) = @current&.law_limit_exceeded?(law_id) || false

        # The committer whose pass transaction an abort rolls back before its TERM. One fix loop, one
        # committer; a committer with no open transaction makes the rollback a no-op.
        def pass_owner = @pass_owner

        def hold_pass(committer)
          @pass_owner = committer
          nil
        end
      end

      def initialize(root:, max_passes:, env: ENV, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     wall: -> { Time.now }, out: nil, say: nil, beat_seconds: HEARTBEAT_SECONDS, poll_seconds: 1,
                     limits: nil, killer: nil, resource_budget: nil)
        @root = root
        @costs = File.join(root, COSTS)
        @max_passes = max_passes.to_i
        @max_cost = limit(env["MASTER_FIX_MAX_COST"], DEFAULT_MAX_COST)
        @max_minutes = limit(env["MASTER_FIX_MAX_MINUTES"], DEFAULT_MAX_MINUTES)
        @clock = clock
        @wall = wall
        @out = out || ->(line) { Master::Trace::Dmesg.status(UNIT, line) }
        @say = say || ->(text) { Master::Trace::Dmesg.emit(text) }
        @beat_every = beat_seconds
        @pulse = RunPulse.new(max_passes:, clock:, commits: method(:commit_count))
        @resource_budget = resource_budget || ResourceBudget.new(root:)
        @poll = poll_seconds
        @lock = Mutex.new
        @stages = Hash.new(0.0)
        @boundaries = {}
        @warned = false
        @fix_budget = limits || fix_budget_limits
        @killer = killer || ->(_reason) { Process.kill("TERM", Process.pid) }
        @stop_grace = Integer(env.fetch("MASTER_FIX_STOP_GRACE_S", STOP_GRACE_SECONDS.to_s), exception: false) || 0
        @exit_reason = nil
        @law_spend = Hash.new { |hash, law| hash[law] = [0.0, 0] }
        @laws_over = {}
        @offset = 0
        @ledger = [0.0, 0]
      end

      def start!
        @started = @clock.call
        @started_wall = @wall.call.to_i
        @last_output = @started
        @last_beat = @started
        @last_machine_beat = @started
        @last_guard_check = @started
        # Check the disk before the first model call or stream event can fill
        # the journal. Resource pressure cannot wait for the 30-second cadence
        # when the filesystem is already below its hard floor.
        @last_resource_check = @started - RESOURCE_CHECK_SECONDS
        @last_unit = nil
        @last_text = nil
        @pass = 0
        guard_check(@started)
        return self if @exit_reason

        @last_resource_check = @started
        @watchdog = Thread.new { watch } if @poll.positive?
        self
      end

      def elapsed_seconds
        return 0.0 unless @started

        [@clock.call - @started, 0.0].max
      end

      def stop!
        watchdog = @watchdog
        @watchdog = nil
        # A stall or disk abort can be discovered by the watchdog itself.
        # Killing Thread.current here would interrupt finish!/killer before the
        # final report or hard safety stop had a chance to run.
        watchdog.kill if watchdog&.alive? && watchdog != Thread.current
      end

      # The run's last word: why it ended, what it did, what the autofix stage
      # and the model phase refused, and whether anything protected changed.
      def finish!(reason)
        stop!
        return if @finished_said

        @finished_said = true
        reason = @exit_reason || reason
        counts = @pulse.counts
        elapsed = @started ? (@clock.call - @started).round : 0
        @say.call("fix0: run ended reason=#{reason} elapsed=#{elapsed}s fixed=#{counts[:fixed]} failed=#{counts[:failed]} rejected=#{counts[:rejected]} attempts=#{counts[:attempts]}")
        (AutofixGuard.summary_lines + RunLedger.summary_lines).each { |text| @say.call(text) }
        @say.call(self_check_line)
      end

      # Time between two lines belongs to the unit that spoke first.
      def note_output(unit, text)
        return if unit.to_s == UNIT || @started.nil?

        now = @clock.call
        @lock.synchronize do
          @stages[@last_unit] += now - @last_output if @last_unit
          @last_output = now
          @last_unit = unit.to_s
          @last_text = text.to_s[0, 60]
        end
        @pulse.unit = unit
      end

      # Reads only the ledger lines written since the last call: the per-law
      # check asks after every violation, and the file grows with the run.
      def spend
        return @ledger unless File.file?(@costs)

        File.open(@costs) do |io|
          io.seek(@offset)
          while (line = io.gets)
            break unless line.end_with?("\n")

            @offset = io.pos
            row = parse(line)
            next unless row && row["ts"].to_i >= @started_wall

            @ledger = [@ledger.first + row["amount"].to_f, @ledger.last + row["tokens"].to_i]
          end
        end
        @ledger
      rescue SystemCallError
        @ledger
      end

      def note_law_cost(law_id, usd, tokens = 0)
        @lock.synchronize do
          sum = @law_spend[law_id.to_s]
          @law_spend[law_id.to_s] = [sum.first + usd.to_f, sum.last + tokens.to_i]
        end
      end

      # A law may spend its share of the run's dollars or of its token budget:
      # subscription lanes bill $0.00 and still burn tokens (342191 tokens at
      # $0.00 in one measured run), so dollars alone would never trip.
      def law_limit_exceeded?(law_id)
        usd, tokens = @lock.synchronize { @law_spend[law_id.to_s] }
        share = law_share(law_id)
        (usd > @max_cost * share || tokens > run_tokens * share).tap { |over| announce_law_over(law_id, usd, tokens, share) if over }
      end

      # Prints the budget line; returns the reason to stop, or nil.
      def boundary(pass)
        cost, tokens = spend
        minutes = (@clock.call - @started) / 60.0
        @boundaries[pass] = @clock.call
        @pass = pass
        @out.call(line(cost, tokens, minutes, pass))
        reason = exhausted(cost, minutes)
        warn_near(cost, minutes) unless reason
        @out.call(reason) if reason
        reason
      end

      # The dmesg banner, then the pulse listening to the bus.
      def announce(target:, bus:)
        # A startup disk preflight may already have ended the run. Do not
        # attach event listeners or emit a fresh-run banner after that verdict.
        return self if @exit_reason

        limits = "budget #{show(@max_cost, "$")} / #{show(@max_minutes, "", "m")}"
        RunPulse::Banner.lines(root: @root, target: target || @root, max_passes: @max_passes, limits:).each { |text| @say.call(text) }
        @pulse.attach(bus) if bus
        @guard_scope = guard_scope(target)
        @protected_baseline = AutofixGuard.protected_changes(@root)
      end

      # The tree a run can write, as a repository-relative prefix ("RAILS/"), or nil for the whole
      # repository: another writer's STUDIO edit stopped a RAILS run, which cannot touch STUDIO.
      def guard_scope(target)
        relative = File.expand_path(target.to_s, @root).delete_prefix("#{File.expand_path(Master::REPO_ROOT)}/")
        tree = relative.split("/").first

        tree && MasterPaths::TREES.include?(tree) ? "#{tree}/" : nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RunBudget.guard_scope")
        nil
      end

      def pass_end(pass)
        fused = ToolBreaker.fused_count
        lines = @pulse.pass_summary(pass, tokens: spend.last)
        lines.concat(AutofixGuard.summary_lines)
        lines.concat(RunLedger.summary_lines)
        lines << Refusals.pass_summary_line
        lines << "fix0: pass #{pass} #{fused} tuples fused" if fused.positive?
        lines << "fix0: pass #{pass} #{@laws_over.size} laws over budget" if @laws_over.any?
        lines.each { |text| @say.call(text) }
      end

      # The watchdog calls this; a test drives it without a thread. One line
      # per HEARTBEAT_SECONDS whatever else was said, so a run is never quiet
      # for longer than that.
      def beat
        now = @clock.call
        return if now - @last_beat < @beat_every

        @last_beat = now
        message = @pulse.line(elapsed: now - @started, tokens: spend.last, eta: eta_part)
        fused = ToolBreaker.fused_count
        message = "#{message} #{fused} tuples fused" if fused.positive?
        @say.call(message)
        watch_for_stall
        message
      end

      # A pass with no fix attempted past MASTER_FIX_STALL_S says so on every
      # heartbeat, and an advisory phase is cut short rather than waited out.
      def watch_for_stall
        stalled = @pulse.stall(@clock.call)
        return unless stalled

        @say.call(stalled[:line])
        Master::Review::LLMDispatcher::PassClock.cancel!("stalled") if stalled[:skippable]
        return unless stalled[:abort]

        reason = stalled[:line].sub(/\Afix0: STALLED /, "stalled, ")
        # A non-advisory no-progress stall is a safety stop, not a preference. The run is asked to
        # stop first, so its proof and scorecard still say what it did; a run that does not wind
        # down within the grace is killed, so an unattended deadlock never waits another hour.
        stop_gracefully!(reason)
      end

      # Every abort reason, including startup disk/protected-path failures, must reach /fix.
      def stopping = @stopping || @exit_reason

      def stop_gracefully!(reason)
        return if @stopping || @exit_reason
        unless @stop_grace.positive?
          abort_run!(reason, force: true)
          return
        end

        @stopping = reason
        @say.call("fix0: STOPPING #{reason}; ending the repair to prove what it did")
        Thread.new do
          sleep @stop_grace
          abort_run!("#{reason}; still running #{@stop_grace}s after the stop", force: true) unless @finished_said
        end
        nil
      end

      # Distinguish an infrastructure abort from a graceful/progress timeout.
      def stop_category = @exit_reason.to_s.match?(/disk (?:pressure|space|measurement unavailable)|protected path changed/) ? :infrastructure : :timeout

      # One machine-readable heartbeat a minute, whatever the human line says.
      def machine_beat(now)
        guard_check(now)
        return if now - (@last_machine_beat || 0) < MACHINE_BEAT_SECONDS

        @last_machine_beat = now
        @say.call(@pulse.machine_line(now - @started))
        reasons = RunLedger.why_line
        @say.call("fix0: not landed so far, #{reasons}") if reasons
      end

      # Safety monitor: measure disk pressure every 30 seconds and stop before
      # exhaustion; compare protected paths every five minutes and stop on drift.
      # Only stall aborts honor MASTER_FIX_ABORT_ON_STALL=0.
      def guard_check(now)
        if now - (@last_resource_check || @started || now) >= RESOURCE_CHECK_SECONDS
          @last_resource_check = now
          measurement = @resource_budget.measure
          free_gb = measurement.dig(:values, :disk_free_gb)
          if @resource_budget.disk_critical?(measurement)
            reason = free_gb.nil? ? "disk space measurement unavailable" : "disk pressure at #{free_gb} GB free"
            abort_run!("#{reason}; stopping before filesystem exhaustion", force: true)
          end
        end

        return unless @protected_baseline && now - (@last_guard_check || 0) >= GUARD_CHECK_SECONDS

        @last_guard_check = now
        fresh = new_protected_changes
        abort_run!("protected path changed: #{fresh.first(3).join(", ")}", force: true) unless fresh.empty?
      end

      def new_protected_changes
        fresh = AutofixGuard.protected_changes(@root) - @protected_baseline
        @guard_scope ? fresh.select { |path| path.start_with?(@guard_scope) } : fresh
      end

      def self_check_line
        return "fix0: self-check: protected paths unchecked" unless @protected_baseline

        fresh = new_protected_changes
        fresh.empty? ? "fix0: self-check: no protected path changed by this run" : "fix0: self-check: PROTECTED PATHS CHANGED by this run: #{fresh.join(", ")}"
      end

      # Says why, prints the summary, then ends the process. MASTER_FIX_ABORT_ON_STALL=0
      # keeps the run going and only reports.
      def abort_run!(reason, force: false)
        if @exit_reason
          return unless force

          @exit_reason = reason
          @say.call("fix0: ABORT #{reason}")
          @killer.call(reason)
          return
        end

        @exit_reason = reason
        @say.call("fix0: ABORT #{reason}")
        finish!(reason)
        return unless force || ENV["MASTER_FIX_ABORT_ON_STALL"] != "0"

        roll_back_open_pass
        discard_unproven_writes
        @killer.call(reason)
      end

      # The pass in flight goes back first: the MASTER abort of 2026-10-23 left a model's half-applied
      # edit to bin/loops in the tree. A file another writer changed since stays (Committer#roll_back_own).
      # A commit holding the committer's lock past the wait is left to the next run's recovery.
      def roll_back_open_pass
        owner = self.class.pass_owner
        return unless owner

        worker = Thread.new { owner.abort_transaction! }
        return if worker.join(ROLLBACK_WAIT_SECONDS)

        @say.call("fix0: the open pass did not roll back in #{ROLLBACK_WAIT_SECONDS}s; recovery restores it")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RunBudget.roll_back_open_pass")
      end

      # An aborted run proves nothing, and its TERM skips the pipeline's clean-up, so the uncommitted
      # autofix bytes go back first; a file changed since is another writer's and stays.
      def discard_unproven_writes
        reverted, left = AutofixGuard.revert_written!(uncommitted_paths)
        @say.call("fix0: put back #{reverted.size} file(s) the autofix wrote") if reverted.any?
        @say.call("fix0: left #{left.size} file(s) changed since the autofix wrote them") if left.any?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RunBudget.discard_unproven_writes")
      end

      # Spelled from @root, as the autofix recorded its writes: --show-toplevel answers with symlinks
      # resolved (/private/var for /var), and no path would match.
      def uncommitted_paths
        up, = Open3.capture2("git", "-C", @root, "rev-parse", "--show-cdup")
        top = File.expand_path(up.strip, @root)
        listing, = Open3.capture2("git", "-C", top, "diff", "--name-only", "HEAD")
        listing.lines.map { |path| File.join(top, path.strip) }
      end

      private

      def fix_budget_limits
        data = Master.load_yaml(Master.limits_path, default: {}) || {}
        data["fix_budget"].is_a?(Hash) ? data["fix_budget"] : {}
      rescue StandardError
        {}
      end

      def law_share(law_id)
        Float(@fix_budget.dig("law_shares", law_id.to_s) || @fix_budget["law_share"] || DEFAULT_LAW_SHARE)
      end

      def run_tokens = Integer(@fix_budget["run_tokens"] || DEFAULT_RUN_TOKENS)

      def announce_law_over(law_id, usd, tokens, share)
        return if @laws_over.key?(law_id.to_s)

        @laws_over[law_id.to_s] = true
        @out.call("#{law_id} not configured, law budget spent: $#{format("%.2f", usd)} and #{tokens} tokens " \
                  "past #{(share * 100).round}% of the run; skipped until the run ends")
      end

      WATCHDOG_MAX_CONSECUTIVE_FAILURES = 5

      def watch
        failures = 0
        loop do
          sleep @poll
          begin
            beat
            machine_beat(@clock.call) unless @exit_reason
            failures = 0
          rescue StandardError => e
            failures += 1
            Master::Ground::Swallow.log(
              e, context: "Fix::RunBudget.watch", severity: :load_bearing
            )
            next unless failures >= WATCHDOG_MAX_CONSECUTIVE_FAILURES

            @exit_reason ||= "watchdog failed #{failures} consecutive beats: #{e.class}"
            Master::Trace::Dmesg.status(
              "fix0",
              "watchdog failed #{failures} consecutive beats — run stops: #{e.class}: #{e.message.to_s[0, 120]}",
            )
            break
          end
          break if @exit_reason
        end
      end

      def limit(raw, default)
        return default if raw.to_s.strip.empty?
        return Float::INFINITY if %w[0 off none unlimited].include?(raw.to_s.strip.downcase)

        value = raw.to_f
        value.positive? ? value : default
      end

      def eta_part
        eta(@pass).sub("ETA ", "eta ")
      end

      def commit_count
        out, status = Master::Io::Exec.capture2e("git", "-C", @root, "rev-list", "--count", "HEAD")
        status.success? ? out.to_i : 0
      rescue StandardError
        0
      end

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def line(cost, tokens, minutes, pass)
        parts = ["spent $#{format("%.2f", cost)} / #{show(@max_cost, "$")}", "#{tokens} tokens",
                 "#{minutes.round(1)} / #{show(@max_minutes, "", "m")}"]
        parts << "stages #{stage_times}" unless stage_times.empty?
        parts << "pass #{pass}"
        parts << eta(pass)
        parts.join(", ")
      end

      def show(value, prefix = "", suffix = "")
        value.infinite? ? "no limit" : "#{prefix}#{value.round(2)}#{suffix}"
      end

      def stage_times
        top = @lock.synchronize { @stages.sort_by { |_, secs| -secs }.first(3) }
        top.map { |unit, secs| "#{unit} #{secs >= 90 ? "#{(secs / 60).round(1)}m" : "#{secs.round}s"}" }.join(" ")
      end

      def eta(pass)
        done = pass - 1
        return "ETA unknown" if done < 1 || @max_passes <= done

        first = @boundaries.min_by { |n, _| n }
        per_pass = (@boundaries.fetch(pass) - first.last) / [pass - first.first, 1].max
        "ETA ~#{(per_pass * (@max_passes - done) / 60.0).ceil}m"
      end

      def exhausted(cost, minutes)
        if cost > @max_cost
          "budget exhausted: spent $#{format("%.2f", cost)} over the $#{@max_cost.round(2)} limit " \
            "(MASTER_FIX_MAX_COST); stopping before the next pass"
        elsif minutes > @max_minutes
          "budget exhausted: #{minutes.round} minutes over the #{@max_minutes.round}-minute limit " \
            "(MASTER_FIX_MAX_MINUTES); stopping before the next pass"
        end
      end

      def warn_near(cost, minutes)
        return if @warned
        return unless cost > @max_cost * WARN_SHARE || minutes > @max_minutes * WARN_SHARE

        @warned = true
        @out.call("past #{(WARN_SHARE * 100).round}% of a run limit; raise MASTER_FIX_MAX_COST or MASTER_FIX_MAX_MINUTES to continue past it")
      end
    end
  end
end
