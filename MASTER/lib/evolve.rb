# frozen_string_literal: true

module MASTER
  # Self-improvement workflow
  # Analyzes codebase, identifies refinements, applies them, repeats until convergence
  class Evolve
    MAX_ITERATIONS = 100
    CONVERGENCE_THRESHOLD = 0.02  # Stop when improvement rate drops below 2%
    MIN_REFINEMENTS = 2           # Stop when fewer than this found
    PER_FILE_BUDGET = 0.5         # Max cost per file analysis
    MAX_ANALYSIS_FILE_SIZE = 10_000
    MAX_CONCEPTUAL_CHECK_SIZE = 5000
    REFINEMENT_FILE = File.join(Paths.config, 'refinements.yml')
    WISHLIST_FILE = File.join(Paths.config, 'wishlist.yml')
    EVOLUTION_LOG = File.join(Paths.data, 'evolution.log')
    HISTORY_FILE = File.join(Paths.data, 'evolution_history.yml')
    
    # Files that should never be auto-modified during self-runs
    PROTECTED_FILES = %w[
      lib/evolve.rb
      lib/violations.rb
      lib/converge.rb
      lib/core/executor.rb
    ].freeze

    def initialize(llm, chamber = nil)
      @llm = llm
      @chamber = chamber || Chamber.new(llm)
      @creative = CreativeChamber.new(llm)
      @intro = Introspection.new(llm)
      @iteration = 0
      @cost = 0.0
      @history = []  # Track improvement rates
      @prior_wishlist = load_prior_wishlist
    end
    
    # Load wishlist from previous run to inform current analysis
    def load_prior_wishlist
      return [] unless File.exist?(WISHLIST_FILE)
      YAML.load_file(WISHLIST_FILE) rescue []
    end
    
    # Save run history for learning across sessions
    def save_run_history(summary)
      history = File.exist?(HISTORY_FILE) ? (YAML.load_file(HISTORY_FILE) rescue []) : []
      history << {
        timestamp: Time.now.iso8601,
        iterations: @iteration,
        cost: @cost,
        summary: summary
      }
      history = history.last(50) # Keep last 50 runs
      File.write(HISTORY_FILE, history.to_yaml)
    end
    
    # Check if file is protected from auto-modification
    def protected?(file)
      PROTECTED_FILES.any? { |p| file.end_with?(p) }
    end
    
    # Load principles from YAML files for context
    def load_principles
      dir = File.join(Paths.lib, 'principles')
      return [] unless File.directory?(dir)
      
      Dir[File.join(dir, '*.yml')].map do |f|
        YAML.load_file(f) rescue nil
      end.compact
    end
    
    # Format principles for LLM context
    def principles_context
      principles = load_principles
      return "" if principles.empty?
      
      principles.first(10).map do |p|
        "#{p['name']}: #{p['description']}"
      end.join("\n")
    end
    
    # Capture baseline metrics before any changes
    def capture_baseline(target)
      {
        files: collect_files(target).size,
        lines: collect_files(target).sum { |f| File.read(f).lines.count rescue 0 },
        violations: count_violations(target),
        timestamp: Time.now.iso8601
      }
    end
    
    # Run tests to verify changes didn't break anything
    def verify_tests
      test_dir = File.join(Paths.root, 'test')
      return { passed: true, skipped: true } unless File.directory?(test_dir)
      
      result = `cd #{Paths.root} && ruby -Ilib -Itest -e "Dir['test/test_*.rb'].each { |f| require './'+f }" 2>&1`
      passed = $?.success?
      { passed: passed, output: result.lines.last(5).join, skipped: false }
    end

    # Continuous evolution until convergence
    def converge(target: Paths.lib, budget: 5.0)
      log "Convergence loop started: #{target}"
      log "Budget: $#{budget}, threshold: #{CONVERGENCE_THRESHOLD * 100}%"
      
      # Capture baseline before any changes
      @baseline = capture_baseline(target)
      log "Baseline: #{@baseline[:files]} files, #{@baseline[:violations]} violations"

      # Full principle check at START (lexical + conceptual)
      start_violations = full_principle_check(target)
      log "Starting violations: #{start_violations} (lexical + conceptual)"

      prev_score = 0
      stall_count = 0

      loop do
        @iteration += 1

        # Run one evolution cycle (lexical checks only for speed)
        cycle_result = run_cycle(target)
        break if cycle_result[:stop]

        # Track improvement
        current_score = cycle_result[:applied]
        current_violations = cycle_result[:violations] || 0
        improvement_rate = prev_score > 0 ? (current_score - prev_score).abs.to_f / prev_score : 1.0
        @history << { 
          iteration: @iteration, 
          applied: current_score, 
          rate: improvement_rate,
          violations: current_violations
        }

        log "Cycle #{@iteration}: #{current_score} applied, #{current_violations} violations"

        # Check convergence conditions
        if improvement_rate < CONVERGENCE_THRESHOLD
          stall_count += 1
          log "Diminishing returns detected (#{stall_count}/3)"
          if stall_count >= 3
            log "Converged: improvement rate below threshold for 3 cycles"
            break
          end
        else
          stall_count = 0
        end

        if @cost >= budget
          log "Budget exhausted: $#{'%.2f' % @cost}"
          break
        end

        if @iteration >= MAX_ITERATIONS
          log "Max iterations reached"
          break
        end

        if current_score < MIN_REFINEMENTS
          log "Too few refinements found, likely converged"
          break
        end

        prev_score = current_score

        # Brief pause between cycles
        sleep 1
      end

      # Full principle check at END (lexical + conceptual)
      end_violations = full_principle_check(target)
      log "Ending violations: #{end_violations} (lexical + conceptual)"
      
      # Verify tests still pass after all changes
      test_result = verify_tests
      if test_result[:skipped]
        log "Tests: skipped (no test directory)"
      elsif test_result[:passed]
        log "Tests: passed"
      else
        log "Tests: FAILED - #{test_result[:output]}"
      end
      
      # Store for summary
      @start_violations = start_violations
      @end_violations = end_violations
      @test_result = test_result

      # Final summary
      summary = convergence_summary
      log summary

      # Generate wishlist for next session
      wishlist = generate_wishlist(target)
      save_wishlist(wishlist)
      save_run_history(summary)

      log "Evolution complete: #{@iteration} iterations, $#{'%.4f' % @cost}"
      {
        iterations: @iteration,
        cost: @cost,
        history: @history,
        baseline: @baseline,
        start_violations: start_violations,
        end_violations: end_violations,
        tests_passed: test_result[:passed],
        converged: stall_count >= 3 || @history.last&.dig(:applied).to_i < MIN_REFINEMENTS,
        wishlist: wishlist
      }
    end

    # Single evolution cycle
    def run_cycle(target)
      # 0. Measure principle compliance BEFORE
      before_violations = count_violations(target)

      # 1. Analyze current state
      refinements = analyze(target)
      if refinements.empty?
        log "No refinements found"
        return { stop: true, applied: 0, violations: before_violations }
      end

      # 2. Prioritize by impact (principle violations first)
      prioritized = prioritize(refinements)
      log "Found #{prioritized.size} refinement opportunities"

      # 3. Apply top refinements
      applied = apply_top(prioritized, count: 5)

      # 4. Validate changes (syntax + principles)
      unless validate(target)
        log "Validation failed, reverting"
        revert_last
        return { stop: false, applied: 0, violations: before_violations }
      end

      # 5. Check principle compliance AFTER
      after_violations = count_violations(target)
      if after_violations > before_violations
        log "Principle violations increased (#{before_violations}→#{after_violations}), reverting"
        revert_last
        return { stop: false, applied: 0, violations: before_violations }
      end

      # 6. Commit if successful
      if applied > 0
        delta = before_violations - after_violations
        msg = "evolve: #{applied} refinements"
        msg += ", -#{delta} violations" if delta > 0
        commit_changes(msg)
        log "Violations: #{before_violations}→#{after_violations}"
      end

      # 7. Introspect
      reflect

      { stop: false, applied: applied, violations: after_violations }
    end

    # Count principle violations in target (lexical + conceptual)
    def count_violations(target, conceptual: false)
      files = collect_files(target)
      total = 0
      files.each do |file|
        code = File.read(file) rescue next
        # Lexical (fast, regex-based)
        lexical = Violations.check_literal(code) rescue []
        total += lexical.size
        
        # Conceptual (slow, LLM-based) - only on first/last cycle or when requested
        if conceptual && code.length < MAX_CONCEPTUAL_CHECK_SIZE
          conceptual_v = Violations.detect_conceptual(code, file, @llm) rescue []
          total += conceptual_v.size
          @cost += @llm.last_cost rescue 0
        end
      end
      total
    end

    # Full principle check (both lexical and conceptual)
    def full_principle_check(target)
      log "Running full principle check (lexical + conceptual)..."
      count_violations(target, conceptual: true)
    end

    # Full single-pass evolution (original method)
    def run(target: Paths.lib, budget: 1.0)
      log "Evolution started: #{target}"
      @baseline = capture_baseline(target)

      until @iteration >= MAX_ITERATIONS || @cost >= budget
        result = run_cycle(target)
        break if result[:stop] || result[:applied] == 0
      end

      test_result = verify_tests
      log test_result[:passed] ? "Tests: passed" : "Tests: FAILED"

      wishlist = generate_wishlist(target)
      save_wishlist(wishlist)
      save_run_history("#{@iteration} iterations, $#{'%.4f' % @cost}, tests: #{test_result[:passed]}")

      log "Evolution complete: #{@iteration} iterations, $#{'%.4f' % @cost}"
      { iterations: @iteration, cost: @cost, tests_passed: test_result[:passed], wishlist: wishlist }
    end

    # Analyze codebase for refinement opportunities
    def analyze(target)
      files = collect_files(target)
      refinements = []

      files.each do |file|
        next if @cost >= PER_FILE_BUDGET
        next if protected?(file)

        code = File.read(file) rescue next
        next if code.length > MAX_ANALYSIS_FILE_SIZE

        # Check current violations for this file
        current_violations = Violations.check_literal(code) rescue []
        violation_context = current_violations.any? ? 
          "Current violations: #{current_violations.map { |v| v[:principle] }.uniq.join(', ')}" : ""
        
        # Include prior wishlist items relevant to this file
        prior_context = @prior_wishlist.select { |w| w[:file]&.include?(File.basename(file)) }
        wishlist_context = prior_context.any? ?
          "Prior wishlist: #{prior_context.map { |w| w[:description] }.join('; ')}" : ""
        
        # Load actual principles for context
        principles_text = principles_context

        prompt = <<~PROMPT
          Analyze this code for refinements that align with these principles:
          #{principles_text.empty? ? "KISS, DRY, YAGNI, Single Responsibility, Few Arguments, Small Functions." : principles_text}

          #{violation_context}
          #{wishlist_context}

          Return 3-5 specific improvements. For each:
          - Line number (approximate)
          - What to change (one sentence)
          - Why (principle violated OR clarity/performance/safety)
          - Effort: low/medium/high

          Prioritize fixing principle violations. Only suggest changes that are:
          - Surgical (1-5 lines)
          - Safe (won't break behavior)
          - Aligned with principles above

          ```
          #{code[0..3000]}
          ```
        PROMPT

        result = @llm.chat(prompt, tier: :cheap)
        @cost += @llm.last_cost rescue 0

        if result.ok?
          parse_refinements(result.value, file).each do |r|
            refinements << r
          end
        end
      end

      refinements
    end

    # Prioritize refinements by impact and effort
    def prioritize(refinements)
      # Score: high impact + low effort = high priority
      refinements.sort_by do |r|
        impact = { clarity: 1, performance: 2, safety: 3 }[r[:impact]] || 1
        effort = { low: 3, medium: 2, high: 1 }[r[:effort]] || 1
        -(impact * effort) # Negative for descending sort
      end
    end

    # Apply top N refinements via chamber deliberation
    def apply_top(refinements, count: 5)
      applied = 0

      refinements.first(count).each do |ref|
        result = @chamber.deliberate(ref[:file])
        @cost += @chamber.cost

        if result[:applied]
          applied += 1
          log "Applied: #{ref[:file]}:#{ref[:line]} - #{ref[:desc]}"
        end
      end

      applied
    end

    # Validate changes (syntax check, tests if available)
    def validate(target)
      # Ruby syntax check
      files = collect_files(target).select { |f| f.end_with?('.rb') }

      files.all? do |file|
        system("ruby -c #{file} > /dev/null 2>&1")
      end
    end

    # Revert last changes via git
    def revert_last
      system("git checkout -- .")
    end

    # Post-iteration reflection
    def reflect
      summary = "Iteration #{@iteration}: analyzed codebase, applied refinements"
      @intro.reflect_on_phase(:implement, summary)
    end

    # Generate wishlist for future sessions
    def generate_wishlist(target)
      prompt = <<~PROMPT
        You just analyzed and improved this codebase: #{target}

        Based on patterns you've seen, what are the TOP 10 improvements
        that would make the biggest difference but weren't addressed?

        Consider:
        - Architectural improvements
        - Missing features
        - Performance opportunities
        - Developer experience
        - User experience

        Return as numbered list with brief descriptions.
      PROMPT

      result = @llm.chat(prompt, tier: :strong)
      @cost += @llm.last_cost rescue 0

      result.ok? ? parse_wishlist(result.value) : []
    end

    # Save wishlist for next session
    def save_wishlist(items)
      data = {
        'generated' => Time.now.iso8601,
        'iteration' => @iteration,
        'items' => items
      }

      File.write(WISHLIST_FILE, data.to_yaml)
    end

    # Load previous wishlist
    def load_wishlist
      return [] unless File.exist?(WISHLIST_FILE)
      YAML.safe_load(File.read(WISHLIST_FILE))['items'] || []
    rescue
      []
    end

    private

    def collect_files(target)
      if File.file?(target)
        [target]
      else
        Dir.glob(File.join(target, '**', '*.rb'))
           .reject { |f| f.include?('/vendor/') || f.include?('/test/') }
      end
    end

    def parse_refinements(text, file)
      refinements = []

      text.scan(/(?:line\s*)?(\d+)[:\s]+(.+?)(?:\n|$)/i) do |line, desc|
        impact = :clarity
        impact = :performance if desc =~ /perform|speed|fast/i
        impact = :safety if desc =~ /safe|secur|error|bug/i

        effort = :medium
        effort = :low if desc =~ /\blow\b/i
        effort = :high if desc =~ /\bhigh\b/i

        refinements << {
          file: file,
          line: line.to_i,
          desc: desc.strip[0..100],
          impact: impact,
          effort: effort
        }
      end

      refinements
    end

    def parse_wishlist(text)
      items = []

      text.lines.each do |line|
        if line =~ /^\d+[.)]\s*(.+)/
          items << $1.strip
        end
      end

      items.first(10)
    end

    def log(msg)
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      line = "[#{timestamp}] #{msg}"
      puts line

      File.open(EVOLUTION_LOG, 'a') { |f| f.puts(line) }
    rescue
      # Ignore logging errors
    end

    def commit_changes(message)
      system("git add -A && git commit -m '#{message}' > /dev/null 2>&1")
    end

    def convergence_summary
      total_applied = @history.sum { |h| h[:applied] }
      avg_rate = @history.empty? ? 0 : @history.sum { |h| h[:rate] } / @history.size

      # Use full principle check values if available, otherwise history
      start_v = @start_violations || @history.first&.dig(:violations) || 0
      end_v = @end_violations || @history.last&.dig(:violations) || 0
      violation_delta = start_v - end_v

      <<~SUMMARY
        ━━━ Convergence Summary ━━━
        Iterations: #{@iteration}
        Refinements applied: #{total_applied}
        
        Principle Alignment:
          Start: #{start_v} violations (lexical + conceptual)
          End:   #{end_v} violations
          Delta: #{violation_delta >= 0 ? '↓' : '↑'}#{violation_delta.abs} #{violation_delta >= 0 ? '✓' : '⚠'}
        
        Cost: $#{'%.4f' % @cost}
      SUMMARY
    end

    public

    # Update README.md to reflect current state
    def update_readme
      readme_path = File.join(Paths.root, 'README.md')
      
      # Gather current state
      files = Dir.glob(File.join(Paths.lib, '*.rb')).map { |f| File.basename(f, '.rb') }
      principles = Principle.load_all rescue []
      tiers = LLM::TIERS.keys rescue []
      commands = CLI::COMMANDS rescue []

      prompt = <<~PROMPT
        Update the README.md for MASTER v#{VERSION}.

        Current modules: #{files.join(', ')}
        Principles: #{principles.size}
        LLM tiers: #{tiers.join(', ')}
        Commands: #{commands.first(15).join(', ')}

        Write in clear prose paragraphs. No tables, no lists, no horizontal rules.
        Keep it concise - around 400 words. Focus on what it does, not how.

        Structure:
        1. One-line description
        2. Quick start (2 sentences)
        3. What it does (2-3 paragraphs)
        4. Key capabilities
        5. Environment variables

        Style: Strunk & White. Direct. No marketing fluff.
      PROMPT

      result = @llm.chat(prompt, tier: :strong)
      @cost += @llm.last_cost rescue 0

      if result.ok?
        content = "# MASTER v#{VERSION}\n\n#{result.value.strip}\n"
        File.write(readme_path, content)
        log "README.md updated"
        true
      else
        log "README update failed: #{result.error}"
        false
      end
    end

    # Full convergence with README update
    def converge_and_document(target: Paths.lib, budget: 5.0)
      result = converge(target: target, budget: budget)

      # Update README after convergence
      if result[:converged] || result[:iterations] > 0
        update_readme
        commit_changes("docs: README updated after evolution")
      end

      result
    end
  end
end
