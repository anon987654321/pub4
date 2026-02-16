# frozen_string_literal: true

# 8-Phase Bug Hunting Protocol
# Systematic debugging methodology

require_relative 'bug_hunting/phases'

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
  end
end
