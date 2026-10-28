# frozen_string_literal: true

# MASTER/checks/support owns the check kernel. OPENBSD/lib/check_result.rb is a
# compatibility path. Every check in the repo returns this
# type: RAILS/checks, MASTER/checks, OPENBSD/checks and MASTER/tools/check.rb require it
# across the tree boundary and add nothing to it, so adding an outcome is a
# change with four consumers. A repo-level lib/ means a fifth top-level tree
# holding three files. MASTER/lib requires nothing from either sibling — it reads
# their data and reaches STUDIO's check through `rake studio` as a subprocess —
# and a shared kernel is the thing everything ends up requiring. Revisit when a
# fifth consumer appears.

module Deploy
  # Four outcomes, not two.
  #
  # :passed, :failed, :inconclusive (the check declined to measure), :errored
  # (the check tried and broke). These remain distinct for diagnosis, but an
  # errored result can never make a runner or report claim success.
  #
  # `ok?` is not a pass verdict: it means no hard failure or check error has
  # occurred. `outcome` distinguishes a measured pass from an inconclusive run.
  # A check that could not run —
  # no Chrome, no app listening, no deploy stamp, a missing gem — reported the
  # same green as a check that ran and found nothing. Sixteen checks in the RAILS
  # suite take that path, which is why a green run of the whole suite meant less
  # than it looked: `deploy_drift` printed "ok: no deploy drift detected"
  # directly under its own warning saying "Nothing was checked."
  #
  # Warnings could not express it. A warning is something a check observed; this
  # is a check declining to claim it observed anything. So `inconclusive!` is a
  # third state: it never blocks by default (off the deploy host most rendered
  # checks genuinely cannot run, and failing there would train people to ignore
  # the suite), but it does suppress the success line and name what was skipped.
  # CHECK_STRICT_INCONCLUSIVE=1 makes it blocking, for CI on the deploy host
  # where Chrome and the apps are supposed to be present.
  class CheckResult
    attr_reader :failures, :warnings, :soft_failures, :unchecked, :errors

    TRUTHY = %w[1 true yes on].freeze

    def self.flag?(name, env = ENV)
      TRUTHY.include?(env[name].to_s.strip.downcase)
    end

    # CHECK_STRICT_SOFT=1 promotes soft failures to hard (merge-blocking).
    def self.strict_soft?(env = ENV) = flag?("CHECK_STRICT_SOFT", env)

    # CHECK_STRICT_INCONCLUSIVE=1 promotes "could not check" to hard.
    def self.strict_inconclusive?(env = ENV) = flag?("CHECK_STRICT_INCONCLUSIVE", env)

    # CHECK_REQUIRE_LIVE=1 turns "port closed, skipping" into a failure.
    #
    # measured_nothing? cannot express this case: a check that ran fifty source
    # checks and skipped every live one has a non-zero check count, so it passes
    # and its skips are warnings. On 2026-08-03 that produced eight green checks on
    # a machine where no app was listening -- and booting the apps turned one of
    # them red immediately. This flag is for runs that mean to measure the live
    # half, so the absence of it is loud instead of a warning line.
    def self.require_live?(env = ENV) = flag?("CHECK_REQUIRE_LIVE", env)

    def initialize
      @failures = []
      @warnings = []
      @soft_failures = []
      @unchecked = []
      @gaps = {}

      @errors = []
      @checks_ran = 0
      @live_skips = 0
      @incomplete = false
    end

    # The check itself broke — an exception escaped its own run, not a finding
    # it made about the tree. Keep the fourth state so the report names the
    # broken instrument rather than mislabelling its crash as a tree finding.
    # A runner must still finish the remaining checks, record this outcome, and
    # exit non-zero: a missing verdict is not a pass.
    def errored!(reason)
      @errors << reason
      self
    end

    # A check that raised, rendered as a result rather than as a backtrace. The
    # caller passes the check name because an exception message rarely says which
    # check produced it.
    def self.from_error(exception, check:, backtrace_lines: 3)
      trace = Array(exception.backtrace).first(backtrace_lines).join(" | ")
      new.errored!(
        "#{check} raised #{exception.class}: #{exception.message}#{trace.empty? ? '' : " @ #{trace}"}",
      )
    end

    # severity: :hard (default, blocks) | :soft (warn unless CHECK_STRICT_SOFT)
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

    # A live check the check declined to run because nothing was listening.
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
    #
    # gap: is a Master::Gap (duck-typed: anything with #clause) saying whether
    # the check resolves alone, what it costs, and whose call it is. This file
    # does not load it: OPENBSD/lib carries a copy and must not reach into MASTER.
    def inconclusive!(reason, gap: nil)
      @unchecked << reason

      @gaps[reason] = gap if gap
      self
    end

    # reason => gap, for the reasons that came with one.
    attr_reader :gaps

    # A check that measured something and could not measure everything it
    # declares. inconclusive! alone leaves the outcome :passed whenever one
    # check ran, so a flow check whose apps were mostly down read as green over
    # a "Not checked" block nobody opened. This is the stronger statement: the
    # check's verdict is :inconclusive, never :passed, while it stands. It does
    # not block by itself (CHECK_REQUIRE_LIVE does that, through skipped_live,
    # on the host where the apps must be up) -- it only refuses to be green.
    def incomplete!(reason, gap: nil)
      @incomplete = true

      inconclusive!(reason, gap:)
    end

    def incomplete? = @incomplete

    # Count a check that actually ran, so a check can say how much it measured.
    #
    # Without this the two states are indistinguishable: a passing check records
    # nothing, so `unchecked.empty?` was the only signal available and one skipped
    # precondition spoke for the whole check. human_walkthrough runs source checks
    # for every app and needs a port only for the live half, so a single parked app
    # made it report "INCONCLUSIVE (checked nothing)" -- untrue -- and dropped it
    # from the pass count.
    def checked!(count = 1)
      @checks_ran += count

      self
    end

    attr_reader :checks_ran

    # Nothing measured at all. This is what CHECK_STRICT_INCONCLUSIVE is for, and
    # it is now decided here rather than inside inconclusive!: promoting at record
    # time meant a check that ran fifty checks and skipped one hard-failed on the
    # deploy host, so `resource_guard.sh` parking amber -- a documented, normal VPS
    # state -- blocked releases that had nothing wrong with them.
    #
    # A live skip counts toward "measured nothing" as of 2026-08-11. It did not,
    # and that was the hole: skipped_live files a warning rather than an unchecked
    # precondition, so a check whose ENTIRE check set was live-skipped had zero
    # checks, zero unchecked and reported PASSED. layout_geometry did exactly that
    # on 2026-08-03 -- PASSED having skipped all 17 of its checks because no app was
    # listening, which is how a dead amber and bsdports read as green for an unknown
    # number of days (the old backlog: amber_bsdports_stop_and_stay_down).
    #
    # A check that skipped some live checks and ran others still passes: this asks
    # whether anything at all was measured, not whether everything was.
    def measured_nothing?
      @checks_ran.zero? && (!@unchecked.empty? || @live_skips.positive?)
    end

    # Why nothing was measured, in the terms the reader can act on. "0
    # precondition(s) missing" was the old output for an all-live-skipped check,
    # which is both true and useless: the preconditions were not missing, the app
    # was not listening.
    def nothing_measured_reason
      parts = []

      parts << "#{@unchecked.size} precondition(s) missing" unless @unchecked.empty?
      parts << "#{@live_skips} live check(s) skipped, nothing listening" if @live_skips.positive?
      parts.empty? ? "no checks ran" : parts.join(", ")
    end

    # An errored check has no verdict; callers must not confuse its empty
    # finding list with success.
    def ok?
      @failures.empty? && @errors.empty?
    end

    # Did this check check everything it exists to check?
    def conclusive?
      @unchecked.empty? && @live_skips.zero?
    end

    # The one place the three states are ranked. Callers that aggregate checks
    # (MASTER/checks/runner.rb) ask for this instead of re-deriving it from the
    # three lists, so the suite line and a leaf's own output cannot disagree.
    #
    # :inconclusive means the check measured nothing, not that it skipped
    # something. A check that checked fifty things and could not check the
    # fifty-first passed, and says what it skipped -- calling that "checked
    # nothing" was false, dropped it out of the pass count, and under
    # CHECK_STRICT_INCONCLUSIVE turned a parked app into a blocked deploy.
    # A check whose own code raised. Ranked above :inconclusive because it is a
    # stronger statement: inconclusive means the check declined to measure,
    # errored means it tried and broke.
    def errored? = !@errors.empty?

    def outcome
      return :failed unless @failures.empty?
      return :errored if errored?
      return :failed if measured_nothing? && self.class.strict_inconclusive?

      measured_nothing? || incomplete? ? :inconclusive : :passed
    end

    # label: prefixes every merged message, so a composite's output still names
    # which leaf produced each line.
    def merge!(other, label: nil)
      tag = label ? "[#{label}] " : ""
      Array(other.failures).each { |m| @failures << "#{tag}#{m}" }
      Array(other.warnings).each { |w| @warnings << "#{tag}#{w}" }
      Array(other.soft_failures).each { |m| @soft_failures << "#{tag}#{m}" }

      Array(other.unchecked).each { |m| @unchecked << "#{tag}#{m}" }
      other.gaps.each { |m, gap| @gaps["#{tag}#{m}"] = gap } if other.respond_to?(:gaps)
      # Without this a composite swallows a leaf that crashed: the leaf's errors
      # would be neither failures nor unchecked, so the composite would report
      # PASSED for a leaf that never ran. That is the same false green the third
      # state was added to close, one level up.
      Array(other.errors).each { |m| @errors << "#{tag}#{m}" } if other.respond_to?(:errors)

      # A composite measured whatever its leaves measured, or one leaf with no
      # Chrome would speak for the whole suite the way one app used to speak for
      # a whole check.
      @checks_ran += other.checks_ran if other.respond_to?(:checks_ran)
      @incomplete ||= other.incomplete? if other.respond_to?(:incomplete?)

      # Same reason as checks_ran: without this a composite whose every leaf
      # live-skipped would look like a composite that had nothing to skip.
      @live_skips += other.live_skips if other.respond_to?(:live_skips)
      self
    end

    # Everything report! does except exiting, so an aggregating caller gets the
    # same rendering. Pass no success_message when the caller prints its own.
    def render(success_message = nil)
      emit("Warnings:", @warnings)
      emit("Not checked:", @unchecked.map { |reason| @gaps[reason] ? "#{reason} (#{@gaps[reason].clause})" : reason })
      emit("Check errors (no verdict produced):", @errors)
      emit("Failures:", @failures)

      case outcome
      when :errored
        puts "errored: the check itself broke — #{@errors.size} error(s) above; this run cannot pass"
        :errored
      when :failed
        # The strict-mode failure has no message of its own -- the promotion moved
        # out of inconclusive! and into outcome -- so say why, or the runner reports
        # FAILED with nothing under it.
        if @failures.empty?
          emit("Failures:", ["nothing measured, and CHECK_STRICT_INCONCLUSIVE is set " \
                             "(#{nothing_measured_reason})"])
        end

        :failed
      when :inconclusive
        # Deliberately not the success message: the point of the third state is
        # that this check has nothing to report success about.
        if measured_nothing?
          puts "inconclusive: nothing measured — #{nothing_measured_reason} " \
               "(set CHECK_STRICT_INCONCLUSIVE=1 to treat as failure)"
        else
          puts "inconclusive: #{@checks_ran} check(s) ran, #{@unchecked.size} declared check(s) could not " \
               "(see Not checked above; this is not a pass)"
        end

        :inconclusive
      else
        # A pass that skipped something says so, instead of printing a clean
        # success line over a "Not checked:" block.
        if success_message
          detail = ["#{@checks_ran} check(s) ran"]
          detail << "#{@unchecked.size} check(s) not checked" unless @unchecked.empty?

          detail << "#{@live_skips} live check(s) skipped" if @live_skips.positive?
          puts conclusive? ? success_message : "#{success_message} (#{detail.join(', ')})"
        end
        :passed
      end
    end

    def report!(success_message)
      exit 1 if %i[failed errored].include?(render(success_message))
    end

    private

    def emit(header, messages)
      return if messages.empty?

      Kernel.warn header
      messages.each { |message| Kernel.warn "  - #{message}" }
    end
  end
end
