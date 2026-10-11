# frozen_string_literal: true

module Deploy
  # A wall-clock budget for a stretch of CDP work, so one sick surface fails
  # with a reason instead of retrying inside the transport for minutes.
  #
  # The deadline is enforced in two places: before each command (every command
  # past the deadline raises, so a probe that swallows errors cannot keep the
  # surface alive) and as a cap on each response wait. A command that was cut
  # short by the cap may surface as a plain Timeout that a caller records as a
  # payload error, so the block's exit checks the clock as well.
  module CdpBudget
    # Not a CdpSession::Error: GeometryProbe.walk turns those into a payload
    # error and carries on, which is the quiet failure this exists to end.
    class Exceeded < StandardError; end

    def with_budget(seconds, label)
      started = monotonic
      @budget_deadline = started + seconds
      @budget_recoveries = @recoveries
      result = yield
      raise_exceeded(label, seconds, started) if monotonic > @budget_deadline
      result
    rescue CdpSession::Error
      raise_exceeded(label, seconds, started) if monotonic > @budget_deadline
      raise
    ensure
      @budget_deadline = nil
    end

    private

    def check_budget!(method)
      @last_method = method
      return unless @budget_deadline && monotonic > @budget_deadline

      raise Exceeded, "over its time budget, #{method} refused"
    end

    def raise_exceeded(label, seconds, started)
      spent = (monotonic - started).round(1)
      rebuilt = @recoveries - @budget_recoveries
      raise Exceeded, "#{label} exceeded its #{seconds}s budget after #{spent}s " \
                      "(last command #{@last_method}, #{rebuilt} connection rebuild(s))"
    end
  end
end
