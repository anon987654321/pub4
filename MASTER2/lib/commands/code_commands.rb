# frozen_string_literal: true
require "shellwords"

module MASTER
  module Commands
    # Code analysis and refactoring commands
    module CodeCommands
      REFACTOR_USAGE = "Usage: autofix <file> [-p|--preview|-r|--raw|-a|--apply]"

      def autofix(args)
        target = parse_refactor_target(args)
        return Result.err(target[:error]) if target[:error]
        mode = target[:mode]

        case target[:type]
        when :snippet
          return autofix_snippet(target[:snippet], mode)
        when :directory
          return autofix_directory(target[:path], mode)
        end

        file = target[:path]

        path = File.expand_path(file)
        return Result.err("File not found: #{file}") unless File.exist?(path)

        original_code = File.read(path)

        bugs_found, hunt_result, pattern_matches = run_bug_hunting(original_code, file)
        critical_count = run_constitutional_validation(original_code, file)
        learned_issues = run_learnings_check(original_code)
        smells = run_smell_detection(original_code, file)

        total_issues = bugs_found + critical_count + learned_issues.size + smells.size

        if total_issues == 0
          puts "\nFile is clean! No refactoring needed."
          return Result.ok({ message: "No issues found" })
        end

        print_refactor_summary(bugs_found, critical_count, learned_issues, smells, total_issues)
        mode = :apply if mode == :preview
        puts "\nAuto mode: applying fixes for all detected violations."

        result = generate_and_apply_fixes(path, original_code, mode)
        record_refactor_learnings(file, original_code, result, bugs_found, pattern_matches)
        result
      end
      alias refactor autofix

      def chamber(file)
        autofix(file)
      end

      def evolve(path)
        path ||= MASTER.root
        evolver = Evolve.new
        result = evolver.run(path: path, dry_run: true)

        UI.header("Evolution Analysis (dry run)")
        puts [
          "  Files processed: #{result[:files_processed]}",
          "  Improvements found: #{result[:improvements]}",
          "  Cost: #{UI.currency_precise(result[:cost])}"
        ].join("\n")
        puts

        Result.ok(result)
      end

      def opportunities(path)
        path ||= MASTER.root
        if File.directory?(path) && defined?(Prescan)
          Prescan.run(path)
        end
        UI.header("Analyzing for opportunities")
        puts "  Path: #{path}"
        puts "  This may take a moment...\n\n"

        result = CodeReview.opportunities(path)
        if result.err?
          puts "  Error: #{result.error}"
          return result
        end

        categories = result.value
        %i[architectural micro micro_refinement ui_ux typography].each do |cat|
          items = categories[cat] || []
          next if items.empty?

          puts "  #{cat.to_s.gsub('_', ' ').upcase} (#{items.size})"
          items.first(5).each { |item| puts "    * #{item[:description] || item}" }
          puts
        end

        result
      end

      def print_axiom_stats
        summary = Review::AxiomStats.summary
        puts
        puts summary
        puts
      end

      def print_language_axioms(args)
        axioms = DB.axioms
        if axioms.empty?
          puts "\n  No language axioms found.\n"
          return
        end

        UI.header("Language Axioms")
        axioms.each do |axiom|
          name = axiom[:name] || axiom["name"] || "unnamed"
          desc = axiom[:description] || axiom["description"] || ""
          puts "  #{name.ljust(20)} #{desc[0, 50]}"
        end
        puts
      end

      # Manual deep-dive bug analysis
      def hunt_bugs(args)
        return puts "Usage: hunt <file>" unless args

        file = args.strip
        path = File.expand_path(file)
        return puts "File not found: #{file}" unless File.exist?(path)

        code = File.read(path)
        result = BugHunting.analyze(code, file_path: file)
        puts BugHunting.format(result)
      end

      # Manual constitutional validation
      def critique_code(args)
        return puts "Usage: critique <file>" unless args

        file = args.strip
        path = File.expand_path(file)
        return puts "File not found: #{file}" unless File.exist?(path)

        code = File.read(path)
        violations = Violations.analyze(code, path: file, llm: nil, conceptual: false)
        puts Violations.report(violations)
      end

      # Detect principle conflicts in constitution
      def detect_conflicts
        puts "Analyzing constitution for principle conflicts..."
        puts

        # For now, provide a simple implementation
        constitution_path = File.join(MASTER.root, 'data', 'constitution.yml')

        if File.exist?(constitution_path)
          puts "constitution: found"
          puts "review: manual check recommended for complex conflicts"
        else
          puts "! constitution: not found at #{constitution_path}"
        end
      end

      # Show what learnings would apply to this code
      def show_learnings(args)
        return puts "Usage: learn <file>" unless args

        file = args.strip
        path = File.expand_path(file)
        return puts "File not found: #{file}" unless File.exist?(path)

        code = File.read(path)
        issues = Learnings.apply_to(code)

        if issues.empty?
          puts "No learned patterns match this code"
        else
          puts "Matched Patterns:"
          issues.each do |issue|
            puts "\n#{issue[:severity].to_s.upcase}: #{issue[:description]}"
            puts "Learning ID: #{issue[:learning_id]}"
          end
        end
      end

      private

      def parse_refactor_target(args)
        usage = "#{REFACTOR_USAGE.sub("<file>", "<file|dir>")} or autofix --snippet \"<ruby code>\""
        return { error: usage } if args.nil? || args.to_s.strip.empty?

        parts = Shellwords.split(args.to_s)
        mode = extract_mode(parts)
        snippet_idx = parts.index("--snippet")

        if snippet_idx
          snippet = parts[(snippet_idx + 1)..]&.join(" ").to_s.strip
          return { error: "Snippet cannot be empty." } if snippet.empty?
          return { type: :snippet, snippet: snippet, mode: mode }
        end

        target = parts.find { |p| !p.start_with?("-") }
        return { error: usage } if target.nil? || target.empty?

        expanded = File.expand_path(target)
        if File.directory?(expanded)
          { type: :directory, path: expanded, mode: mode }
        else
          { type: :file, path: target, mode: mode }
        end
      rescue ArgumentError => e
        { error: "Invalid arguments: #{e.message}" }
      end

      def autofix_directory(path, mode)
        Prescan.run(path) if defined?(Prescan)
        mr = MultiRefactor.new(
          dry_run: mode != :apply,
          force_rewrite: true,
          align_axioms: true,
          include_all_files: true
        )
        mr.run(path: path)
      end

      def autofix_snippet(snippet, mode)
        filename = "snippet.rb"
        result = best_candidate_fix(filename, snippet)
        return result unless result.ok?

        candidate = render_output(lint_output(result.value[:final].to_s))
        case mode
        when :raw
          puts candidate
        else
          puts DiffView.unified_diff(snippet, candidate, filename: filename)
        end

        Result.ok(final: candidate, source: :snippet)
      end

      def run_bug_hunting(code, file)
        puts UI.bold("phase1: bug hunting...")
        hunt_result = BugHunting.analyze(code, file_path: file)
        pattern_matches = hunt_result.dig(:findings, :patterns, :matches) || []
        verification_bugs = hunt_result.dig(:findings, :verification, :bugs_found) || 0
        bugs_found = pattern_matches.size + verification_bugs

        if bugs_found > 0
          puts "bugs: #{bugs_found} found"
          puts BugHunting.format(hunt_result)
        else
          puts "bugs: clean"
        end
        [bugs_found, hunt_result, pattern_matches]
      end

      def run_constitutional_validation(code, file)
        puts UI.bold("phase2: constitutional validation...")
        violations = Violations.analyze(code, path: file, llm: nil, conceptual: false)
        critical_count = violations[:literal].count { |v| v[:severity] == :error }

        if critical_count > 0
          puts "#{critical_count} critical violations"
          puts Violations.report(violations)
        else
          puts "violations: clean"
        end
        critical_count
      end

      def run_learnings_check(code)
        puts UI.bold("phase3: checking learnings...")
        learned_issues = Learnings.apply_to(code)

        if learned_issues.any?
          puts "Found #{learned_issues.size} known patterns:"
          learned_issues.each { |issue| puts "  * #{issue[:description]} (#{issue[:severity]})" }
        else
          puts "patterns: clean"
        end
        learned_issues
      end

      def run_smell_detection(code, file)
        puts UI.bold("phase4: smell detection...")
        smells = Smells.analyze(code, file)

        if smells.any?
          puts "Found #{smells.size} code smells"
          smells.first(5).each { |smell| puts "  * #{smell[:smell]}: #{smell[:message]}" }
        else
          puts "smells: clean"
        end
        smells
      end

      def print_refactor_summary(bugs_found, critical_count, learned_issues, smells, total_issues)
        puts [
          UI.bold("summary:"),
          "  Bugs: #{bugs_found}",
          "  Critical Violations: #{critical_count}",
          "  Known Patterns: #{learned_issues.size}",
          "  Code Smells: #{smells.size}",
          "  TOTAL: #{total_issues} issues"
        ].join("\n")
      end

      def generate_and_apply_fixes(path, original_code, mode)
        puts UI.bold("phase5: generating fixes...")
        result = if obvious_issue?(path, original_code)
          best_candidate_fix(path, original_code)
        else
          chamber = Council.new
          chamber.deliberate(original_code, filename: File.basename(path))
        end

        return result unless result.ok? && result.value[:final]

        proposed_code = result.value[:final]
        council_info = result.value[:council]
        linted = lint_output(proposed_code)
        rendered = render_output(linted)

        case mode
        when :raw   then display_raw_output(result, rendered, council_info)
        when :apply then apply_refactor_auto(path, original_code, rendered, result, council_info)
        else             display_preview(path, original_code, rendered, result, council_info)
        end
        result
      end

      def apply_refactor_auto(path, original, proposed, result, council_info)
        diff = DiffView.unified_diff(original, proposed, filename: File.basename(path))
        puts "\n  Proposals: #{result.value[:proposals]&.size || 1}"
        puts "  Cost: #{UI.currency_precise(result.value[:cost] || 0.0)}"
        if (summary = format_council_summary(council_info))
          puts summary
        end
        puts "\n#{diff}"

        Undo.track_edit(path, original)
        clean = TextHygiene.normalize(proposed, filename: path)
        File.write(path, clean)
        enforce_ruby_style!(path)
        puts "  refactor: applied to #{path}"
        puts "  (Use 'undo' command to revert)"
      end

      def enforce_ruby_style!(path)
        return unless File.extname(path) == ".rb"
        return unless defined?(RubocopDetector) && RubocopDetector.installed?

        system("rubocop", "-A", path, out: File::NULL, err: File::NULL)
      rescue StandardError
        nil
      end

      def obvious_issue?(path, code)
        ext = File.extname(path)
        return true if code.match?(/[ \t]+$/) || code.include?("\r\n")
        return true if code.match?(/\bteh\b/i) || code.match?(/\brecieve\b/i)
        return true if code.match?(/^\s*\t+/)
        return true if code.match?(/^\s*(binding\.pry|debugger|byebug)/)
        return true if ext == ".rb" && !MASTER::Utils.valid_ruby?(code)

        false
      end

      def best_candidate_fix(path, original_code)
        puts "obvious-fix: generating multiple candidates and selecting best..."
        candidates = []

        candidates << { source: :heuristic, code: heuristic_fix(original_code) }

        if defined?(Review::Fixer)
          tmp = "#{path}.obvious_tmp"
          begin
            File.write(tmp, original_code)
            fixer = Review::Fixer.new(mode: :aggressive)
            fixer.fix(tmp)
            candidates << { source: :review_fixer, code: File.read(tmp) } if File.exist?(tmp)
          ensure
            File.delete(tmp) if File.exist?(tmp)
          end
        end

        chamber = Council.new
        llm_result = chamber.deliberate(original_code, filename: File.basename(path))
        if llm_result.ok? && llm_result.value[:final].to_s.strip != ""
          candidates << {
            source: :council,
            code: llm_result.value[:final],
            council: llm_result.value[:council],
            proposals: llm_result.value[:proposals],
            cost: llm_result.value[:cost]
          }
        end

        scored = candidates.uniq { |c| c[:code] }.map do |candidate|
          metrics = score_candidate(path, candidate[:code])
          score = if defined?(DecisionEngine)
            DecisionEngine.score(
              impact: metrics[:impact],
              confidence: metrics[:confidence],
              cost: metrics[:cost]
            )
          else
            metrics[:fallback_score]
          end
          candidate.merge(score: score)
        end
        best = scored.max_by { |c| c[:score] }
        return Result.err("No viable fix candidate generated.") unless best

        Result.ok(
          final: best[:code],
          council: best[:council],
          proposals: best[:proposals] || [],
          cost: best[:cost] || 0.0
        )
      end

      def heuristic_fix(code)
        code
          .gsub("\r\n", "\n")
          .gsub(/[ \t]+$/, "")
          .gsub(/\bteh\b/i, "the")
          .gsub(/\brecieve\b/i, "receive")
          .gsub(/^\t+/) { |m| "  " * m.length }
      end

      def score_candidate(path, code)
        impact = 1.0
        confidence = 1.0
        cost = 1.0
        fallback_score = 0.0

        if File.extname(path) == ".rb"
          unless MASTER::Utils.valid_ruby?(code)
            return { impact: 0.0, confidence: 0.0, cost: 10_000.0, fallback_score: -10_000.0 }
          end
          impact += 0.8
          fallback_score += 200
        end

        violations = Violations.analyze(code, path: path, llm: nil, conceptual: false) rescue { literal: [], conceptual: [] }
        literal = Array(violations[:literal]).size
        conceptual = Array(violations[:conceptual]).size
        confidence -= (literal * 0.08) + (conceptual * 0.04)
        fallback_score -= literal * 5
        fallback_score -= conceptual * 3

        smells = Smells.analyze(code, path) rescue []
        cost += (literal * 0.2) + (conceptual * 0.1) + (smells.size * 0.05)
        confidence -= smells.size * 0.01
        fallback_score -= smells.size

        confidence = [[confidence, 0.01].max, 1.0].min
        { impact: impact, confidence: confidence, cost: cost, fallback_score: fallback_score }
      end

      def record_refactor_learnings(file, original_code, result, bugs_found, pattern_matches)
        return unless result.ok? && result.value[:final] && bugs_found > 0

        puts UI.bold("phase6: recording learnings...")
        rendered = render_output(lint_output(result.value[:final]))

        pattern_matches.first(3).each do |match|
          pattern = Learnings.extract_pattern_from_fix(original_code, rendered)
          next unless pattern

          Learnings.record(
            category: :bug_pattern, pattern: pattern,
            description: "Auto-discovered during refactor of #{file}: #{match[:name]}",
            example: "Fixed in #{file}", severity: :info
          )
        end
        puts "learnings: updated"
      end

    end
  end
end
