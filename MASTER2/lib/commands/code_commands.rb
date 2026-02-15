# frozen_string_literal: true

module MASTER
  module Commands
    # Code analysis and refactoring commands
    module CodeCommands
      def refactor(args)
        return Result.err("Usage: refactor <file> [--preview|--raw|--apply]") unless args

        parts = args.strip.split(/\s+/)
        return Result.err("Usage: refactor <file> [--preview|--raw|--apply]") if parts.empty?
        
        file = parts.first
        
        # Check if the first argument looks like a flag
        if file&.start_with?("--")
          return Result.err("Usage: refactor <file> [--preview|--raw|--apply]")
        end
        
        mode = extract_mode(parts[1..-1])

        return Result.err("File path cannot be empty") if file.nil? || file.empty?
        
        path = File.expand_path(file)
        return Result.err("File not found: #{file}") unless File.exist?(path)

        original_code = File.read(path)
        
        # PHASE 1: Bug Hunting (8-phase analysis)
        puts UI.bold("🔍 PHASE 1: Bug Hunting (8-phase analysis)...")
        hunt_result = BugHunting.analyze(original_code, file_path: file)
        
        # Count actual bugs from patterns
        pattern_matches = hunt_result.dig(:findings, :patterns, :matches) || []
        verification_bugs = hunt_result.dig(:findings, :verification, :bugs_found) || 0
        bugs_found = pattern_matches.size + verification_bugs
        
        if bugs_found > 0
          puts "⚠️  Found #{bugs_found} potential bugs"
          puts BugHunting.format(hunt_result)
        else
          puts "✓ No bugs detected"
        end
        
        # PHASE 2: Constitutional Validation
        puts "\n" + UI.bold("🧠 PHASE 2: Constitutional Validation...")
        violations = Violations.analyze(original_code, path: file, llm: nil, conceptual: false)
        critical_count = violations[:literal].count { |v| v[:severity] == :error }
        
        if critical_count > 0
          puts "🚨 #{critical_count} critical violations"
          puts Violations.report(violations)
        else
          puts "✓ No constitutional violations"
        end
        
        # PHASE 3: Checking Learnings Database
        puts "\n" + UI.bold("📚 PHASE 3: Checking Learnings Database...")
        learned_issues = Learnings.apply_to(original_code)
        
        if learned_issues.any?
          puts "💡 Found #{learned_issues.size} known patterns:"
          learned_issues.each do |issue|
            puts "  • #{issue[:description]} (#{issue[:severity]})"
          end
        else
          puts "✓ No known patterns detected"
        end
        
        # PHASE 4: Code Smell Detection
        puts "\n" + UI.bold("👃 PHASE 4: Code Smell Detection...")
        smells = Smells.analyze(original_code, file)
        
        if smells.any?
          puts "📋 Found #{smells.size} code smells"
          smells.first(5).each do |smell|
            puts "  • #{smell[:smell]}: #{smell[:message]}"
          end
        else
          puts "✓ No code smells"
        end
        
        # Summary
        total_issues = bugs_found + critical_count + learned_issues.size + smells.size
        
        if total_issues == 0
          puts "\n✨ File is clean! No refactoring needed."
          return Result.ok({ message: "No issues found" })
        end
        
        puts "\n" + UI.bold("📊 SUMMARY:")
        puts "  Bugs: #{bugs_found}"
        puts "  Critical Violations: #{critical_count}"
        puts "  Known Patterns: #{learned_issues.size}"
        puts "  Code Smells: #{smells.size}"
        puts "  TOTAL: #{total_issues} issues"
        
        # Confirmation gate
        print "\n🤔 Proceed with automatic fixes? (y/n): "
        response = get_user_input&.chomp&.downcase
        
        unless response == 'y' || response == 'yes'
          puts "Cancelled."
          return Result.ok({ message: "Cancelled by user" })
        end
        
        # PHASE 5: Generating Fixes
        puts "\n" + UI.bold("🤖 PHASE 5: Generating Fixes...")
        chamber = Chamber.new
        result = chamber.deliberate(original_code, filename: File.basename(path))

        return result unless result.ok? && result.value[:final]

        proposed_code = result.value[:final]
        council_info = result.value[:council]

        # Pass through lint + render stages for governance
        linted = lint_output(proposed_code)
        rendered = render_output(linted)
        
        fix_successful = false

        # Format output based on mode
        case mode
        when :raw
          display_raw_output(result, rendered, council_info)
          fix_successful = true
        when :apply
          apply_refactor(path, original_code, rendered, result, council_info)
          fix_successful = true
        else # :preview (default)
          display_preview(path, original_code, rendered, result, council_info)
          fix_successful = true
        end
        
        # PHASE 6: Recording Learnings
        if fix_successful && bugs_found > 0
          puts "\n" + UI.bold("📝 PHASE 6: Recording Learnings...")
          
          # Extract pattern from bugs that were fixed
          pattern_matches.first(3).each do |match|
            pattern = Learnings.extract_pattern_from_fix(original_code, rendered)
            if pattern
              Learnings.record(
                category: :bug_pattern,
                pattern: pattern,
                description: "Auto-discovered during refactor of #{file}: #{match[:name]}",
                example: "Fixed in #{file}",
                severity: :info
              )
            end
          end
          
          puts "✓ Learnings updated"
        end

        result
      end

      def chamber(file)
        refactor(file)
      end

      def evolve(path)
        path ||= MASTER.root
        evolver = Evolve.new
        result = evolver.run(path: path, dry_run: true)

        UI.header("Evolution Analysis (dry run)")
        puts "  Files processed: #{result[:files_processed]}"
        puts "  Improvements found: #{result[:improvements]}"
        puts "  Cost: #{UI.currency_precise(result[:cost])}"
        puts

        Result.ok(result)
      end

      def opportunities(path)
        path ||= MASTER.root
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
          items.first(5).each { |item| puts "    • #{item[:description] || item}" }
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
        
        # This would require analyzing the constitution file
        # For now, provide a simple implementation
        constitution_path = File.join(MASTER.root, 'data', 'constitution.yml')
        
        if File.exist?(constitution_path)
          puts "✓ Constitution file found"
          puts "  Manual review recommended for complex conflicts"
        else
          puts "⚠ Constitution file not found at: #{constitution_path}"
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
      
      # Abstraction for user input to improve testability
      def get_user_input
        $stdin.gets
      end
    end
  end
end
