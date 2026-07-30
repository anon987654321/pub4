# frozen_string_literal: true

module Deploy
  # Three outcomes, not two.
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
    attr_reader :failures, :warnings, :soft_failures, :unchecked

    TRUTHY = %w[1 true yes on].freeze

    def self.flag?(name, env = ENV)
      TRUTHY.include?(env[name].to_s.strip.downcase)
    end

    # GATE_STRICT_SOFT=1 promotes soft failures to hard (merge-blocking).
    def self.strict_soft?(env = ENV) = flag?("GATE_STRICT_SOFT", env)

    # GATE_STRICT_INCONCLUSIVE=1 promotes "could not check" to hard.
    def self.strict_inconclusive?(env = ENV) = flag?("GATE_STRICT_INCONCLUSIVE", env)

    def initialize
      @failures = []
      @warnings = []
      @soft_failures = []
      @unchecked = []
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

    # A check that could not run. Name the missing precondition, not the check:
    # "no Chrome/Chromium" reads as a fixable environment fact, "geometry not
    # measured" reads as a mystery.
    def inconclusive!(reason)
      @unchecked << reason
      @failures << "[unchecked→hard] #{reason}" if self.class.strict_inconclusive?
      self
    end

    def ok?
      @failures.empty?
    end

    # Did this gate actually check the thing it exists to check?
    def conclusive?
      @unchecked.empty?
    end

    # The one place the three states are ranked. Callers that aggregate gates
    # (RAILS/gates/runner.rb) ask for this instead of re-deriving it from the
    # three lists, so the suite line and a leaf's own output cannot disagree.
    def outcome
      return :failed unless ok?

      conclusive? ? :passed : :inconclusive
    end

    # label: prefixes every merged message, so a composite's output still names
    # which leaf produced each line.
    def merge!(other, label: nil)
      tag = label ? "[#{label}] " : ""
      Array(other.failures).each { |m| @failures << "#{tag}#{m}" }
      Array(other.warnings).each { |w| @warnings << "#{tag}#{w}" }
      Array(other.soft_failures).each { |m| @soft_failures << "#{tag}#{m}" } if other.respond_to?(:soft_failures)
      Array(other.unchecked).each { |m| @unchecked << "#{tag}#{m}" } if other.respond_to?(:unchecked)
      self
    end

    # Everything report! does except exiting, so an aggregating caller gets the
    # same rendering. Pass no success_message when the caller prints its own.
    def render(success_message = nil)
      emit("Warnings:", @warnings)
      emit("Not checked:", @unchecked)
      emit("Failures:", @failures)

      case outcome
      when :failed then :failed
      when :inconclusive
        # Deliberately not the success message: the point of the third state is
        # that this gate has nothing to report success about.
        puts "inconclusive: #{@unchecked.size} check(s) did not run (set GATE_STRICT_INCONCLUSIVE=1 to treat as failure)"
        :inconclusive
      else
        puts success_message if success_message
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
