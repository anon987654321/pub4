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
        chamber = Chamber.new
        result = chamber.deliberate(original_code, filename: File.basename(path))

        return result unless result.ok? && result.value[:final]

        proposed_code = result.value[:final]
        council_info = result.value[:council]

        # Pass through lint + render stages for governance
        linted = lint_output(proposed_code)
        rendered = render_output(linted)

        # Format output based on mode
        case mode
        when :raw
          display_raw_output(result, rendered, council_info)
        when :apply
          apply_refactor(path, original_code, rendered, result, council_info)
        else # :preview (default)
          display_preview(path, original_code, rendered, result, council_info)
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
        if result[:error]
          puts "  Error: #{result[:error]}"
        else
          %i[architectural micro_refinement ui_ux typography].each do |cat|
            items = result[cat] || []
            next if items.empty?

            puts "  #{cat.to_s.gsub('_', ' ').upcase} (#{items.size})"
            items.first(5).each { |item| puts "    • #{item}" }
            puts
          end
        end

        Result.ok(result)
      end

      def print_axiom_stats
        summary = AxiomStats.summary
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
    end
  end
end
