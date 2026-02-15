# frozen_string_literal: true

require 'yaml'

module MASTER
  # Analysis - Situational awareness and introspection
  # Consolidates Prescan and Introspection modules
  module Analysis
    # Prescan - Mandatory situational awareness before touching code
    # Ported from MASTER v1 cli.rb prescan ritual
    module Prescan
      extend self

      def run(path = MASTER.root)
        puts UI.bold("\n🔍 Prescan")
        puts UI.dim("Understanding codebase state before proceeding...\n")

        results = {
          tree: show_tree(path),
          sprawl: detect_sprawl(path),
          git_status: check_git_status(path),
          recent_commits: show_recent_commits(path)
        }

        warn_if_issues(results)
        results
      end

      private

      def show_tree(path)
        puts UI.dim("Structure:")

        # Ruby-native tree walker - no system dependencies
        tree = file_tree(path, max_depth: 3, exclude: %w[. .. .git vendor tmp node_modules var])
        puts tree.join("\n")
        true
      end

      # Ruby-native tree walker
      def file_tree(root, indent: "", max_depth: 3, depth: 0, exclude: [])
        return [] if depth >= max_depth

        entries = Dir.children(root).sort.reject { |e| exclude.include?(e) }
        lines = []

        entries.each_with_index do |entry, i|
          path = File.join(root, entry)
          last = i == entries.size - 1
          connector = last ? "└── " : "├── "
          lines << "#{indent}#{connector}#{entry}"

          if File.directory?(path)
            extension = last ? "    " : "│   "
            lines.concat(file_tree(path, indent: "#{indent}#{extension}", max_depth: max_depth, depth: depth + 1, exclude: exclude))
          end
        end

        lines
      end

      def detect_sprawl(path)
        large_files = []

        Dir.glob(File.join(path, "**", "*.rb")).each do |file|
          lines = File.readlines(file).size
          if lines > 500
            large_files << { file: file, lines: lines }
          end
        end

        if large_files.any?
          puts UI.yellow("\n⚠️  Sprawl detected (#{large_files.size} files > 500 lines):")
          large_files.first(5).each do |f|
            puts "  #{File.basename(f[:file])}: #{f[:lines]} lines"
          end
        end

        large_files
      end

      def check_git_status(path)
        return nil unless system("git", "-C", path, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

        status = `git -C #{Shellwords.escape(path)} status --porcelain`.strip

        if status.empty?
          puts UI.green("\n✓ Git: Clean working tree")
        else
          puts UI.yellow("\n⚠️  Git: Uncommitted changes:")
          puts status.lines.first(5).map { |l| "  #{l}" }
        end

        status
      end

      def show_recent_commits(path)
        return nil unless system("git -C #{path} rev-parse --git-dir > /dev/null 2>&1")

        puts UI.dim("\nRecent commits:")
        system("git", "-C", path, "log", "--oneline", "--decorate", "-5")

        true
      end

      def warn_if_issues(results)
        warnings = []

        warnings << "Large files detected" if results[:sprawl]&.any?
        warnings << "Uncommitted changes" if results[:git_status] && !results[:git_status].empty?

        if warnings.any?
          puts UI.yellow("\n⚠️  Issues: #{warnings.join(', ')}")
          puts UI.dim("Consider addressing these before proceeding.\n")
        else
          puts UI.green("\n✓ All clear\n")
        end
      end
    end

    # Introspection - Unified self-awareness and introspection module
    # Consolidates: SelfMap, SelfCritique, SelfRepair, SelfTest, and adversarial questioning
    # ALL code piped through MASTER2 gets the same hostile treatment
    # Whether self or user code, everything is questioned equally
    class Introspection
      class << self
        # ═══════════════════════════════════════════════════════════════════
        # SECTION 1: Structure Mapping (from self_map.rb)
        # ═══════════════════════════════════════════════════════════════════

        IGNORED = %w[.git node_modules vendor tmp log .bundle].freeze

        # Generate summary of MASTER's structure for boot display
        # @return [String] Brief summary "X lib, Y test"
        def summary(root = MASTER.root)
          map = generate_map(root)
          "#{map[:lib_files].count} lib, #{map[:test_files].count} test"
        rescue StandardError
          "unavailable"
        end

        # Generate complete map of MASTER's structure
        # @return [Hash] Structure map with files, ruby_files, lib_files, test_files
        def generate_map(root = MASTER.root)
          {
            files: collect_files(root, root),
            ruby_files: collect_files(root, root).select { |f| f.end_with?(".rb") },
            lib_files: collect_files(root, root).select { |f| f.include?("/lib/") && f.end_with?(".rb") },
            test_files: collect_files(root, root).select { |f| (f.include?("/test/") || f.include?("_test.rb") || f.include?("test_")) && f.end_with?(".rb") }
          }
        end

        # Generate tree string representation of directory
        # @param dir [String] Directory to scan
        # @param prefix [String] Prefix for indentation
        # @return [String] Tree representation
        def tree_string(dir = MASTER.root, prefix = "")
          result = []
          entries = Dir.entries(dir).sort.reject { |e| e.start_with?(".") || IGNORED.include?(e) }

          entries.each_with_index do |entry, idx|
            path = File.join(dir, entry)
            is_dir = File.directory?(path)

            # Only append slash for directories
            result << "#{prefix}#{entry}#{is_dir ? '/' : ''}"

            if is_dir
              result << tree_string(path, "#{prefix}  ")
            end
          end

          result.join("\n")
        end

        # ═══════════════════════════════════════════════════════════════════
        # SECTION 2: Self-Critique (from self_critique.rb)
        # ═══════════════════════════════════════════════════════════════════

        CONFIDENCE_THRESHOLD = 0.6
        MAX_RETRIES = 3

        # LLM evaluates its own work with confidence scoring
        # @param task [String] The task description
        # @param response [String] The response to critique
        # @param llm [Object] LLM instance
        # @param tier [Symbol] Tier to use (:cheap, :fast, :smart, :genius)
        # @return [Hash] Critique with scores and suggestions
        def critique_response(task:, response:, llm:, tier: :cheap)
          prompt = <<~PROMPT
            You are evaluating your own work. Be brutally honest.

            Task: #{task}

            Your response: #{response[0..2000]}

            Rate this response on:
            1. Correctness (0-1): Does it solve the task?
            2. Completeness (0-1): Does it address all aspects?
            3. Clarity (0-1): Is it clear and well-structured?

            Return ONLY valid JSON:
            {
              "correctness": 0.0-1.0,
              "completeness": 0.0-1.0,
              "clarity": 0.0-1.0,
              "overall_confidence": 0.0-1.0,
              "issues": ["issue1", "issue2"],
              "suggestions": ["suggestion1", "suggestion2"]
            }
          PROMPT

          result = llm.ask(prompt, tier: tier)
          return default_critique unless result.ok?

          parse_critique(result.value)
        end

        # Check if response should be retried based on confidence
        # @param critique [Hash] Critique hash
        # @return [Boolean] True if should retry
        def should_retry?(critique)
          return false unless critique

          critique[:overall_confidence] < CONFIDENCE_THRESHOLD
        end

        # Extract strength score from critique
        # @param critique [Hash] Critique hash
        # @return [Float] Weighted strength score 0.0-1.0
        def extract_strength(critique)
          return 0.5 unless critique

          weights = { correctness: 0.4, completeness: 0.3, clarity: 0.3 }

          weighted_sum = weights.sum do |key, weight|
            (critique[key] || 0.5) * weight
          end

          weighted_sum.clamp(0.0, 1.0)
        end

        # ═══════════════════════════════════════════════════════════════════
        # SECTION 3: Self-Repair (from self_repair.rb)
        # ═══════════════════════════════════════════════════════════════════

        # Full repair pipeline with audit → confirm → fix → test → learn
        # @param files [String, Array<String>] File(s) to repair
        # @param dry_run [Boolean] Preview changes without writing
        # @param auto_confirm [Boolean] Skip confirmation gates
        # @return [Result] Ok with repair summary or Err
        def repair(files, dry_run: true, auto_confirm: false)
          files = [files] unless files.is_a?(Array)

          repaired = 0
          failed = 0
          skipped = 0

          # Step 1: Audit scan
          audit_result = if defined?(Audit)
            Audit.scan(files)
          else
            return Result.err("Audit module not available")
          end

          return audit_result unless audit_result.ok?

          report = audit_result.value[:report]
          findings = report.prioritized

          UI.dim("  🔍 Found #{findings.size} issues") if defined?(UI)

          # Step 2: Process each finding
          findings.each do |finding|
            # Skip if dry_run
            if dry_run
              UI.dim("  [DRY RUN] Would repair: #{finding.message}") if defined?(UI)
              skipped += 1
              next
            end

            # Step 3: Confirmation gate (unless auto_confirm)
            unless auto_confirm
              if defined?(ConfirmationGate)
                gate_result = ConfirmationGate.gate(
                  "Repair #{finding.category}",
                  description: finding.message
                ) { true }

                unless gate_result.ok?
                  skipped += 1
                  next
                end
              end
            end

            # Step 4: Attempt fix
            fix_result = attempt_fix(finding)

            if fix_result.ok?
              # Step 5: Run self-test if available
              if respond_to?(:run)
                test_result = run
                unless test_result.ok?
                  # Rollback on test failure
                  rollback_fix(finding)
                  failed += 1

                  # Record failure
                  record_learning(finding, fix_result.value, success: false)
                  next
                end
              end

              repaired += 1

              # Step 6: Record success
              record_learning(finding, fix_result.value, success: true)
            else
              failed += 1
              skipped += 1 if fix_result.error.include?("not available")
            end
          end

          Result.ok(
            repaired: repaired,
            failed: failed,
            skipped: skipped,
            total: findings.size
          )
        end

        require_relative 'introspection/self_map'
      end

      # Instance methods for LLM-based introspection
      def initialize(llm: LLM)
        @llm = llm
      end

      def reflect_on_phase(phase, summary)
        reflection = self.class.phase_reflections[phase.to_sym]
        return nil unless reflection

        prompt = <<~PROMPT
          Phase completed: #{phase.upcase}
          Summary: #{summary}

          Reflect: #{reflection}
          Be specific. Name concrete issues, not platitudes.
          One paragraph maximum.
        PROMPT

        result = @llm.ask(prompt, stream: false)
        result.ok? ? result.value[:content] : "Reflection failed: #{result.failure}"
      end

      def hostile_question(content, context = nil)
        question = self.class.hostile_questions.sample

        prompt = <<~PROMPT
          CONTENT TO REVIEW:
          #{content[0, 2000]}
          #{"CONTEXT: #{context}" if context}

          HOSTILE QUESTION: #{question}

          If you find a genuine issue, respond:
          ISSUE: [one-line description]
          WHY: [one sentence explanation]

          If no issue found, respond:
          PASS
        PROMPT

        result = @llm.ask(prompt, stream: false)
        return nil unless result.ok?

        response = result.value[:content].to_s
        if response.include?("ISSUE:")
          {
            question: question,
            issue: response[/ISSUE:\s*(.+)/, 1],
            why: response[/WHY:\s*(.+)/, 1],
          }
        else
          nil
        end
      end

      def examine(code, filename: nil)
        prompt = <<~PROMPT
          Examine this code as a hostile reviewer.
          #{"FILE: #{filename}" if filename}

          ```
          #{code[0, 4000]}
          ```

          Answer each briefly (one line each):
          1. WORST BUG: What's the worst bug hiding here?
          2. CURSE: What will the next developer curse you for?
          3. DELETE: What would you delete entirely?
          4. MISSING: What's missing that should be obvious?
          5. VERDICT: APPROVE or REJECT (one word)
        PROMPT

        result = @llm.ask(prompt, stream: false)
        return { error: result.failure } unless result.ok?

        content = result.value[:content].to_s
        {
          worst_bug: content[/WORST BUG:\s*(.+)/, 1],
          curse: content[/CURSE:\s*(.+)/, 1],
          delete: content[/DELETE:\s*(.+)/, 1],
          missing: content[/MISSING:\s*(.+)/, 1],
          verdict: content[/VERDICT:\s*(\w+)/, 1]&.upcase,
          passed: content.include?("APPROVE"),
        }
      end

      private

      class << self
        private

        # ═══════════════════════════════════════════════════════════════════
        # PRIVATE HELPERS - Section 1 (SelfMap)
        # ═══════════════════════════════════════════════════════════════════

        def collect_files(dir, root = dir)
          result = []

          Dir.entries(dir).each do |entry|
            next if entry.start_with?(".") || IGNORED.include?(entry)

            path = File.join(dir, entry)
            if File.directory?(path)
              result.concat(collect_files(path, root))
            else
              result << path.sub("#{root}/", "")
            end
          end

          result
        end

        # ═══════════════════════════════════════════════════════════════════
        # PRIVATE HELPERS - Section 2 (SelfCritique)
        # ═══════════════════════════════════════════════════════════════════

        def parse_critique(text)
          json_match = text.match(/\{[^{}]*\}/m)
          return default_critique unless json_match

          parsed = JSON.parse(json_match[0], symbolize_names: true)

          {
            correctness: parsed[:correctness]&.to_f || 0.5,
            completeness: parsed[:completeness]&.to_f || 0.5,
            clarity: parsed[:clarity]&.to_f || 0.5,
            overall_confidence: parsed[:overall_confidence]&.to_f || 0.5,
            issues: Array(parsed[:issues]),
            suggestions: Array(parsed[:suggestions])
          }
        rescue JSON::ParserError
          default_critique
        end

        def default_critique
          {
            correctness: 0.5,
            completeness: 0.5,
            clarity: 0.5,
            overall_confidence: 0.5,
            issues: ['Unable to parse self-critique'],
            suggestions: []
          }
        end

        # ═══════════════════════════════════════════════════════════════════
        # PRIVATE HELPERS - Section 3 (SelfRepair)
        # ═══════════════════════════════════════════════════════════════════

        def attempt_fix(finding)
          # Try AutoFixer if available
          if defined?(AutoFixer)
            fixer = AutoFixer.new(mode: :moderate)

            if File.exist?(finding.file)
              result = fixer.fix(finding.file)
              return result if result.ok?
            end
          end

          # Try known fix from learning
          if defined?(LearningFeedback)
            if LearningFeedback.known_fix?(finding)
              return LearningFeedback.apply_known(finding)
            end
          end

          Result.err("No fix available for this finding")
        end

        def rollback_fix(finding)
          # Use Staging rollback if available
          if defined?(Staging)
            staging = Staging.new
            staging.rollback(finding.file)
          end
        end

        def record_learning(finding, fix, success:)
          # Record pattern in learning feedback
          if defined?(LearningFeedback)
            LearningFeedback.record(finding, fix, success: success)
          end
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BACKWARD COMPATIBILITY ALIASES
  # ═══════════════════════════════════════════════════════════════════

  Prescan = Analysis::Prescan
  Introspection = Analysis::Introspection
  SelfMap = Analysis::Introspection
  SelfCritique = Analysis::Introspection
  SelfRepair = Analysis::Introspection
  SelfTest = Analysis::Introspection
end
