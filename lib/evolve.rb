# frozen_string_literal: true

module MASTER
  # Self-improvement workflow
  # Analyzes codebase, identifies refinements, applies them, repeats until convergence
  class Evolve
    MAX_ITERATIONS = 100
    CONVERGENCE_THRESHOLD = 0.02  # Stop when improvement rate drops below 2%
    MIN_REFINEMENTS = 2           # Stop when fewer than this found
    REFINEMENT_FILE = File.join(Paths.config, 'refinements.yml')
    WISHLIST_FILE = File.join(Paths.config, 'wishlist.yml')
    EVOLUTION_LOG = File.join(Paths.data, 'evolution.log')

    def initialize(llm, chamber = nil)
      @llm = llm
      @chamber = chamber || Chamber.new(llm)
      @creative = CreativeChamber.new(llm)
      @intro = Introspection.new(llm)
      @iteration = 0
      @cost = 0.0
      @history = []  # Track improvement rates
    end

    # Continuous evolution until convergence
    def converge(target: Paths.lib, budget: 5.0)
      log "Convergence loop started: #{target}"
      log "Budget: $#{budget}, threshold: #{CONVERGENCE_THRESHOLD * 100}%"

      prev_score = 0
      stall_count = 0

      loop do
        @iteration += 1

        # Run one evolution cycle
        cycle_result = run_cycle(target)
        break if cycle_result[:stop]

        # Track improvement
        current_score = cycle_result[:applied]
        improvement_rate = prev_score > 0 ? (current_score - prev_score).abs.to_f / prev_score : 1.0
        @history << { iteration: @iteration, applied: current_score, rate: improvement_rate }

        log "Cycle #{@iteration}: #{current_score} applied, rate: #{(improvement_rate * 100).round(1)}%"

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

      # Final summary
      summary = convergence_summary
      log summary

      # Generate wishlist for next session
      wishlist = generate_wishlist(target)
      save_wishlist(wishlist)

      {
        iterations: @iteration,
        cost: @cost,
        history: @history,
        converged: stall_count >= 3 || @history.last&.dig(:applied).to_i < MIN_REFINEMENTS,
        wishlist: wishlist
      }
    end

    # Single evolution cycle
    def run_cycle(target)
      # 1. Analyze current state
      refinements = analyze(target)
      if refinements.empty?
        log "No refinements found"
        return { stop: true, applied: 0 }
      end

      # 2. Prioritize by impact
      prioritized = prioritize(refinements)
      log "Found #{prioritized.size} refinement opportunities"

      # 3. Apply top refinements
      applied = apply_top(prioritized, count: 5)

      # 4. Validate changes
      unless validate(target)
        log "Validation failed, reverting"
        revert_last
        return { stop: false, applied: 0 }
      end

      # 5. Commit if successful
      if applied > 0
        commit_changes("evolve: #{applied} refinements, iteration #{@iteration}")
      end

      # 6. Introspect
      reflect

      { stop: false, applied: applied }
    end

    # Full single-pass evolution (original method)
    def run(target: Paths.lib, budget: 1.0)
      log "Evolution started: #{target}"

      until @iteration >= MAX_ITERATIONS || @cost >= budget
        result = run_cycle(target)
        break if result[:stop] || result[:applied] == 0
      end

      wishlist = generate_wishlist(target)
      save_wishlist(wishlist)

      log "Evolution complete: #{@iteration} iterations, $#{'%.4f' % @cost}"
      { iterations: @iteration, cost: @cost, wishlist: wishlist }
    end

    # Analyze codebase for refinement opportunities
    def analyze(target)
      files = collect_files(target)
      refinements = []

      files.each do |file|
        next if @cost >= 0.5 # Per-file budget

        code = File.read(file) rescue next
        next if code.length > 10_000 # Skip large files

        prompt = <<~PROMPT
          Analyze this code for micro-refinement opportunities.
          Return 3-5 specific improvements. For each:
          - Line number (approximate)
          - What to change (one sentence)
          - Why (impact: clarity/performance/safety)
          - Effort: low/medium/high

          Only suggest changes that are:
          - Surgical (1-5 lines)
          - Safe (won't break behavior)
          - Valuable (not style nitpicks)

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

      <<~SUMMARY
        Convergence Summary
        -------------------
        Iterations: #{@iteration}
        Total refinements: #{total_applied}
        Average improvement rate: #{(avg_rate * 100).round(1)}%
        Total cost: $#{'%.4f' % @cost}
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
