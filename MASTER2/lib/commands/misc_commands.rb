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
    end
  end
end
