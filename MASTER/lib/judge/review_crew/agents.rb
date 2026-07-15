# frozen_string_literal: true

module Master
  module Judge
    class ReviewCrew
      Finding = Struct.new(:agent, :severity, :category, :message, :line, :suggestion, :file, keyword_init: true) do
        def to_h
          {
            agent: agent,
            severity: severity,
            category: category,
            message: message,
            line: line,
            suggestion: suggestion,
            file: file,
          }.compact
        end
      end

      class BaseAgent
        attr_reader :name, :findings

        def initialize(name:)
          @name = name
          @findings = []
        end

        def analyze(code, file_path)
          raise NotImplementedError, "#{self.class}#analyze not implemented"
        end

        def add_finding(severity:, category:, message:, line:, suggestion:, file_path:)
          @findings << Finding.new(
            agent: name,
            severity: severity,
            category: category,
            message: message,
            line: line,
            suggestion: suggestion,
            file: file_path
          )
        end
      end

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

      class PerformanceAgent < BaseAgent
        def initialize
          super(name: "PerformanceAgent")
        end

        def analyze(code, file_path)
          lines = code.lines
          check_file_length(lines, file_path)
          check_long_lines(lines, file_path)
          findings
        end

        private

        def check_file_length(lines, file_path)
          return unless lines.size > 300

          add_finding(
            severity: :warning,
            category: :performance,
            message: "file is #{lines.size} lines",
            line: 1,
            suggestion: "split the file at responsibility boundaries",
            file_path: file_path
          )
        end

        def check_long_lines(lines, file_path)
          lines.each_with_index do |line, idx|
            next if line.length <= 120

            add_finding(
              severity: :info,
              category: :performance,
              message: "line #{line.chomp.length} chars",
              line: idx + 1,
              suggestion: "wrap the line or extract a helper",
              file_path: file_path
            )
          end
        end
      end

      class StyleAgent < BaseAgent
        def initialize
          super(name: "StyleAgent")
        end

        def analyze(code, file_path)
          code.each_line.with_index(1) do |line, line_no|
            check_trailing_whitespace(line, line_no, file_path)
            check_important_usage(line, line_no, file_path)
          end
          findings
        end

        private

        def check_trailing_whitespace(line, line_no, file_path)
          return unless line.match?(/[ \t]+\n?\z/)

          add_finding(
            severity: :info,
            category: :style,
            message: "trailing whitespace",
            line: line_no,
            suggestion: "trim trailing spaces",
            file_path: file_path
          )
        end

        def check_important_usage(line, line_no, file_path)
          return unless line.match?(/!\s*important\b/)

          add_finding(
            severity: :warning,
            category: :style,
            message: "!important used",
            line: line_no,
            suggestion: "prefer cascade and specificity",
            file_path: file_path
          )
        end
      end

      class ArchitectureAgent < BaseAgent
        def initialize(root:, code_index: nil, reference_graph: nil)
          super(name: "ArchitectureAgent")
          @root = root
          @code_index = code_index
          @reference_graph = reference_graph
          @cycle_reported = false
        end

        def analyze(code, file_path)
          check_many_public_methods(code, file_path)
          check_ghost_smell(code, file_path)
          check_cyclic_dependency(code, file_path)
          check_message_chain(code, file_path)
          findings
        end

        private

        def check_many_public_methods(code, file_path)
          count = code.each_line.count
          return unless count > 10 && code.scan(/^\s*def\s+/).size > 10

          add_finding(
            severity: :warning,
            category: :architecture,
            message: "many public methods detected",
            line: 1,
            suggestion: "split into smaller collaborating objects",
            file_path: file_path
          )
        end

        def check_ghost_smell(code, file_path)
          return unless ghost_smell?(code)

          add_finding(
            severity: :warning,
            category: :architecture,
            message: "ghost smell detected: guard clause may be hiding a missing abstraction",
            line: 1,
            suggestion: "look for repeated branching that wants a shared object or explicit policy",
            file_path: file_path
          )
        end

        def check_cyclic_dependency(code, file_path)
          return if @cycle_reported

          cycle = detect_cycle
          return unless cycle

          add_finding(
            severity: :error,
            category: :architecture,
            message: "cyclic dependency detected: #{cycle.join(' -> ')}",
            line: 1,
            suggestion: "break the require chain by extracting shared code into a lower-level module",
            file_path: file_path
          )
          @cycle_reported = true
        end

        def check_message_chain(code, file_path)
          return unless code.match?(/\b[a-z_]+(\.[a-z_]+){3,}\b/)

          add_finding(
            severity: :warning,
            category: :architecture,
            message: "message chain detected",
            line: 1,
            suggestion: "introduce a local variable or delegation",
            file_path: file_path
          )
        end

        def detect_cycle
          return unless @reference_graph

          graph = @reference_graph.build
          edges = Array(graph[:edges]).select { |edge| edge[:type].to_s == "require" }
          adjacency = Hash.new { |hash, key| hash[key] = [] }
          edges.each { |edge| adjacency[edge[:from]] << edge[:to] }

          visited = {}
          stack = []

          adjacency.keys.each do |node|
            cycle = visit_node(node, adjacency:, visited:, stack:)
            return cycle if cycle
          end
          nil
        rescue StandardError
          nil
        end

        def ghost_smell?(code)
          return false unless code.match?(/\breturn\s+(?:if|unless)\b/)

          method_count = code.scan(/^\s*def\s+/).size
          branch_count = code.scan(/^\s*(if|unless|case|when)\b/).size
          repeated_guards = code.scan(/\breturn\s+(?:if|unless)\b/).size
          method_count >= 4 && branch_count >= 4 && repeated_guards >= 2
        end

        def visit_node(node, adjacency:, visited:, stack:)
          return if visited[node]
          visited[node] = true
          stack << node

          Array(adjacency[node]).each do |child|
            if stack.include?(child)
              idx = stack.index(child) || 0
              return stack[idx..] + [child]
            end
            cycle = visit_node(child, adjacency:, visited:, stack:)
            return cycle if cycle
          end

          stack.pop
          nil
        end
      end
    end
  end
end
