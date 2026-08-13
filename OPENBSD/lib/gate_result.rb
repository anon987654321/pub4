# frozen_string_literal: true

module Deploy
  # Four outcomes, not two.
  #
  # :passed, :failed, :inconclusive (the gate declined to measure), :errored
  # (the gate tried and broke). The first three are below; :errored and its
  # fail-open policy are documented on `errored!`.
  #
  # `ok?` only ever meant "no hard failures", so a gate that could not run —
  # no Chrome, no app listening, no deploy stamp, a missing gem — reported the
  # same green as a gate that ran and found nothing. Sixteen gates in the RAILS
  # suite take that path, which is why a green run of the whole suite meant less
  # than it looked: `deploy_drift` printed "ok: no deploy drift detected"
  # directly under its own warning saying "Nothing was checked."
  #
  # Warnings could not express it. A warning is something a gate observed; this
  # is a gate declining to claim it observed anything. So `inconclusive!` is a
  # third state: it never blocks by default (off the deploy host most rendered
  # gates genuinely cannot run, and failing there would train people to ignore
  # the suite), but it does suppress the success line and name what was skipped.
  # GATE_STRICT_INCONCLUSIVE=1 makes it blocking, for CI on the deploy host
  # where Chrome and the apps are supposed to be present.
  class GateResult
    attr_reader :failures, :warnings, :soft_failures, :unchecked, :errors

    TRUTHY = %w[1 true yes on].freeze

    def self.flag?(name, env = ENV)
      TRUTHY.include?(env[name].to_s.strip.downcase)
    end

    # GATE_STRICT_SOFT=1 promotes soft failures to hard (merge-blocking).
    def self.strict_soft?(env = ENV) = flag?("GATE_STRICT_SOFT", env)

    # GATE_STRICT_INCONCLUSIVE=1 promotes "could not check" to hard.
    def self.strict_inconclusive?(env = ENV) = flag?("GATE_STRICT_INCONCLUSIVE", env)

    # GATE_REQUIRE_LIVE=1 turns "port closed, skipping" into a failure.
    #
    # measured_nothing? cannot express this case: a gate that ran fifty source
    # checks and skipped every live one has a non-zero check count, so it passes
    # and its skips are warnings. On 2026-08-03 that produced eight green gates on
    # a machine where no app was listening -- and booting the apps turned one of
    # them red immediately. This flag is for runs that mean to measure the live
    # half, so the absence of it is loud instead of a warning line.
    def self.require_live?(env = ENV) = flag?("GATE_REQUIRE_LIVE", env)

    # GATE_STRICT_ERRORS=1 makes a gate's own crash blocking. See errored! for
    # why the default is the other way.
    def self.strict_errors?(env = ENV) = flag?("GATE_STRICT_ERRORS", env)

    def initialize
      @failures = []
      @warnings = []
      @soft_failures = []
      @unchecked = []
      @errors = []
      @checks_ran = 0
      @live_skips = 0
    end

    # The gate itself broke — an exception escaped its own run, not a finding
    # it made about the tree.
    #
    # Fail-open, from arXiv 2607.07405 §"deterministic gates": "if a gate itself
    # raises an exception, the harness records the error and allows the original
    # call." Their reason is precision. A gate that crashes and blocks produces a
    # false block on every subsequent call, and a suite whose blocks are mostly
    # its own bugs is one people learn to route around — which is how a gate
    # fleet stops being read at all.
    #
    # pub4's version of that was worse than a false block: RAILS/gates/runner.rb
    # called `klass.run` with no rescue, so one gate raising killed the process
    # and every gate after it in the --all order never ran. Forty-six gates
    # reporting nothing, exit 1, and a backtrace where the summary should be.
    #
    # So this is a fourth state and not a failure: it never blocks by default,
    # it is counted and named separately from both :passed and :failed, and it
    # can never be mistaken for a pass. GATE_STRICT_ERRORS=1 promotes it for CI
    # on the deploy host, where a gate that cannot run is itself the news.
    def errored!(reason)
      @errors << reason
      @failures << "[gate-error] #{reason}" if self.class.strict_errors?
      self
    end

    # A gate that raised, rendered as a result rather than as a backtrace. The
    # caller passes the gate name because an exception message rarely says which
    # gate produced it.
    def self.from_error(exception, gate:, backtrace_lines: 3)
      trace = Array(exception.backtrace).first(backtrace_lines).join(" | ")
      new.errored!(
        "#{gate} raised #{exception.class}: #{exception.message}#{trace.empty? ? '' : " @ #{trace}"}"
      )
    end

    # severity: :hard (default, blocks) | :soft (warn unless GATE_STRICT_SOFT)
    def fail(message, severity: :hard)
      case severity.to_sym
      when :soft
        @soft_failures << message
        if self.class.strict_soft?
          @failures << "[soft→hard] #{message}"
        else
          @warnings << "[soft] #{message}"
        end
      else
        @failures << message
      end
    end

    def warn(message)
      @warnings << message
    end

    # A live check the gate declined to run because nothing was listening.
    def skipped_live(message)
      @live_skips += 1
      if self.class.require_live?
        @failures << "[live-required] #{message}"
      else
        @warnings << message
      end
      self
    end

    attr_reader :live_skips

    # A check that could not run. Name the missing precondition, not the check:
    # "no Chrome/Chromium" reads as a fixable environment fact, "geometry not
    # measured" reads as a mystery.
    def inconclusive!(reason)
      @unchecked << reason
      self
    end

    # Count a check that actually ran, so a gate can say how much it measured.
    #
    # Without this the two states are indistinguishable: a passing check records
    # nothing, so `unchecked.empty?` was the only signal available and one skipped
    # precondition spoke for the whole gate. human_walkthrough runs source checks
    # for every app and needs a port only for the live half, so a single parked app
    # made it report "INCONCLUSIVE (checked nothing)" -- untrue -- and dropped it
    # from the pass count.
    def checked!(count = 1)
      @checks_ran += count
      self
    end

    attr_reader :checks_ran

    # Nothing measured at all. This is what GATE_STRICT_INCONCLUSIVE is for, and
    # it is now decided here rather than inside inconclusive!: promoting at record
    # time meant a gate that ran fifty checks and skipped one hard-failed on the
    # deploy host, so `resource_guard.sh` parking amber -- a documented, normal VPS
    # state -- blocked releases that had nothing wrong with them.
    #
    # A live skip counts toward "measured nothing" as of 2026-08-11. It did not,
    # and that was the hole: skipped_live files a warning rather than an unchecked
    # precondition, so a gate whose ENTIRE check set was live-skipped had zero
    # checks, zero unchecked and reported PASSED. layout_geometry did exactly that
    # on 2026-08-03 -- PASSED having skipped all 17 of its checks because no app was
    # listening, which is how a dead amber and bsdports read as green for an unknown
    # number of days (data/debt.yml: amber_bsdports_stop_and_stay_down).
    #
    # A gate that skipped some live checks and ran others still passes: this asks
    # whether anything at all was measured, not whether everything was.
    def measured_nothing?
      @checks_ran.zero? && (!@unchecked.empty? || @live_skips.positive?)
    end

    # Why nothing was measured, in the terms the reader can act on. "0
    # precondition(s) missing" was the old output for an all-live-skipped gate,
    # which is both true and useless: the preconditions were not missing, the app
    # was not listening.
    def nothing_measured_reason
      parts = []
      parts << "#{@unchecked.size} precondition(s) missing" unless @unchecked.empty?
      parts << "#{@live_skips} live check(s) skipped, nothing listening" if @live_skips.positive?
      parts.empty? ? "no checks ran" : parts.join(", ")
    end

    def ok?
      @failures.empty?
    end

    # Did this gate check everything it exists to check?
    def conclusive?
      @unchecked.empty?
    end

    # The one place the three states are ranked. Callers that aggregate gates
    # (RAILS/gates/runner.rb) ask for this instead of re-deriving it from the
    # three lists, so the suite line and a leaf's own output cannot disagree.
    #
    # :inconclusive means the gate measured nothing, not that it skipped
    # something. A gate that checked fifty things and could not check the
    # fifty-first passed, and says what it skipped -- calling that "checked
    # nothing" was false, dropped it out of the pass count, and under
    # GATE_STRICT_INCONCLUSIVE turned a parked app into a blocked deploy.
    # A gate whose own code raised. Ranked above :inconclusive because it is a
    # stronger statement: inconclusive means the gate declined to measure,
    # errored means it tried and broke.
    def errored? = !@errors.empty?

    def outcome
      return :failed unless ok?
      return :errored if errored?
      return :failed if measured_nothing? && self.class.strict_inconclusive?

      measured_nothing? ? :inconclusive : :passed
    end

    # label: prefixes every merged message, so a composite's output still names
    # which leaf produced each line.
    def merge!(other, label: nil)
      tag = label ? "[#{label}] " : ""
      Array(other.failures).each { |m| @failures << "#{tag}#{m}" }
      Array(other.warnings).each { |w| @warnings << "#{tag}#{w}" }
      Array(other.soft_failures).each { |m| @soft_failures << "#{tag}#{m}" }
      Array(other.unchecked).each { |m| @unchecked << "#{tag}#{m}" }
      # Without this a composite swallows a leaf that crashed: the leaf's errors
      # would be neither failures nor unchecked, so the composite would report
      # PASSED for a leaf that never ran. That is the same false green the third
      # state was added to close, one level up.
      Array(other.errors).each { |m| @errors << "#{tag}#{m}" } if other.respond_to?(:errors)
      # A composite measured whatever its leaves measured, or one leaf with no
      # Chrome would speak for the whole suite the way one app used to speak for
      # a whole gate.
      @checks_ran += other.checks_ran if other.respond_to?(:checks_ran)
      # Same reason as checks_ran: without this a composite whose every leaf
      # live-skipped would look like a composite that had nothing to skip.
      @live_skips += other.live_skips if other.respond_to?(:live_skips)
      self
    end

    # Everything report! does except exiting, so an aggregating caller gets the
    # same rendering. Pass no success_message when the caller prints its own.
    def render(success_message = nil)
      emit("Warnings:", @warnings)
      emit("Not checked:", @unchecked)
      emit("Gate errors (fail-open — nothing was blocked by these):", @errors)
      emit("Failures:", @failures)

      case outcome
      when :errored
        puts "errored: the gate itself broke and blocked nothing — " \
             "#{@errors.size} error(s) above (set GATE_STRICT_ERRORS=1 to treat as failure)"
        :errored
      when :failed
        # The strict-mode failure has no message of its own -- the promotion moved
        # out of inconclusive! and into outcome -- so say why, or the runner reports
        # FAILED with nothing under it.
        if @failures.empty?
          emit("Failures:", ["nothing measured, and GATE_STRICT_INCONCLUSIVE is set " \
                             "(#{nothing_measured_reason})"])
        end
        :failed
      when :inconclusive
        # Deliberately not the success message: the point of the third state is
        # that this gate has nothing to report success about.
        puts "inconclusive: nothing measured — #{nothing_measured_reason} " \
             "(set GATE_STRICT_INCONCLUSIVE=1 to treat as failure)"
        :inconclusive
      else
        # A pass that skipped something says so, instead of printing a clean
        # success line over a "Not checked:" block.
        if success_message
          puts conclusive? ? success_message : "#{success_message} (#{@checks_ran} check(s) ran, #{@unchecked.size} skipped)"
        end
        :passed
      end
    end

    def report!(success_message)
      exit 1 if render(success_message) == :failed
    end

    private

    def emit(header, messages)
      return if messages.empty?

      Kernel.warn header
      messages.each { |message| Kernel.warn "  - #{message}" }
    end
  end
end
