# frozen_string_literal: true

require 'yaml'

module MASTER
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
          files: collect_files(root),
          ruby_files: collect_files(root).select { |f| f.end_with?(".rb") },
          lib_files: collect_files(root).select { |f| f.include?("/lib/") && f.end_with?(".rb") },
          test_files: collect_files(root).select { |f| (f.include?("/test/") || f.include?("_test.rb") || f.include?("test_")) && f.end_with?(".rb") }
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
            if defined?(SelfTest)
              test_result = SelfTest.run
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
      
      # ═══════════════════════════════════════════════════════════════════
      # SECTION 4: Self-Test (from self_test.rb)
      # ═══════════════════════════════════════════════════════════════════
      
      BARE_RESCUE_ALLOWED = %w[
        result.rb boot.rb autocomplete.rb speech.rb momentum.rb weaviate.rb
      ].freeze
      
      # Run comprehensive self-tests on MASTER
      # @return [Result] Ok with test results or Err
      def run
        print "Running self-test"
        
        # Collect all results silently
        results = {}
        
        print "."
        results[:static_analysis] = run_static_analysis
        print "."
        results[:consistency_checks] = run_consistency_checks
        print "."
        results[:enforcement] = run_enforcement
        print "."
        results[:logic_checks] = run_logic_checks
        print "."
        results[:introspection] = run_introspection
        print "."
        results[:file_processing] = run_file_processing
        print "."
        results[:pipeline_safety] = run_pipeline_test
        print "."
        results[:council_review] = run_council_review
        puts " done.\n\n"

        # Output prose summary
        print_prose_summary(results)
        Result.ok(results)
      end
      
      # Test methods for self-test
      def run_static_analysis
        total_issues = 0
        each_lib_file do |code, filename|
          result = CodeReview.analyze(code, filename: filename)
          total_issues += (result[:issues] || []).size
        end

        {
          passed: total_issues < MASTER::QualityStandards.max_self_test_issues,
          message: "#{lib_files.size} files, #{total_issues} issues",
          issues: total_issues,
        }
      end
      
      def run_consistency_checks
        files = lib_files
        issues = []

        files.each do |file|
          content = File.read(file)
          basename = File.basename(file)
          issues.concat(check_error_message_format(content, basename))
          issues.concat(check_exception_handling(content, basename))
        end

        {
          passed: issues.size < 5,
          message: "#{issues.size} consistency issues",
          issues: issues,
        }
      end
      
      def run_enforcement
        all_violations = []
        each_lib_file do |code, filename|
          result = Enforcement.check(code, filename: filename)
          all_violations.concat(result[:violations] || [])
        end

        {
          passed: all_violations.size < MASTER::QualityStandards.max_self_test_violations,
          message: "#{all_violations.size} violations across 5 layers",
          violations: all_violations,
        }
      end
      
      def run_logic_checks
        files = lib_files
        issues = []

        files.each do |file|
          content = File.read(file)
          basename = File.basename(file)
          issues.concat(check_logic_patterns(content, basename))
        end

        {
          passed: issues.size < 3,
          message: "#{issues.size} logic issues",
          issues: issues,
        }
      end
      
      def run_introspection
        all_issues = []
        lib_files.first(10).each do |file|
          code = File.read(file)
          result = interrogate(code, context: { filename: File.basename(file) })
          all_issues.concat(result[:issues] || [])
        end

        {
          passed: all_issues.size < 20,
          message: "#{all_issues.size} adversarial issues found",
          issues: all_issues,
          severity: all_issues.size >= 10 ? :high : :medium,
        }
      end
      
      def run_file_processing
        result = FileProcessor.process_directory(File.join(MASTER.root, "lib"), dry_run: true)
        changes_needed = result[:files_changed]

        {
          passed: changes_needed < 5,
          message: "#{changes_needed} files need processing",
          details: result,
        }
      end
      
      def run_pipeline_test
        pipeline = Pipeline.new(stages: %i[intake compress guard])
        sample = File.read(File.join(MASTER.root, "lib", "master.rb"))[0, 500]
        result = pipeline.call({ text: "Review: #{sample}" })

        {
          passed: result.ok?,
          message: result.ok? ? "Pipeline accepts own code" : "Rejected: #{result.failure}",
        }
      end
      
      def run_council_review
        # Build code sample from key files
        key_files = %w[master.rb pipeline.rb stages.rb llm.rb chamber.rb executor.rb commands.rb enforcement.rb introspection.rb]
        code_sample = key_files.map do |f|
          path = File.join(MASTER.root, "lib", f)
          next unless File.exist?(path)
          "# #{f}\n#{File.read(path)[0, 4000]}"
        end.compact.join("\n\n---\n\n")

        axiom_list = DB.axioms.map { |a| "- #{a[:name] || a[:id]}" }.join("\n")

        prompt = <<~PROMPT
          You are MASTER v#{VERSION}, reviewing your own source.
          
          AXIOMS: #{axiom_list}
          
          Review this code against axioms. Rate self-alignment 1-10.
          Be brutally honest.
          
          CODE:
          #{code_sample[0, 12_000]}
        PROMPT

        result = LLM.ask(prompt, stream: false)

        if result.ok?
          response = result.value[:content].to_s
          rating_match = response.match(/(\d+)\s*\/\s*10|rating[:\s]+(\d+)/i)
          rating = rating_match ? (rating_match[1] || rating_match[2]).to_i : 5

          puts "\n    Rating: #{rating}/10"

          {
            passed: rating >= 7,
            message: "Council rated #{rating}/10",
            rating: rating,
          }
        else
          { passed: false, message: "LLM error: #{result.failure}" }
        end
      rescue StandardError => e
        { passed: false, message: "Failed: #{e.message}" }
      end
      
      def print_prose_summary(results)
        passed = results.values.count { |r| r[:passed] }
        total = results.size
        
        static = results[:static_analysis]
        consistency = results[:consistency_checks]
        enforcement = results[:enforcement]
        logic = results[:logic_checks]
        introspection_result = results[:introspection]
        council = results[:council_review]
        
        # Build natural prose
        paragraphs = []
        
        # Opening
        if passed == total
          paragraphs << "MASTER passed all #{total} self-application phases. The codebase meets its own standards."
        elsif passed >= total - 2
          paragraphs << "MASTER completed self-application with #{passed} of #{total} phases passing. A few areas need attention."
        else
          paragraphs << "Self-application found gaps in #{total - passed} of #{total} phases. Significant work remains."
        end
        
        # Static analysis and structure
        issues_summary = []
        issues_summary << "#{static[:issues] || 0} static analysis issues" if static[:issues].to_i > 0
        issues_summary << "#{consistency[:issues]&.size || 0} consistency issues" if consistency[:issues]&.size.to_i > 0
        issues_summary << "#{enforcement[:violations]&.size || 0} axiom violations" if enforcement[:violations]&.size.to_i > 0
        
        if issues_summary.any?
          paragraphs << "Code review found #{issues_summary.join(', ')}. Most are minor style issues like missing periods in error messages or mixed hash key types."
        else
          paragraphs << "Code review found no significant issues."
        end
        
        # Logic and adversarial
        if logic[:issues]&.size.to_i > 0 || introspection_result[:issues]&.size.to_i > 0
          logic_count = logic[:issues]&.size || 0
          adversarial_count = introspection_result[:issues]&.size || 0
          paragraphs << "Deeper analysis identified #{logic_count} logic patterns worth reviewing and #{adversarial_count} potential issues from adversarial introspection. These include thread-safety considerations and edge cases an attacker might exploit."
        end
        
        # Council rating
        if council[:rating]
          rating = council[:rating]
          if rating >= 8
            paragraphs << "The adversarial council rated the codebase #{rating}/10, indicating strong alignment with stated axioms."
          elsif rating >= 6
            paragraphs << "The adversarial council rated the codebase #{rating}/10. Room for improvement exists but fundamentals are solid."
          else
            paragraphs << "The adversarial council rated the codebase #{rating}/10, suggesting significant gaps between stated principles and implementation."
          end
        end
        
        # Print with nice wrapping
        paragraphs.each do |para|
          puts word_wrap(para, 72)
          puts
        end
      end
      
      def word_wrap(text, width)
        text.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip
      end
      
      def check_error_message_format(content, file)
        issues = []
        messages = content.scan(/Result\.err\(["']([^"']+)["']\)/)
        messages.flatten.each do |msg|
          next if msg.start_with?(/[A-Z]/) && msg.end_with?(".")
          issues << "#{file}: Error message missing period or capitalization"
        end
        issues.first(2)  # Limit per file
      end

      def check_exception_handling(content, file)
        issues = []
        # Check for bare rescues (not rescue StandardError)
        if content.match?(/rescue\s*$/) && !BARE_RESCUE_ALLOWED.include?(file)
          issues << "#{file}: Bare rescue found"
        end
        issues
      end

      def check_logic_patterns(content, file)
        issues = []
        # Thread-unsafe memoization
        if content.match?(/\|\|=.*YAML\./) && !content.match?(/Monitor|Mutex/)
          issues << "#{file}: Potential thread-unsafe YAML memoization"
        end
        # Mixed hash key types
        symbol_keys = content.scan(/\[:\w+\]/).size
        string_keys = content.scan(/\["[^"]+"\]/).size
        if symbol_keys > 5 && string_keys > 5
          issues << "#{file}: Mixed symbol/string hash access"
        end
        issues
      end
      
      def lib_files
        Dir.glob(File.join(MASTER.root, "lib", "**", "*.rb"))
      end

      def each_lib_file
        lib_files.each { |f| yield File.read(f), File.basename(f) }
      end
      
      # ═══════════════════════════════════════════════════════════════════
      # SECTION 5: Adversarial Questioning (original introspection)
      # ═══════════════════════════════════════════════════════════════════

      def hostile_questions
        @hostile_questions ||= begin
          config = load_questions
          config.dig('hostile', 'questions') || default_hostile_questions
        end
      end

      def phase_reflections
        @phase_reflections ||= begin
          config = load_questions
          reflections = {}
          %w[discover analyze ideate design implement validate deliver learn].each do |phase|
            if config[phase]
              reflections[phase.to_sym] = config.dig(phase, 'introspection') || 
                                          config.dig(phase, 'purpose')
            end
          end
          reflections.empty? ? default_phase_reflections : reflections
        end
      end

      # Interrogate any input/output with hostile questions
      # This is the main entry point - treats all code equally
      def interrogate(content, context: {})
        issues = []

        # Fast path: heuristic checks (no LLM cost)
        hostile_questions.each do |question|
          issue = fast_check(content, question)
          issues << issue if issue
        end

        # Phase-specific reflection if stage provided
        if context[:stage]
          reflection = phase_reflections[context[:stage].to_sym]
          if reflection
            issue = fast_check(content, reflection)
            issues << issue if issue
          end
        end

        {
          interrogated: true,
          issues: issues,
          passed: issues.empty?,
          severity: calculate_severity(issues),
          recommendation: recommendation(issues),
        }
      end

      # Deep interrogation with LLM (uses budget)
      def deep_interrogate(content, context: {})
        issues = []

        # Sample questions for cost efficiency
        questions = hostile_questions.sample(3)
        questions << phase_reflections[context[:stage].to_sym] if context[:stage]

        questions.compact.each do |question|
          result = ask_hostile(content, question)
          issues << result if result
        end

        {
          deep: true,
          issues: issues,
          passed: issues.empty?,
          severity: calculate_severity(issues),
        }
      end

      # Audit against axioms
      def audit(content, axioms: nil)
        axioms ||= DB.axioms
        violations = []

        axioms.each do |axiom|
          violation = check_axiom(content, axiom)
          violations << violation if violation
        end

        {
          audited: true,
          violations: violations,
          passed: violations.empty?,
          axioms_checked: axioms.size,
        }
      end

      # Full adversarial review: interrogate + audit + enforcement
      def full_review(content, context: {})
        interrogation = interrogate(content, context: context)
        audit_result = audit(content)
        enforcement = Enforcement.check(content, filename: context[:filename] || "input")

        all_issues = interrogation[:issues] + 
                     audit_result[:violations] + 
                     enforcement[:violations]

        {
          passed: all_issues.empty?,
          interrogation: interrogation,
          audit: audit_result,
          enforcement: enforcement,
          total_issues: all_issues.size,
          severity: calculate_severity(all_issues),
          recommendation: recommendation(all_issues),
        }
      end
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
      
      def collect_files(dir)
        result = []

        Dir.entries(dir).each do |entry|
          next if entry.start_with?(".") || IGNORED.include?(entry)

          path = File.join(dir, entry)
          if File.directory?(path)
            result.concat(collect_files(path))
          else
            result << path.sub("#{dir}/", "")
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
      
      # ═══════════════════════════════════════════════════════════════════
      # PRIVATE HELPERS - Section 5 (Adversarial Questioning)
      # ═══════════════════════════════════════════════════════════════════

      FAST_CHECKS = {
        /assumption.*wrong/i => {
          pattern: /\b(always|never|must|definitely|guaranteed)\b/i,
          issue: "Contains absolute language",
        },
        /hostile user/i => {
          pattern: /\b(password|secret|key|token|credential)\b/i,
          issue: "May expose sensitive information",
        },
        /edge case/i => {
          check: ->(c) { c.match?(/\bnil\b|\bnull\b/) && !c.match?(/\b(handle|check|guard|rescue)\b/i) },
          issue: "May not handle nil/null edge cases",
        },
        /simplest/i => {
          check: ->(c) { c.length > 5000 },
          issue: "Content very long - may not be simplest",
        },
        /regret/i => {
          pattern: /\b(TODO|FIXME|XXX|HACK|temporary|workaround)\b/i,
          issue: "Contains technical debt markers",
        },
        /who loses/i => {
          pattern: /\b(delete|remove|drop|disable|revoke)\b/i,
          issue: "Contains destructive operations",
        },
        /second-order/i => {
          check: ->(c) { c.scan(/\b(require|import|include|use)\b/).size > 10 },
          issue: "Many dependencies - consider cascading effects",
        },
        /security officer/i => {
          pattern: /\b(eval|exec|system|`[^`]+`|%x\{)/i,
          issue: "Contains code execution patterns",
        },
        /complexity hiding/i => {
          check: ->(c) { c.scan(/\bif\b|\bcase\b|\b\?\s*.*:/).size > 20 },
          issue: "High branching complexity",
        },
        /technical debt/i => {
          check: ->(c) { c.scan(/\b(TODO|FIXME|HACK|XXX|OPTIMIZE|REFACTOR)\b/i).size > 3 },
          issue: "Multiple technical debt markers",
        },
      }.freeze

      def fast_check(content, question)
        FAST_CHECKS.each do |q_pattern, check|
          next unless question.match?(q_pattern)

          triggered = check[:check]&.call(content) || (check[:pattern] && content.match?(check[:pattern]))
          return { question: question, issue: check[:issue] } if triggered
        end
        nil
      end

      def ask_hostile(content, question)
        prompt = <<~PROMPT
          HOSTILE QUESTION: #{question}

          CONTENT:
          #{content[0, 2000]}

          If genuine issue found, respond: ISSUE: [description]
          Otherwise respond: PASS
        PROMPT

        result = LLM.ask(prompt, stream: false)
        return nil unless result.ok?

        response = result.value[:content].to_s
        if response.include?("ISSUE:")
          { question: question, issue: response[/ISSUE:\s*(.+)/, 1] }
        else
          nil
        end
      end

      def check_axiom(content, axiom)
        id = axiom[:id] || axiom["id"]
        pattern = axiom[:pattern] || axiom["pattern"]

        if pattern && content.match?(Regexp.new(pattern, Regexp::IGNORECASE))
          return { axiom: id, issue: "Pattern violation" }
        end

        case id
        when "OMIT_WORDS"
          fillers = content.scan(/\b(just|really|very|basically|actually|literally|quite|rather)\b/i).size
          return { axiom: id, issue: "#{fillers} filler words" } if fillers > 5

        when "ACTIVE_VOICE"
          passive = content.scan(/\b(was|were|been|being)\s+\w+ed\b/i).size
          return { axiom: id, issue: "#{passive} passive constructions" } if passive > 3

        when "DRY"
          lines = content.lines.map(&:strip).reject(&:empty?)
          dups = lines.group_by(&:itself).select { |_, v| v.size > 2 && v.first.length > 30 }
          return { axiom: id, issue: "Repeated lines detected" } if dups.any?

        when "KISS"
          if content.scan(/\bclass\b/).size > 3 || content.scan(/\bmodule\b/).size > 3
            return { axiom: id, issue: "Too many classes/modules" }
          end

        when "FAIL_LOUD"
          if content.match?(/rescue\s*($|#|\n\s*end)/)
            return { axiom: id, issue: "Bare rescue swallows errors" }
          end
        end

        nil
      end

      def calculate_severity(issues)
        count = issues.size
        if count >= 5 then :critical
        elsif count >= 3 then :high
        elsif count >= 1 then :medium
        else :low
        end
      end

      def recommendation(issues)
        case calculate_severity(issues)
        when :critical then "Major issues - requires significant revision"
        when :high then "Notable issues - revision recommended"
        when :medium then "Minor issues - acceptable with acknowledgment"
        else "Passes adversarial review"
        end
      end

      def load_questions
        path = File.join(MASTER.root, 'data', 'questions.yml')
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def default_hostile_questions
        [
          "What assumption here could be completely wrong?",
          "What would a hostile user do with this?",
          "What edge case would break this in production?",
          "Is this the simplest possible solution?",
          "What would I regret about this in 6 months?",
          "What am I not seeing?",
          "Who loses if this is implemented?",
          "What's the second-order effect?",
          "Is this solving the right problem or a symptom?",
          "What would the security officer veto here?",
          "Where is the complexity hiding?",
          "What would break if requirements changed 20%?",
          "Where is technical debt accumulating?"
        ]
      end

      def default_phase_reflections
        {
          intake: "Did I understand the actual intent, not just the words?",
          compress: "Did I lose essential meaning in compression?",
          guard: "Did I block something legitimate?",
          route: "Did I pick the right model for this task?",
          council: "Did the council debate the real issues?",
          ask: "Did the LLM answer what was asked?",
          lint: "Did I enforce axioms consistently?",
          render: "Is the output clear to the user?"
        }
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BACKWARD COMPATIBILITY ALIASES
  # ═══════════════════════════════════════════════════════════════════
  
  SelfMap = Introspection
  SelfCritique = Introspection
  SelfRepair = Introspection
  SelfTest = Introspection
end
