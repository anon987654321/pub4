# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      # "remove_all" lens: flags code that exists but doesn't earn its keep --
      # complements PerformanceAgent (which flags what's slow) and
      # ArchitectureAgent (which flags what's tangled), neither of which asks
      # "does this need to exist at all."
      class MinimalistAgent < BaseAgent
        def initialize
          super(name: "MinimalistAgent")
        end

        def analyze(code, file_path)
          check_commented_out_code(code, file_path)
          check_unused_looking_param(code, file_path)
          check_single_call_wrapper(code, file_path)
          findings
        end

        private

        def check_commented_out_code(code, file_path)
          code.each_line.with_index(1) do |line, line_no|
            next unless line.match?(/^\s*#\s*(def |class |if |end\b|@\w+\s*=)/)

            add_finding(
              severity: :info,
              category: :minimalism,
              message: "commented-out code",
              line: line_no,
              suggestion: "delete it; git history remembers what removal can't",
              file_path: file_path
            )
          end
        end

        def check_unused_looking_param(code, file_path)
          code.scan(/def\s+\w+\(([^)]*)\)/).each do |(params)|
            next if params.to_s.strip.empty?

            params.split(",").map(&:strip).each do |param|
              name = param.sub(/[:=].*/, "").delete("*&").strip
              next if name.empty? || code.scan(/\b#{Regexp.escape(name)}\b/).size > 1

              add_finding(
                severity: :info,
                category: :minimalism,
                message: "parameter '#{name}' appears unused in its own method body",
                line: 1,
                suggestion: "remove it, or use it -- an unused parameter is a promise the method doesn't keep",
                file_path: file_path
              )
            end
          end
        end

        def check_single_call_wrapper(code, file_path)
          methods = code.scan(/^\s*def\s+(\w+)/).flatten
          methods.each do |name|
            callers = code.scan(/\b#{Regexp.escape(name)}\b/).size
            next unless callers == 2 # the def line + exactly one call site

            add_finding(
              severity: :info,
              category: :minimalism,
              message: "'#{name}' has exactly one call site",
              line: 1,
              suggestion: "inline it unless the name alone is carrying real documentation value",
              file_path: file_path
            )
          end
        end
      end
    end
  end
end
