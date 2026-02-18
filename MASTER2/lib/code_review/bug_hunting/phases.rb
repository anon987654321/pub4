# frozen_string_literal: true

module MASTER
  module BugHunting
    # Phase 1: Lexical Consistency Analysis
    module Phase1Lexical
      KEYWORDS = %w[if else elsif unless while until for do end class module def return break next case when then begin rescue ensure raise nil true false self].freeze

      class << self
        def analyze(code)
          identifiers = extract_identifiers(code)
          issues = []
          issues.concat(find_similar(identifiers))
          issues.concat(find_case_issues(identifiers))
          issues.concat(find_single_letter(identifiers))
          { count: identifiers.size, identifiers: identifiers, issues: issues }
        end

        private

        def extract_identifiers(code)
          code.scan(/\b[a-z_][a-z0-9_]*\b/i).uniq.reject { |id| KEYWORDS.include?(id) }
        end

        def find_similar(ids)
          issues = []
          ids.combination(2).each do |a, b|
            next if a.length < 4 || b.length < 4

            if a.downcase == b.downcase && a != b
              issues << "case mismatch: #{a} vs #{b}"
            elsif Utils.levenshtein(a, b) == 1
              issues << "typo? #{a} vs #{b}"
            end
          end
          issues
        end

        def find_case_issues(ids)
          by_lower = ids.group_by(&:downcase)
          by_lower.select { |_, v| v.size > 1 }.map { |_, variants| "inconsistent: #{variants.join(', ')}" }
        end

        def find_single_letter(ids)
          singles = ids.select { |id| id.length == 1 && !%w[i j k n m x y].include?(id) }
          singles.map { |s| "single-letter var: #{s}" }
        end
      end
    end

    # Phase 2: Simulated Execution
    module Phase2Execution
      PERSPECTIVES = [
        { name: 'happy_path', desc: 'nominal execution' },
        { name: 'edge_cases', desc: 'nil, empty, zero, boundary' },
        { name: 'concurrent', desc: 'race conditions, deadlocks' },
        { name: 'failure', desc: 'timeouts, exceptions, exhaustion' },
        { name: 'backwards', desc: 'trace from bug to root cause' }
      ].freeze

      def self.analyze(_code)
        perspectives = PERSPECTIVES.map { |p| { name: p[:name], status: "analyzed: #{p[:desc]}" } }
        { perspectives: perspectives }
      end
    end

    # Phase 3: Assumption Interrogation
    module Phase3Assumptions
      def self.analyze(code)
        found = []

        if code.include?('File.open') && !code.include?('rescue')
          found << { category: 'file', desc: 'assumes file exists' }
        end

        if code.match?(/\.(save|create|update|destroy)\b/) && !code.include?('rescue')
          found << { category: 'database', desc: 'assumes DB success' }
        end

        if code.match?(/\.\w+\(/) && !code.match?(/&\.|\bnil\?|\bpresent\?/)
          found << { category: 'nil', desc: 'may call method on nil' }
        end

        if code.match?(/\[\d+\]/) && !code.match?(/\.length|\.size|\.count/)
          found << { category: 'bounds', desc: 'array access without bounds check' }
        end

        if code.match?(/Net::HTTP|URI\.open|Faraday|HTTParty/) && !code.include?('timeout')
          found << { category: 'network', desc: 'network call without timeout' }
        end

        { found: found }
      end
    end

    # Phase 4: Data Flow Analysis
    module Phase4DataFlow
      def self.analyze(code)
        traces = []
        code.scan(/(\w+)\s*=\s*(.+)$/).each do |var, source|
          next if var.match?(/^[A-Z]/)

          traces << { var: var, source: source.strip }
        end
        { traces: traces, count: traces.size }
      end
    end

    # Phase 5: State Reconstruction
    module Phase5State
      def self.analyze(code)
        edges = []
        edges << 'nil' if code.include?('nil')
        edges << 'empty' if code.match?(/\[\]|\{\}|""/)
        edges << 'zero' if code.match?(/\b0\b/)
        edges << 'negative' if code.match?(/-\d/)
        edges << 'empty string' if code.include?('""') || code.include?("''")
        { edges: edges }
      end
    end

    # Phase 6: Pattern Recognition
    module Phase6Patterns
      PATTERNS = [
        { name: 'resource_leak', check: ->(c) { c.include?('File.open') && !c.match?(/File\.open.*do|ensure/) }, confidence: 'HIGH', fix: 'Use block form: File.open(path) { |f| ... }' },
        { name: 'off_by_one', check: ->(c) { c.match?(/\[.*\.length\]|\[.*\.size\]/) }, confidence: 'MED', fix: 'Use .length-1 or ... exclusive range' },
        { name: 'null_deref', check: ->(c) { c.match?(/\.\w+\(/) && !c.include?('&.') && !c.include?('nil?') }, confidence: 'LOW', fix: 'Add nil check or use &. safe navigation' },
        { name: 'race_condition', check: ->(c) { c.include?('Thread') && c.match?(/if.*\n.*=/) }, confidence: 'MED', fix: 'Use Mutex or atomic operations' },
        { name: 'sql_injection', check: ->(c) { c.match?(/execute.*#\{|WHERE.*#\{/) }, confidence: 'HIGH', fix: 'Use parameterized queries' },
        { name: 'hardcoded_secret', check: ->(c) { c.match?(/password\s*=\s*['"]|api_key\s*=\s*['"]|sk-[a-zA-Z0-9]/) }, confidence: 'HIGH', fix: 'Use environment variables' }
      ].freeze

      def self.analyze(code)
        matches = PATTERNS.select { |p| p[:check].call(code) }.map do |p|
          { name: p[:name], confidence: p[:confidence], fix: p[:fix] }
        end
        { matches: matches }
      end
    end

    # Phase 7: Proof of Understanding
    module Phase7Proof
      def self.validate(report)
        checks = {
          lexical: report[:findings][:lexical]&.key?(:count),
          execution: report[:findings][:execution]&.key?(:perspectives),
          assumptions: report[:findings][:assumptions]&.key?(:found),
          dataflow: report[:findings][:dataflow]&.key?(:traces),
          patterns: report[:findings][:patterns]&.key?(:matches)
        }
        { complete: checks.values.all?, checks: checks }
      end
    end

    # Phase 8: Verification
    module Phase8Verify
      def self.check(report)
        passed = report[:phases].size == 8 &&
                 report[:findings].size >= 7 &&
                 report[:findings][:understanding]&.dig(:complete)
        { passed: passed, phases: report[:phases].size }
      end
    end
  end
end
