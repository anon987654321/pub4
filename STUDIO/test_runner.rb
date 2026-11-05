# frozen_string_literal: true

module Studio
  # A subprocess exit code is not sufficient test evidence: a file may load,
  # register no tests and exit successfully. This parser is shared by the
  # STUDIO Rake task and its regression tests.
  module TestRunner
    SUMMARY_RE = /\A\s*(\d+) runs?, (\d+) assertions?, (\d+) failures?, (\d+) errors?(?:, (\d+) skips?)?\s*\z/

    Result = Struct.new(:state, :reason, :summary, keyword_init: true)

    module_function

    def parse_summary(output)
      output.to_s.lines.filter_map do |line|
        match = SUMMARY_RE.match(line.chomp)
        next unless match

        runs, assertions, failures, errors, skips = match.captures
        {
          runs: runs.to_i,
          assertions: assertions.to_i,
          failures: failures.to_i,
          errors: errors.to_i,
          skips: skips.to_s.to_i
        }
      end.last
    end

    def classify(output, status)
      summary = parse_summary(output)
      return Result.new(state: :blocked, reason: "no valid Minitest summary") unless summary
      if summary.fetch(:runs).zero?
        return Result.new(state: :blocked, reason: "Minitest reported zero runs", summary:)
      end

      failures = summary.fetch(:failures)
      errors = summary.fetch(:errors)
      if failures.positive? || errors.positive?
        reason = "Minitest reported #{failures} failures and #{errors} errors"
        return Result.new(state: :fail, reason:, summary:)
      end

      unless status&.success?
        exit_status = status&.exitstatus
        reason = "test process exited #{exit_status || "unsuccessfully"}"
        return Result.new(state: :fail, reason:, summary:)
      end

      Result.new(state: :pass, summary:)
    end

    def summary_line(summary)
      "#{summary.fetch(:runs)} runs, #{summary.fetch(:assertions)} assertions, " \
        "#{summary.fetch(:failures)} failures, #{summary.fetch(:errors)} errors, " \
        "#{summary.fetch(:skips)} skips"
    end
  end
end
