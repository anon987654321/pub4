# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      # "break it" lens: flags failure modes an adversary or bad luck would
      # find, not style. Complements SecurityAgent (which flags exploits)
      # by flagging plain unreliability -- what happens when the network,
      # the disk, or the caller misbehaves, not attacks.
      class ChaosAgent < BaseAgent
        EXTERNAL_CALL_PATTERN = /\b(Net::HTTP|HTTParty|Faraday|open-uri|URI\.open|Process\.spawn|`[^`]+`)\b/

        def initialize
          super(name: "ChaosAgent")
        end

        def analyze(code, file_path)
          check_unrescued_external_call(code, file_path)
          check_unbounded_retry(code, file_path)
          check_missing_timeout(code, file_path)
          findings
        end

        private

        def check_unrescued_external_call(code, file_path)
          return unless code.match?(EXTERNAL_CALL_PATTERN)
          return if code.match?(/rescue\b/)

          add_finding(
            severity: :warning,
            category: :reliability,
            message: "external call with no rescue anywhere in the file",
            line: 1,
            suggestion: "the network, the disk, and other processes fail; handle it or let a caller who can",
            file_path: file_path
          )
        end

        def check_unbounded_retry(code, file_path)
          code.each_line.with_index(1) do |line, line_no|
            next unless line.match?(/\bretry\b/)
            next if code.match?(/\battempts?\s*[<>=]|\bmax_retries?\b|\bretr(y|ies)_count\b/)

            add_finding(
              severity: :warning,
              category: :reliability,
              message: "retry with no visible attempt counter",
              line: line_no,
              suggestion: "cap retries; an unbounded retry against a persistently failing dependency is a hang, not resilience",
              file_path: file_path
            )
          end
        end

        def check_missing_timeout(code, file_path)
          return unless code.match?(/Net::HTTP|HTTParty|Faraday/)
          return if code.match?(/timeout|read_timeout|open_timeout/i)

          add_finding(
            severity: :warning,
            category: :reliability,
            message: "HTTP client usage with no visible timeout",
            line: 1,
            suggestion: "a hung dependency without a timeout hangs everything waiting on it",
            file_path: file_path
          )
        end
      end
    end
  end
end
