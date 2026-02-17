# frozen_string_literal: true

require_relative 'misc_commands/selftest_full'
require_relative 'misc_commands/cinematic_persona'

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
          1. Idea name -- brief description
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
            puts "#{captures.size} session captures:"
            captures.last(10).each do |c|
              puts "#{UI.dim(c[:timestamp])}"
              c[:answers].each do |category, answer|
                puts "  #{UI.bold(category)}: #{answer}"
              end
            end
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
        model = LLM.select_model
        checks << { name: "Models available", ok: !model.nil? }

        checks.each do |c|
          status = c[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{status} #{c[:name]}"
        end

        all_ok = checks.all? { |c| c[:ok] }
        puts all_ok ? "health: ok" : "health: some checks failed"
      end

      private

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
          puts "entries: #{stats[:entries]} size: #{stats[:size_human]} dir: #{stats[:cache_dir]}"
        else
          puts "  Usage: cache [stats|clear]"
        end
      end

      # Multi-file refactoring
      def multi_refactor(args)
        return puts "  MultiRefactor not available" unless defined?(MultiRefactor)

        path = args&.split&.first || MASTER.root
        dry_run = !args&.include?("-a") && !args&.include?("--apply")
        mr = MultiRefactor.new(dry_run: dry_run)
        result = mr.run(path: path)
        result
      end

      def start_web_server(args)
        port = args.to_s.strip.match?(/\A\d+\z/) ? args.strip.to_i : nil
        server = Server.new(port: port)
        server.start
        token = Server::AUTH_TOKEN
        puts "  web: http://localhost:#{server.port}"
        puts "  token: #{token}"
      end
    end
  end
end
