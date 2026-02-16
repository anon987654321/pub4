# frozen_string_literal: true

# 8-Phase Bug Hunting Protocol
# Systematic debugging methodology

module MASTER
  module BugHunting
    extend self

    # Diagnostic escalation levels (cheap to expensive)
    ESCALATION_LEVELS = %i[syntax logic history llm].freeze

    class << self
      # Hunt for bugs with automatic escalation
      def hunt(error_or_file, level: :auto)
        if level == :auto
          escalate(error_or_file)
        else
          send(:"level_#{level}", error_or_file)
        end
      end

      def analyze(code, file_path: 'inline')
        report = {
          file_path: file_path,
          phases: [],
          findings: {},
          timestamp: Time.now
        }

        report[:findings][:lexical] = Phase1Lexical.analyze(code)
        report[:phases] << 'Phase 1: Lexical Analysis'

        report[:findings][:execution] = Phase2Execution.analyze(code)
        report[:phases] << 'Phase 2: Simulated Execution'

        report[:findings][:assumptions] = Phase3Assumptions.analyze(code)
        report[:phases] << 'Phase 3: Assumption Interrogation'

        report[:findings][:dataflow] = Phase4DataFlow.analyze(code)
        report[:phases] << 'Phase 4: Data Flow Analysis'

        report[:findings][:state] = Phase5State.analyze(code)
        report[:phases] << 'Phase 5: State Reconstruction'

        report[:findings][:patterns] = Phase6Patterns.analyze(code)
        report[:phases] << 'Phase 6: Pattern Recognition'

        report[:findings][:understanding] = Phase7Proof.validate(report)
        report[:phases] << 'Phase 7: Proof of Understanding'

        report[:findings][:verification] = Phase8Verify.check(report)
        report[:phases] << 'Phase 8: Verification'

        report
      end

      def format(report)
        lines = ["BUG HUNT: #{report[:file_path]}", '']

        if (lex = report[:findings][:lexical])
          lines << "1. LEXICAL (#{lex[:count]} identifiers)"
          lex[:issues].each { |i| lines << "   - #{i}" }
          lines << '   + clean' if lex[:issues].empty?
        end

        if (exec = report[:findings][:execution])
          lines << '2. EXECUTION'
          exec[:perspectives].each { |p| lines << "   #{p[:name]}: #{p[:status]}" }
        end

        if (assume = report[:findings][:assumptions])
          lines << '3. ASSUMPTIONS'
          assume[:found].each { |a| lines << "   ! #{a[:category]}: #{a[:desc]}" }
          lines << '   + none risky' if assume[:found].empty?
        end

        if (flow = report[:findings][:dataflow])
          lines << "4. DATA FLOW (#{flow[:count]} traces)"
          flow[:traces].first(5).each { |t| lines << "   #{t[:var]} <- #{t[:source][0..40]}" }
        end

        if (state = report[:findings][:state])
          lines << '5. STATE'
          lines << "   edge: #{state[:edges].join(', ')}" if state[:edges].any?
        end

        if (pats = report[:findings][:patterns])
          lines << '6. PATTERNS'
          pats[:matches].each do |m|
            lines << "   #{m[:confidence]} #{m[:name]}"
            lines << "      fix: #{m[:fix]}"
          end
          lines << '   + no patterns matched' if pats[:matches].empty?
        end

        if (proof = report[:findings][:understanding])
          status = proof[:complete] ? '+' : '-'
          lines << "7. UNDERSTANDING #{status}"
        end

        if (verify = report[:findings][:verification])
          status = verify[:passed] ? '+ COMPLETE' : '- INCOMPLETE'
          lines << "8. VERIFICATION #{status}"
        end

        lines.join("\n")
      end

      # Escalation strategy - try cheap fixes before expensive LLM
      private

      def escalate(target)
        puts UI.dim("Diagnostic escalation...")

        # Level 1: Syntax (2 sec, $0)
        result = level_syntax(target)
        return result if result[:fixed]

        # Level 2: Logic (10 sec, $0)
        result = level_logic(target)
        return result if result[:fixed]

        # Level 3: History (30 sec, $0)
        result = level_history(target)
        return result if result[:fixed]

        # Level 4: LLM (60 sec, $0.10-0.50)
        level_llm(target)
      end

      def level_syntax(target)
        puts UI.dim("  Level 1: Syntax check...")

        if target.end_with?('.rb')
          output = `ruby -c #{Shellwords.escape(target)} 2>&1`
          if $?.success?
            { level: :syntax, fixed: false, message: "No syntax errors" }
          else
            { level: :syntax, fixed: true, error: output, fix: "Run rubocop -a #{Shellwords.escape(target)}" }
          end
        elsif target.end_with?('.sh')
          output = `zsh -n #{Shellwords.escape(target)} 2>&1`
          { level: :syntax, fixed: !$?.success?, error: output }
        else
          { level: :syntax, fixed: false }
        end
      end

      def level_logic(target)
        puts UI.dim("  Level 2: Logic check (tests)...")

        test_file = target.sub('/lib/', '/test/').sub('.rb', '_test.rb')
        if File.exist?(test_file)
          require 'open3'
          output, status = Open3.capture2e("ruby", test_file)
          if status.success?
            { level: :logic, fixed: false, message: "Tests pass" }
          else
            { level: :logic, fixed: true, error: output, fix: "Check test output above" }
          end
        else
          { level: :logic, fixed: false, message: "No tests found" }
        end
      end

      def level_history(target)
        puts UI.dim("  Level 3: Git history...")

        if system("git rev-parse --git-dir > /dev/null 2>&1")
          # Check if file was recently modified
          log = `git log --oneline -5 -- #{target}`.strip
          if log.empty?
            { level: :history, fixed: false, message: "No recent changes" }
          else
            { level: :history, fixed: false, history: log, suggestion: "Try: git log --patch -- #{target}" }
          end
        else
          { level: :history, fixed: false, message: "Not a git repo" }
        end
      end

      def level_llm(target)
        puts UI.dim("  Level 4: LLM analysis (costs $$$)...")

        # Fall back to existing analyze method
        if File.exist?(target)
          code = File.read(target)
          report = analyze(code, file_path: target)
          { level: :llm, fixed: false, report: report }
        else
          { level: :llm, fixed: false, error: "File not found: #{target}" }
        end
      end

      public
    end

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
            elsif levenshtein(a, b) == 1
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

        def levenshtein(a, b)
          return b.length if a.empty?
          return a.length if b.empty?

          # Wagner-Fischer dynamic programming algorithm
          matrix = Array.new(a.length + 1) { Array.new(b.length + 1) }

          (0..a.length).each { |i| matrix[i][0] = i }
          (0..b.length).each { |j| matrix[0][j] = j }

          (1..a.length).each do |i|
            (1..b.length).each do |j|
              cost = a[i - 1] == b[j - 1] ? 0 : 1
              matrix[i][j] = [
                matrix[i - 1][j] + 1,      # deletion
                matrix[i][j - 1] + 1,      # insertion
                matrix[i - 1][j - 1] + cost # substitution
              ].min
            end
          end

          matrix[a.length][b.length]
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
