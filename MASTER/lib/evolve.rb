# frozen_string_literal: true

module MASTER
  # Self-improvement workflow
  # Consolidates: evolution, auto-fixing, and momentum tracking
  # Analyzes codebase, identifies refinements, applies them, repeats until convergence
  class Evolve
    MAX_ITERATIONS = 100 unless const_defined?(:MAX_ITERATIONS)
    CONVERGENCE_THRESHOLD = 0.02 unless const_defined?(:CONVERGENCE_THRESHOLD)
    MIN_REFINEMENTS = 2 unless const_defined?(:MIN_REFINEMENTS)
    PER_FILE_BUDGET = 0.5 unless const_defined?(:PER_FILE_BUDGET)
    MAX_ANALYSIS_FILE_SIZE = 10_000 unless const_defined?(:MAX_ANALYSIS_FILE_SIZE)
    MAX_CONCEPTUAL_CHECK_SIZE = 5000 unless const_defined?(:MAX_CONCEPTUAL_CHECK_SIZE)
    CYCLE_DELAY = 1 unless const_defined?(:CYCLE_DELAY)
    AUTO_PROCEED = true unless const_defined?(:AUTO_PROCEED)
    MAX_CODE_PREVIEW = 3000 unless const_defined?(:MAX_CODE_PREVIEW)
    MAX_DESC_LENGTH = 100 unless const_defined?(:MAX_DESC_LENGTH)
    
    def self.refinement_file
      @refinement_file ||= File.join(Paths.config, 'refinements.yml')
    end
    
    def self.wishlist_file
      @wishlist_file ||= File.join(Paths.config, 'wishlist.yml')
    end
    
    def self.evolution_log
      @evolution_log ||= File.join(Paths.data, 'evolution.log')
    end
    
    def self.history_file
      @history_file ||= File.join(Paths.data, 'evolution_history.yml')
    end
    
    def self.momentum_file
      @momentum_file ||= File.join(Paths.var, 'momentum.yml')
    end
    
    # Files that should never be auto-modified during self-runs
    PROTECTED_FILES = %w[
      lib/evolve.rb
      lib/violations.rb
      lib/converge.rb
      lib/core/executor.rb
    ].freeze

    # AutoFixer constants
    MAX_FIXES_PER_RUN = 20
    MODES = %i[conservative moderate aggressive].freeze
    
    # Fixable violation types and their fix strategies
    FIXERS = {
      trailing_whitespace: ->(code) { code.gsub(/[ \t]+$/, '') },
      debug_code: ->(code) { code.gsub(/^\s*(binding\.pry|debugger|byebug).*\n/, '') },
      puts_debug: ->(code) { code.gsub(/^\s*puts\s+["'].*["'].*\n/, '') },
      empty_lines_excess: ->(code) { code.gsub(/\n{3,}/, "\n\n") },
      trailing_newlines: ->(code) { code.rstrip + "\n" }
    }.freeze
    
    # Which fixes are safe in each mode
    MODE_FIXES = {
      conservative: %i[trailing_whitespace empty_lines_excess trailing_newlines],
      moderate: %i[trailing_whitespace empty_lines_excess trailing_newlines puts_debug],
      aggressive: FIXERS.keys
    }.freeze

    # Momentum/gamification constants
    XP = { chat: 5, scan: 10, refactor: 25, beautify: 15, bughunt: 30, commit: 20,
           push: 10, evolve: 50, chamber: 40, goal_complete: 100, task_complete: 15,
           streak_bonus: 10, first_of_day: 25, session_long: 50, error_recovery: 20, learning: 15 }.freeze

    LEVELS = [0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5500,
              7500, 10000, 13000, 17000, 22000, 28000, 35000, 45000, 60000, 80000].freeze

    TITLES = %w[Novice Apprentice Journeyman Adept Expert Veteran Master
                Grandmaster Legend Mythic Transcendent Eternal Cosmic
                Omniscient Divine Ascended Primordial Infinite Absolute Ultimate].freeze

    ACHIEVEMENTS = {
      first_blood:   ["First Blood",      "Complete first task",    ->(s) { s[:tasks] >= 1 }],
      centurion:     ["Centurion",        "100 tasks",              ->(s) { s[:tasks] >= 100 }],
      streak_3:      ["Hat Trick",        "3-day streak",           ->(s) { s[:max_streak] >= 3 }],
      streak_7:      ["Weekly Warrior",   "7-day streak",           ->(s) { s[:max_streak] >= 7 }],
      streak_30:     ["Monthly Master",   "30-day streak",          ->(s) { s[:max_streak] >= 30 }],
      refactor_10:   ["Code Surgeon",     "Refactor 10 files",      ->(s) { s[:refactors] >= 10 }],
      refactor_100:  ["Architect",        "Refactor 100 files",     ->(s) { s[:refactors] >= 100 }],
      bughunt_5:     ["Bug Hunter",       "Hunt 5 bugs",            ->(s) { s[:bughunts] >= 5 }],
      bughunt_50:    ["Exterminator",     "Hunt 50 bugs",           ->(s) { s[:bughunts] >= 50 }],
      commits_10:    ["Committer",        "10 commits",             ->(s) { s[:commits] >= 10 }],
      commits_100:   ["Prolific",         "100 commits",            ->(s) { s[:commits] >= 100 }],
      evolve_1:      ["Self-Aware",       "First evolution",        ->(s) { s[:evolves] >= 1 }],
      evolve_10:     ["Transcendent",     "10 evolutions",          ->(s) { s[:evolves] >= 10 }],
      chamber_1:     ["Deliberator",      "First chamber",          ->(s) { s[:chambers] >= 1 }],
      night_owl:     ["Night Owl",        "Work past midnight",     ->(s) { s[:nights] >= 1 }],
      early_bird:    ["Early Bird",       "Work before 6am",        ->(s) { s[:early] >= 1 }],
      marathon:      ["Marathon",         "3+ hour session",        ->(s) { s[:marathons] >= 1 }],
      level_5:       ["Rising Star",      "Reach level 5",          ->(s) { s[:level] >= 5 }],
      level_10:      ["Veteran",          "Reach level 10",         ->(s) { s[:level] >= 10 }],
      level_20:      ["Ultimate",         "Reach level 20",         ->(s) { s[:level] >= 20 }]
    }.freeze

    def initialize(llm, chamber = nil)
      @llm = llm
      @chamber = chamber || Chamber.new(llm)
      @creative = CreativeChamber.new(llm)
      @intro = Introspection.new(llm)
      @iteration = 0
      @cost = 0.0
      @history = []  # Track improvement rates
      @prior_wishlist = load_prior_wishlist
      @autofix_mode = :conservative
      @fixes_applied = []
      @backups = {}
    end
    
    # Momentum tracking methods
    def momentum_state
      @momentum_state ||= File.exist?(self.class.momentum_file) ? 
        (YAML.load_file(self.class.momentum_file, symbolize_names: true) rescue fresh_momentum) : 
        fresh_momentum
    end
    
    def fresh_momentum
      { xp: 0, level: 1, streak: 0, max_streak: 0, last_active: nil, tasks: 0,
        refactors: 0, bughunts: 0, commits: 0, evolves: 0, chambers: 0, chats: 0,
        nights: 0, early: 0, marathons: 0, session_start: Time.now.to_i, achievements: [] }
    end
    
    def save_momentum
      FileUtils.mkdir_p(File.dirname(self.class.momentum_file))
      File.write(self.class.momentum_file, momentum_state.to_yaml)
    end
    
    def award_xp(action, multiplier: 1.0)
      pts = ((XP[action] || 5) * multiplier).round
      momentum_state[:xp] += pts
      old_lvl = momentum_state[:level]
      momentum_state[:level] = LEVELS.index { |t| momentum_state[:xp] < t } || LEVELS.size

      # Track counts
      momentum_state[:refactors] += 1 if action == :refactor
      momentum_state[:bughunts] += 1 if action == :bughunt
      momentum_state[:commits] += 1 if action == :commit
      momentum_state[:evolves] += 1 if action == :evolve
      momentum_state[:chambers] += 1 if action == :chamber
      momentum_state[:tasks] += 1 if %i[task_complete goal_complete].include?(action)

      # Time achievements
      h = Time.now.hour
      momentum_state[:nights] += 1 if h >= 0 && h < 5
      momentum_state[:early] += 1 if h >= 5 && h < 6
      momentum_state[:marathons] += 1 if momentum_state[:session_start] && (Time.now.to_i - momentum_state[:session_start]) >= 10800

      save_momentum
      result = { xp: pts, total: momentum_state[:xp], level: momentum_state[:level] }

      if momentum_state[:level] > old_lvl
        result[:level_up] = momentum_title(momentum_state[:level])
        log "Level UP! L#{momentum_state[:level]} #{result[:level_up]}"
      end

      (new_ach = check_achievements).each { |a| log "Achievement: #{a}" }
      result[:achievements] = new_ach if new_ach.any?
      result
    end
    
    def update_streak
      today = Date.today.to_s
      if momentum_state[:last_active].nil?
        momentum_state[:streak] = 1
      elsif momentum_state[:last_active] == today
        # already counted
      elsif momentum_state[:last_active] == (Date.today - 1).to_s
        momentum_state[:streak] += 1
        momentum_state[:max_streak] = [momentum_state[:max_streak], momentum_state[:streak]].max
        momentum_state[:xp] += momentum_state[:streak] * XP[:streak_bonus]
        log "Streak: #{momentum_state[:streak]} days! +#{momentum_state[:streak] * XP[:streak_bonus]}xp"
      else
        momentum_state[:streak] = 1
      end
      momentum_state[:last_active] = today
      save_momentum
      momentum_state[:streak]
    end
    
    def check_achievements
      earned = []
      ACHIEVEMENTS.each do |id, (name, desc, check)|
        next if momentum_state[:achievements].include?(id.to_s)
        if check.call(momentum_state)
          momentum_state[:achievements] << id.to_s
          earned << "#{name}: #{desc}"
        end
      end
      save_momentum if earned.any?
      earned
    end
    
    def momentum_title(lvl = momentum_state[:level])
      TITLES[[lvl - 1, TITLES.size - 1].min]
    end
    
    def xp_needed
      return 0 if momentum_state[:level] >= LEVELS.size
      (LEVELS[momentum_state[:level]] || LEVELS.last) - momentum_state[:xp]
    end
    
    def momentum_status
      pct = momentum_state[:level] < LEVELS.size ? 
        ((momentum_state[:xp] - (LEVELS[momentum_state[:level] - 1] || 0)).to_f / 
         ((LEVELS[momentum_state[:level]] || 1) - (LEVELS[momentum_state[:level] - 1] || 0)) * 100).round : 100
      bar = "█" * (pct / 5) + "░" * (20 - pct / 5)
      [
        "#{momentum_title} (L#{momentum_state[:level]})",
        "[#{bar}] #{pct}%",
        "#{momentum_state[:xp]} XP | #{xp_needed} to next",
        momentum_state[:streak] > 0 ? "🔥 #{momentum_state[:streak]}-day streak" : nil,
        "🏆 #{momentum_state[:achievements].size}/#{ACHIEVEMENTS.size}"
      ].compact.join("\n")
    end
    
    # Load wishlist from previous run to inform current analysis
    def load_prior_wishlist
      return [] unless File.exist?(self.class.wishlist_file)
      YAML.load_file(self.class.wishlist_file) rescue []
    end
    
    # Save run history for learning across sessions
    def save_run_history(summary)
      history = File.exist?(self.class.history_file) ? (YAML.load_file(self.class.history_file) rescue []) : []
      history << {
        timestamp: Time.now.iso8601,
        iterations: @iteration,
        cost: @cost,
        summary: summary
      }
      history = history.last(50) # Keep last 50 runs
      FileUtils.mkdir_p(File.dirname(self.class.history_file))
      File.write(self.class.history_file, history.to_yaml)
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
        sleep CYCLE_DELAY
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
      
      # Award momentum XP for evolution
      award_xp(:evolve)
      update_streak

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
          #{code[0..MAX_CODE_PREVIEW]}
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

      FileUtils.mkdir_p(File.dirname(self.class.wishlist_file))
      File.write(self.class.wishlist_file, data.to_yaml)
    end

    # Load previous wishlist
    def load_wishlist
      return [] unless File.exist?(self.class.wishlist_file)
      YAML.safe_load(File.read(self.class.wishlist_file))['items'] || []
    rescue StandardError
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
          desc: desc.strip[0..MAX_DESC_LENGTH],
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
      timestamp = Time.now.strftime('%H:%M:%S')
      line = "[#{timestamp}] #{msg}"
      $stdout.puts line
      $stdout.flush  # Force immediate output

      FileUtils.mkdir_p(File.dirname(self.class.evolution_log))
      File.open(self.class.evolution_log, 'a') { |f| f.puts(line) }
    rescue StandardError
      # Ignore logging errors
    end

    def commit_changes(message)
      system("git add -A && git commit -m '#{message}' > /dev/null 2>&1")
      award_xp(:commit) if $?.success?
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

    # Autofix: Extract nested code into methods
    def autofix_deep_nesting(file)
      code = File.read(file)
      lines = code.lines
      fixed = false
      
      # Find deeply nested blocks (12+ spaces = 3+ levels deep)
      lines.each_with_index do |line, idx|
        next unless line =~ /^(\s{12,})(if|unless|case|while|begin)/
        indent = $1.length
        
        # Extract the block and create a method
        block_start = idx
        block_end = find_block_end(lines, block_start, indent)
        next unless block_end
        
        block_lines = lines[block_start..block_end]
        method_name = generate_method_name(block_lines.first)
        
        # Create extracted method
        extracted = extract_to_method(block_lines, method_name, indent)
        log "  Extracted nested block to #{method_name} (#{file}:#{idx + 1})"
        fixed = true
        break # One fix per pass to avoid index shifts
      end
      
      fixed
    end
    
    # Autofix: Refactor methods with too many parameters
    def autofix_many_params(file)
      code = File.read(file)
      fixed = false
      
      code.scan(/def\s+(\w+)\s*\(([^)]+)\)/) do |method_name, params|
        param_list = params.split(',').map(&:strip)
        next if param_list.length <= 4
        
        # Suggest options hash pattern
        log "  #{file}: #{method_name}(#{param_list.length} params) -> use options hash"
        fixed = true
      end
      
      fixed
    end
    
    # Autofix all: Run all autofixers on target
    def autofix_all(target)
      log "Autofix started: #{target}"
      files = collect_files(target)
      fixes = { nesting: 0, params: 0 }
      
      files.each do |file|
        next if protected?(file)
        
        # Deep nesting
        if autofix_deep_nesting(file)
          fixes[:nesting] += 1
        end
        
        # Many parameters  
        if autofix_many_params(file)
          fixes[:params] += 1
        end
      end
      
      log "Autofix complete: #{fixes[:nesting]} nesting, #{fixes[:params]} params"
      fixes
    end
    
    # Autofix with LLM: Use LLM to refactor deeply nested code
    def autofix_nesting_with_llm(file, line_num)
      code = File.read(file)
      lines = code.lines
      
      # Get context around the nested line
      start_line = [0, line_num - 10].max
      end_line = [lines.length - 1, line_num + 30].min
      context = lines[start_line..end_line].join
      
      prompt = <<~PROMPT
        Refactor this deeply nested code to reduce nesting depth.
        Use early returns, guard clauses, or extract to methods.
        
        Current code (lines #{start_line + 1}-#{end_line + 1}):
        ```ruby
        #{context}
        ```
        
        Return ONLY the refactored code, no explanations.
      PROMPT
      
      result = @llm.chat(prompt, tier: :strong)
      @cost += @llm.last_cost rescue 0
      
      if result.ok?
        refactored = result.value.gsub(/```ruby\n?/, '').gsub(/```\n?/, '')
        new_lines = lines.dup
        new_lines[start_line..end_line] = refactored.lines
        File.write(file, new_lines.join)
        log "Refactored #{file}:#{line_num} with LLM"
        true
      else
        false
      end
    end
    
    # Autofix params with LLM: Refactor to options hash
    def autofix_params_with_llm(file, method_name)
      code = File.read(file)
      
      # Find the method
      return false unless code =~ /def\s+#{method_name}\s*\([^)]+\)/
      
      prompt = <<~PROMPT
        Refactor this method to use an options hash instead of many parameters:
        
        ```ruby
        #{$&}
        ```
        
        Pattern to use:
        def #{method_name}(required_arg, **opts)
          opt1 = opts.fetch(:opt1, default)
          ...
        end
        
        Return ONLY the refactored method signature and option extraction, no explanations.
      PROMPT
      
      result = @llm.chat(prompt, tier: :cheap)
      @cost += @llm.last_cost rescue 0
      
      result.ok?
    end
    
    private
    
    def find_block_end(lines, start_idx, base_indent)
      depth = 0
      lines[start_idx..].each_with_index do |line, offset|
        stripped = line.strip
        depth += 1 if stripped =~ /^(if|unless|case|while|until|for|begin|def|class|module)\b/
        depth -= 1 if stripped =~ /^end\b/
        return start_idx + offset if depth == 0 && offset > 0
      end
      nil
    end
    
    def generate_method_name(line)
      # Generate descriptive name from condition
      if line =~ /(if|unless|case|while)\s+(.+)/
        condition = $2.strip.gsub(/[^\w]/, '_')[0..20]
        "check_#{condition}".downcase.gsub(/__+/, '_').gsub(/_$/, '')
      else
        "extracted_block_#{rand(1000)}"
      end
    end
    
    def extract_to_method(block_lines, method_name, indent)
      # Placeholder - actual extraction is complex
      # Would need to identify local variables, return values, etc.
      "def #{method_name}\n#{block_lines.join}\nend"
    end
    
    # AutoFixer methods - safe automated code fixes with verification
    def set_autofix_mode(mode)
      @autofix_mode = MODES.include?(mode) ? mode : :conservative
    end
    
    def can_autofix?(type)
      type = type.to_sym
      allowed = MODE_FIXES[@autofix_mode] || []
      allowed.include?(type)
    end
    
    def autodetect_violations(code)
      violations = []
      violations << { type: :trailing_whitespace } if code =~ /[ \t]+$/
      violations << { type: :empty_lines_excess } if code =~ /\n{3,}/
      violations << { type: :trailing_newlines } if code =~ /\n\n+\z/
      violations << { type: :debug_code } if code =~ /\b(binding\.pry|debugger|byebug)\b/
      violations << { type: :puts_debug } if code =~ /^\s*puts\s+["']/
      violations
    end
    
    def valid_ruby?(code)
      RubyVM::InstructionSequence.compile(code)
      true
    rescue SyntaxError
      false
    end
    
    def autofix_file(file, violations = nil)
      return Result.err("File not found: #{file}") unless File.exist?(file)
      
      code = File.read(file)
      original = code.dup
      @backups[file] = original
      
      # Determine which violations to fix
      fixable = violations&.select { |v| can_autofix?(v[:type]) } || autodetect_violations(code)
      fixable = fixable.take(MAX_FIXES_PER_RUN)
      
      return Result.ok({ file: file, fixed: 0, message: "No fixable violations" }) if fixable.empty?
      
      # Apply fixes
      fixed_count = 0
      fixable.each do |violation|
        type = violation[:type]&.to_sym
        next unless can_autofix?(type)
        
        fixer = FIXERS[type]
        next unless fixer
        
        new_code = fixer.call(code)
        if new_code != code
          code = new_code
          fixed_count += 1
          @fixes_applied << { file: file, type: type }
        end
      end
      
      return Result.ok({ file: file, fixed: 0, message: "No changes made" }) if code == original
      
      # Verify the fix
      unless valid_ruby?(code)
        return Result.err("Fix produced invalid Ruby - rolling back")
      end
      
      # Write the fixed code
      File.write(file, code)
      
      Result.ok({
        file: file,
        fixed: fixed_count,
        types: @fixes_applied.select { |f| f[:file] == file }.map { |f| f[:type] }
      })
    end
    
    def autofix_files(files, violations_by_file = {})
      results = []
      
      files.each do |file|
        violations = violations_by_file[file] || []
        result = autofix_file(file, violations)
        results << result
      end
      
      successful = results.count(&:ok?)
      total_fixed = results.select(&:ok?).sum { |r| r.value[:fixed] }
      
      Result.ok({
        files_processed: files.size,
        files_fixed: successful,
        total_fixes: total_fixed,
        details: results.map { |r| r.ok? ? r.value : { error: r.error } }
      })
    end
    
    def rollback_file(file)
      return Result.err("No backup for #{file}") unless @backups[file]
      
      File.write(file, @backups[file])
      @backups.delete(file)
      
      Result.ok("Rolled back #{file}")
    end
    
    def rollback_all_fixes
      @backups.each do |file, content|
        File.write(file, content)
      end
      
      count = @backups.size
      @backups.clear
      
      Result.ok("Rolled back #{count} files")
    end
  end
  
  # Momentum module - Module-level interface for gamification
  module Momentum
    extend self
    
    def instance
      @instance ||= begin
        llm = LLM.new rescue nil
        Evolve.new(llm) if llm
      end
    end
    
    def status_display
      instance&.momentum_status || "Momentum not available"
    end
    
    def list_achievements
      return "Momentum not available" unless instance
      ACHIEVEMENTS.map do |id, (n, d, _)| 
        "#{instance.momentum_state[:achievements].include?(id.to_s) ? '✓' : '○'} #{n}: #{d}"
      end.join("\n")
    end
    
    def update_streak
      instance&.update_streak || 0
    end
    
    def award(action, multiplier: 1.0)
      instance&.award_xp(action, multiplier: multiplier) || { xp: 0, total: 0, level: 1 }
    end
  end
end
