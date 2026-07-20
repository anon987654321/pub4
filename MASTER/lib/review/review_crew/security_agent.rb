# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      class SecurityAgent < BaseAgent
        SECURITY_PATTERNS = [
          [/eval\s*\(/, "eval()", "replace dynamic evaluation with a method dispatch or parser"],
          [/\bsystem\s*\(/, "system()", "prefer a dedicated helper or vetted command wrapper"],
          [/\bexec\s*\(/, "exec()", "avoid process replacement in application code"],
          [/\`[^`]+\`/, "backtick execution", "use Open3 or a command wrapper"],
          [/\bFile\.read\(([^)]*params|[^)]*request|[^)]*user)/, "File.read with user params", "validate and whitelist the target path"],
          [/\b[A-Z][A-Za-z0-9_:]*\.constantize\b/, ".constantize", "replace string constant lookup with a whitelist"],
          [/\bdynamic\s+send\s*\(|\bsend\s*\(/, "dynamic send()", "prefer explicit method calls or a whitelist"],
          [/\b(sql|execute)\b.*[#"]\{/, "SQL interpolation", "use parameterized queries"],
          [/\bhtml_safe\b/, "html_safe", "escape content or use a safe partial"],
        ].freeze

        def initialize
          super(name: "SecurityAgent")
        end

        def analyze(code, file_path)
          SECURITY_PATTERNS.each do |pattern, label, suggestion|
            code.each_line.with_index(1) do |line, line_no|
              next unless line.match?(pattern)

              add_finding(
                severity: :error,
                category: :security,
                message: "#{label} detected",
                line: line_no,
                suggestion: suggestion,
                file_path: file_path
              )
            end
          end
          findings
        end
      end
    end
  end
end
