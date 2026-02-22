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

        bugs_found, _, pattern_matches = run_bug_hunting(original_code, file)
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
          "  Cost: #{UI.currency_precise(result[:cost])}",
        ].join("\n")
        puts

        Result.ok(result)
      end

      def opportunities(path)
        path ||= MASTER.root
        Prescan.run(path) if File.directory?(path) && defined?(Prescan)
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

      def print_language_axioms(_args)
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
        constitution_path = File.join(MASTER.root, "data", "constitution.yml")

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

      def scan_code(args)
        path = args.nil? || args.strip.empty? ? MASTER.root : File.expand_path(args.strip)

        unless File.exist?(path)
          puts "Path not found: #{path}"
          return Result.err("Path not found: #{path}")
        end

        state_path = Paths.var_file("scan_state.json")

        if (args.nil? || args.strip.empty?) && File.exist?(state_path)
          cached = JSON.parse(File.read(state_path), symbolize_names: true)
          age = ((Time.now - Time.parse(cached[:scanned_at])) / 60).round
          puts "Last scan: #{cached[:scanned_at]} (#{age}m ago)"
          puts "  Issues: #{cached[:total_issues]} (#{cached[:critical]} critical, #{cached[:major]} major)"
          puts "  Pass 'scan .' to re-scan"
          return Result.ok(cached)
        end

        UI.header("Scanning: #{path}")
        result = if File.file?(path)
                   file_result = Review::Scanner.analyze_file(path)
                   {
                     files: { path => file_result },
                     total_issues: file_result[:issues].size,
                     critical: file_result[:issues].count { |i| i[:severity] == :critical },
                     major: file_result[:issues].count { |i| i[:severity] == :major },
                     average_score: file_result[:score].to_f,
                   }
                 else
                   Review::Scanner.analyze_directory(path)
                 end

        result[:files].each do |file, r|
          next if r[:issues].empty?

          rel = file.sub("#{MASTER.root}/", "")
          puts "  #{r[:grade]} #{rel}"
          r[:issues].each { |issue| puts "    #{issue[:severity].to_s.upcase}: #{issue[:message]}" }
        end

        puts
        puts "  Files: #{result[:files].size}"
        puts "  Total issues: #{result[:total_issues]} (#{result[:critical]} critical, #{result[:major]} major)"
        puts "  Average score: #{result[:average_score].round(2)}/#{Review::Scanner::GOOD_PATTERNS.size}"

        state = {
          scanned_at: Time.now.utc.iso8601,
          path: path,
          total_issues: result[:total_issues],
          critical: result[:critical],
          major: result[:major],
          average_score: result[:average_score].round(2),
          files: result[:files].transform_values do |r|
            { issues: r[:issues].size, score: r[:score], grade: r[:grade] }
          end,
        }
        File.write(state_path, JSON.generate(state))
        puts "  Scan state saved → var/scan_state.json"

        Result.ok(state)
      end

      private

      def parse_refactor_target(args)
        usage = "#{REFACTOR_USAGE.sub('<file>', '<file|dir>')} or autofix --snippet \"<ruby code>\""
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
          include_all_files: true,
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
          "  TOTAL: #{total_issues} issues",
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
            FileUtils.rm_f(tmp)
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
            cost: llm_result.value[:cost],
          }
        end

        scored = candidates.uniq { |c| c[:code] }.map do |candidate|
          metrics = score_candidate(path, candidate[:code])
          score = if defined?(DecisionEngine)
                    DecisionEngine.score(
                      impact: metrics[:impact],
                      confidence: metrics[:confidence],
                      cost: metrics[:cost],
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
          cost: best[:cost] || 0.0,
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

        violations = begin
          Violations.analyze(code, path: path, llm: nil,
                                   conceptual: false)
        rescue StandardError
          { literal: [], conceptual: [] }
        end
        literal = Array(violations[:literal]).size
        conceptual = Array(violations[:conceptual]).size
        confidence -= (literal * 0.08) + (conceptual * 0.04)
        fallback_score -= literal * 5
        fallback_score -= conceptual * 3

        smells = begin
          Smells.analyze(code, path)
        rescue StandardError
          []
        end
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
      end

      # `deps [symbol]` — show what files require a given module/symbol.
      # Uses DependencyMap which is more accurate than grepping require lines.
      def print_deps(args)
        require_relative "../dependency_map"
        require_relative "../introspection/friction_recorder"

        if args.nil? || args.strip.empty?
          # No argument: show full graph summary
          graph = DependencyMap.build
          puts "dependency graph: #{graph.size} files"
          graph.each do |file, info|
            rel = file.sub("#{MASTER.root}/", "")
            next if info[:defines].empty?

            puts "  #{rel}: defines #{info[:defines].first(3).join(', ')}"
          end
        else
          # Argument: show who requires this symbol
          symbol = args.strip
          graph  = DependencyMap.build
          lib_root = File.join(MASTER.root, "lib")
          matches = graph.select { |_, info| info[:references].any? { |r| r.include?(symbol) } }
          if matches.empty?
            puts "deps: no references to #{symbol} found"
          else
            puts "deps: #{matches.size} file(s) reference #{symbol}"
            matches.each_key { |f| puts "  #{f.sub("#{lib_root}/", "")}" }
          end
          # Record if agent was greping for deps — friction signal 8
          MASTER::Friction::FrictionRecorder.record(:dep_graph_blind, symbol: symbol) if args.include?("grep")
        end
        HANDLED
      end

      # `introspect` — session retrospective: friction events, remedies, config drift.
      def print_introspection(args)
        require_relative "../introspection/session_retrospective"
        use_llm = args.to_s.include?("--llm")
        report  = Friction::SessionRetrospective.run(use_llm: use_llm)
        puts Friction::SessionRetrospective.format(report)
        HANDLED
      end

      # `config-drift` — find YAML keys in data/ with no Ruby reader.
      def print_config_drift
        require_relative "../introspection/session_retrospective"
        orphans = Friction::SessionRetrospective.audit_config_drift
        if orphans.empty?
          puts "config-drift: clean — all YAML keys have Ruby readers"
        else
          puts "config-drift: #{orphans.size} orphaned key(s):"
          orphans.each { |o| puts "  #{o[:file]}: #{o[:key]}" }
        end
        HANDLED
      end
    end
  end
end
