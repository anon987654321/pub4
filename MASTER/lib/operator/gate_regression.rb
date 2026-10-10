# frozen_string_literal: true

module Operator
  # Judges a repaired tree against the failures it started with. /fix used to
  # demand an absolute green ladder, which no run could earn while standing
  # debt held ratchets over their ceilings, so a correct repair ended as a
  # validation error and nothing landed. This asks the narrower question that
  # a repair can answer: did the run add a failure the tree did not have?
  #
  # It relaxes nothing. A failing stage that was green at the start is a
  # regression, a failing line with no counterpart at the start is a
  # regression, and an OVER count that grew is a regression. A standing
  # failure that stays the same or shrinks is not this run's to clear.
  class GateRegression
    SIGNAL = /OVER|unreadable|fail|error|violation|regress|blind|saturat|over a recorded|rose to/i

    # stage => the failing lines it printed, for stages that failed.
    def self.snapshot(results)
      Array(results).select { |result| result.state == "failed" }.to_h do |result|
        [result.stage, signal_lines(result.body)]
      end
    end

    def self.signal_lines(body)
      Array(body).map { |line| line.to_s.gsub(/\e\[[\d;]*m/, "").strip }.select { |line| line.match?(SIGNAL) }
    end

    def initialize(baseline)
      @baseline = baseline
    end

    def regressions(results)
      Array(results).select { |result| result.state == "failed" }.flat_map do |result|
        before = @baseline[result.stage]
        next ["#{result.stage} was green and now fails"] if before.nil?

        self.class.signal_lines(result.body).filter_map { |line| describe(result.stage, line, before) }
      end
    end

    private

    def describe(stage, line, before)
      same = before.select { |old| key(old) == key(line) }
      return "#{stage}: new, #{line}" if same.empty?
      return unless line.match?(/OVER/)

      now = number(line)
      worst_before = same.filter_map { |old| number(old) }.min
      "#{stage}: grew, #{line}" if now && worst_before && now > worst_before
    end

    def key(line) = line.gsub(/\d+/, "#")

    # The first figure after the name: the current value of an OVER row.
    def number(line) = line[/\s(\d+)\s*\//, 1]&.to_i
  end
end
