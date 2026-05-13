# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class CommentQualityRule < Rule
        TODO_NO_REF      = /^\s*#\s*TODO(?!.*[:(#@])/.freeze
        FIXME_NO_REF     = /^\s*#\s*FIXME(?!.*[:(#@])/.freeze
        CODE_LINE_RE     = /(?:def |end\b|=\s|\.call|if |unless |return |@@|@\w+ =)/.freeze
        MIN_CODE_COMMENTS = 3

        def initialize
          super
          @id          = "comment_quality"
          @description = "Low-quality comments — TODO without ref, commented-out code"
          @severity    = :style
          @rule_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          line_findings = []
          lines = code.lines

          lines.each_with_index do |line, i|
            num = i + 1
            line_findings << finding(line: num, 
message: "TODO without owner or issue ref — add TODO(name) or TODO(#123)") if line.match?(TODO_NO_REF)
            line_findings << finding(line: num, 
message: "FIXME without owner or issue ref — add FIXME(name)") if line.match?(FIXME_NO_REF)
          end

          line_findings + commented_out_blocks(lines)
        end

        private

        def commented_out_blocks(lines)
          findings  = []
          run_start = nil
          run_count = 0

          lines.each_with_index do |line, i|
            stripped = line.strip
            if stripped.start_with?("#") && CODE_LINE_RE.match?(stripped[1..].to_s)
              run_start ||= i + 1
              run_count  += 1
            else
              if run_count >= MIN_CODE_COMMENTS
                findings << finding(line: run_start, 
message: "#{run_count} consecutive lines of commented-out code — delete it, git history preserves it")
              end
              run_start = nil
              run_count = 0
            end
          end

          if run_count >= MIN_CODE_COMMENTS
            findings << finding(line: run_start, 
message: "#{run_count} consecutive lines of commented-out code — delete it, git history preserves it")
          end

          findings
        end
      end
    end
  end
  end
end
