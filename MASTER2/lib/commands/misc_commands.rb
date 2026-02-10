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
        return Result.err("Usage: ideate <topic>") unless topic && !topic.empty?

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

        UI.header("Cinematic Presets")
        result.value[:presets].each do |preset|
          source = preset[:source] == 'builtin' ? UI.pastel.dim('[builtin]') : UI.pastel.cyan('[custom]')
          puts "  • #{UI.pastel.bold(preset[:name])} #{source}"
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

        UI.info("Applying preset '#{preset_name}' to #{input_path}...")
        
        result = Cinematic.apply_preset(input_path, preset_name)
        
        if result.ok?
          output = result.value[:final]
          UI.success("Pipeline complete!")
          puts "  Output: #{output}"
        else
          UI.error("Pipeline failed: #{result.error}")
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
          UI.success("Discovered #{discoveries.size} styles!")
          
          discoveries.each_with_index do |d, i|
            puts "  #{i + 1}. Score: #{d[:score].round(2)} | #{d[:pipeline].stages.size} stages"
          end
        else
          UI.error("Discovery failed: #{result.error}")
        end
      end

      def build_cinematic_pipeline
        UI.header("Build Custom Pipeline")
        puts "  (Interactive pipeline builder coming soon)"
        puts "  For now, use the Ruby API:"
        puts
        puts "    pipeline = MASTER::Cinematic::Pipeline.new"
        puts "    pipeline.chain('stability-ai/sdxl', { prompt: 'cinematic' })"
        puts "    result = pipeline.execute(input)"
        puts
      end
    end
  end
end
