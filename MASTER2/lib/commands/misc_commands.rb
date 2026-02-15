# frozen_string_literal: true

module MASTER
  module Commands
    # Miscellaneous commands
    module MiscCommands
      def speak(text)
        return puts "  Usage: speak <text>" unless text

        result = Speech.speak(text)
        puts "  TTS Error: #{result.error}" if result.err?
      end

      def fix_code(args)
        path = args&.strip
        if path.nil? || path.empty?
          path = "."
        end

        if File.directory?(path)
          fixer = AutoFixer.new(mode: :moderate)
          result = fixer.fix_directory(path)
          if result.ok?
            puts "  Fixed #{result.value[:files_fixed]} files, #{result.value[:issues_fixed]} issues"
          else
            puts "  Error: #{result.error}"
          end
        else
          fixer = AutoFixer.new(mode: :moderate)
          result = fixer.fix(path)
          if result.ok?
            puts "  Fixed: #{path}"
          else
            puts "  Error: #{result.error}"
          end
        end
      end

      def browse_url(args)
        return puts "  Usage: browse <url>" unless args

        url = args.strip
        if defined?(Web)
          result = Web.browse(url)
          if result.ok?
            content = result.value[:content]
            puts "\n  Content (first 1000 chars):\n#{content[0..1000]}\n"
          else
            puts "  Error: #{result.error}"
          end
        else
          puts "  Web module not available"
        end
      end

      def ideate(args)
        topic = args&.strip
        return Result.err("Usage: ideate <topic>.") unless topic && !topic.empty?

        UI.header("Ideating on: #{topic}")
        prompt = <<~PROMPT
          Brainstorm 5 creative ideas for: #{topic}

          Format:
          1. Idea name — brief description
          ...
        PROMPT

        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?

        puts result.value[:content]
        puts

        Result.ok(result.value[:content])
      end

      def session_capture
        # Capture insights from current session
        if defined?(SessionCapture)
          SessionCapture.capture
        else
          puts "  SessionCapture not available"
        end
      end

      def review_captures
        # Review all session captures
        if defined?(SessionCapture)
          result = SessionCapture.review
          if result.ok?
            captures = result.value[:captures]
            puts "\n  #{captures.size} session captures:"
            captures.last(10).each do |c|
              puts "\n  #{UI.dim(c[:timestamp])}"
              c[:answers].each do |category, answer|
                puts "    #{UI.bold(category)}: #{answer}"
              end
            end
            puts
          else
            puts "  #{result.error}"
          end
        else
          puts "  SessionCapture not available"
        end
      end

      def print_health
        UI.header("Health Check")
        checks = []

        # Check API key
        api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
        checks << { name: "API Key", ok: !api_key.nil? && !api_key.empty? }

        # Check var directory writable
        var_ok = File.writable?(Paths.var) rescue false
        checks << { name: "Var writable", ok: var_ok }

        # Check DB initialized
        db_ok = DB.axioms.any? rescue false
        checks << { name: "DB seeded", ok: db_ok }

        # Check models available
        model = LLM.select_available_model
        checks << { name: "Models available", ok: !model.nil? }

        # Check budget
        budget_ok = LLM.budget_remaining > 0
        checks << { name: "Budget remaining", ok: budget_ok }

        checks.each do |c|
          status = c[:ok] ? UI.pastel.green("✓") : UI.pastel.red("✗")
          puts "  #{status} #{c[:name]}"
        end

        all_ok = checks.all? { |c| c[:ok] }
        puts
        puts all_ok ? "  System healthy." : "  Some checks failed."
        puts
      end

      # Cinematic AI Pipeline Commands

      def cinematic(args)
        parts = args&.split || []
        return show_cinematic_help if parts.empty?

        command = parts.first
        case command
        when 'list'
          list_cinematic_presets
        when 'apply'
          apply_cinematic_preset(parts[1], parts[2])
        when 'discover'
          discover_cinematic_styles(parts[1], samples: (parts[2] || 10).to_i)
        when 'build'
          build_cinematic_pipeline
        else
          show_cinematic_help
        end
      end

      private

      def show_cinematic_help
        puts <<~HELP

          Cinematic AI Pipeline Commands:

            cinematic list                     List available presets
            cinematic apply <preset> <input>   Apply preset to image
            cinematic discover <input> [n]     Discover new styles (n samples)
            cinematic build                    Interactive pipeline builder

          Presets: blade-runner, wes-anderson, noir, golden-hour, teal-orange

        HELP
      end

      def list_cinematic_presets
        result = Cinematic.list_presets
        return puts "  Error: #{result.error}" if result.err?

        puts "\nCinematic Presets\n" + ("-" * 40)
        result.value[:presets].each do |preset|
          source = preset[:source] == 'builtin' ? '[builtin]' : '[custom]'
          puts "  • #{preset[:name]} #{source}"
          puts "    #{preset[:description]}"
          puts
        end
      end

      def apply_cinematic_preset(preset_name, input_path)
        unless preset_name && input_path
          return puts "  Usage: cinematic apply <preset> <input>"
        end

        unless File.exist?(input_path)
          return puts "  Error: File not found: #{input_path}"
        end

        puts "  Applying preset '#{preset_name}' to #{input_path}..."

        result = Cinematic.apply_preset(input_path, preset_name)

        if result.ok?
          output = result.value[:final]
          puts "  ✓ Pipeline complete!"
          puts "  Output: #{output}"
        else
          puts "  ✗ Pipeline failed: #{result.error}"
        end
      end

      def discover_cinematic_styles(input_path, samples: 10)
        unless input_path
          return puts "  Usage: cinematic discover <input> [samples]"
        end

        unless File.exist?(input_path)
          return puts "  Error: File not found: #{input_path}"
        end

        result = Cinematic.discover_style(input_path, samples: samples)

        if result.ok?
          discoveries = result.value[:discoveries]
          puts "  ✓ Discovered #{discoveries.size} styles!"

          discoveries.each_with_index do |d, i|
            puts "  #{i + 1}. Score: #{d[:score].round(2)} | #{d[:pipeline].stages.size} stages"
          end
        else
          puts "  ✗ Discovery failed: #{result.error}"
        end
      end

      def build_cinematic_pipeline
        puts "\nBuild Custom Pipeline\n" + ("-" * 40)
        puts "  (Interactive pipeline builder coming soon)"
        puts "  For now, use the Ruby API:"
        puts
        puts "    pipeline = MASTER::Cinematic::Pipeline.new"
        puts "    pipeline.chain('stability-ai/sdxl', { prompt: 'cinematic' })"
        puts "    result = pipeline.execute(input)"
        puts
      end

      # Persona management commands
      def manage_persona(args)
        parts = args&.split || []
        return show_persona_help if parts.empty?

        command = parts[0]
        name = parts[1]

        case command
        when "activate"
          return puts "  Usage: persona activate <name>" unless name

          if defined?(Personas)
            result = Personas.activate(name)
            if result.err?
              puts "  Error: #{result.error}"
            end
          else
            puts "  Personas module not available"
          end
        when "deactivate"
          if defined?(Personas)
            Personas.deactivate
          else
            puts "  Personas module not available"
          end
        when "list"
          list_personas
        else
          show_persona_help
        end
      end

      def list_personas
        return puts "  Personas module not available" unless defined?(Personas)

        personas = Personas.list
        if personas.empty?
          puts "  No personas available"
        else
          puts "\nAvailable Personas:"
          personas.each do |name|
            active_marker = defined?(Personas.active) && Personas.active&.dig(:name) == name ? " *" : ""
            puts "  • #{name}#{active_marker}"
          end
        end
      end

      def show_persona_help
        puts <<~HELP

          Persona Commands:

            persona activate <name>    Activate a persona
            persona deactivate         Deactivate current persona
            persona list               List available personas

        HELP
      end



      # Semantic cache management
      def show_cache_stats(args)
        return puts "  SemanticCache not available" unless defined?(SemanticCache)

        case args&.strip
        when "clear"
          SemanticCache.clear!
          UI.success("Cache cleared")
        when "stats", nil, ""
          stats = SemanticCache.stats
          UI.header("Semantic Cache")
          puts "  Entries: #{stats[:entries]}"
          puts "  Size: #{stats[:size_human]}"
          puts "  Dir: #{stats[:cache_dir]}"
          puts
        else
          puts "  Usage: cache [stats|clear]"
        end
      end

      # Multi-file refactoring
      def multi_refactor(args)
        return puts "  MultiRefactor not available" unless defined?(MultiRefactor)

        path = args&.split&.first || MASTER.root
        dry_run = !args&.include?("--apply")
        mr = MultiRefactor.new(dry_run: dry_run)
        result = mr.run(path: path)
        result
      end

      # Full self-run across entire pub4 repo
      def selfrun_full(args)
        return puts "  MultiRefactor not available" unless defined?(MultiRefactor)

        puts "MASTER2 Self-Run: Analyzing entire pub4 repository..."
        pub4_root = File.expand_path("../..", MASTER.root)  # Go up from MASTER2/ to pub4/

        # Phase 1: Self-refactor MASTER2 itself
        puts "\n=== Phase 1: Self-Refactoring MASTER2 ==="
        mr = MultiRefactor.new(dry_run: !args&.include?("--apply"), budget_cap: 1.0)
        mr.run(path: File.join(pub4_root, "MASTER2", "lib"))

        # Phase 2: Deploy scripts
        puts "\n=== Phase 2: Deploy Scripts ==="
        mr2 = MultiRefactor.new(dry_run: !args&.include?("--apply"), budget_cap: 1.0)
        mr2.run(path: File.join(pub4_root, "deploy"))

        # Phase 3: Business plans (HTML)
        puts "\n=== Phase 3: Business Plans ==="
        mr3 = MultiRefactor.new(dry_run: !args&.include?("--apply"), budget_cap: 0.5)
        mr3.run(path: File.join(pub4_root, "bp"))

        # Phase 4: Self-test
        puts "\n=== Phase 4: Self-Test ==="
        Introspection.run if defined?(Introspection)

        Result.ok("Self-run complete")
      end
    end
  end
end
