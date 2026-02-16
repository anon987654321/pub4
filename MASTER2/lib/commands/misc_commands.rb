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
        model = LLM.select_available_model
        checks << { name: "Models available", ok: !model.nil? }

        # Check budget
        budget_ok = LLM.budget_remaining > 0
        checks << { name: "Budget remaining", ok: budget_ok }

        checks.each do |c|
          status = c[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{status} #{c[:name]}"
        end

        all_ok = checks.all? { |c| c[:ok] }
        puts all_ok ? "health: ok" : "health: some checks failed"
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

        puts "Cinematic Presets"
        result.value[:presets].each do |preset|
          source = preset[:source] == 'builtin' ? '[builtin]' : '[custom]'
          puts "  * #{preset[:name]} #{source} #{preset[:description]}"
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
          puts "pipeline: complete -> #{output}"
        else
          puts "  - Pipeline failed: #{result.error}"
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
          puts "  + Discovered #{discoveries.size} styles!"

          discoveries.each_with_index do |d, i|
            puts "  #{i + 1}. Score: #{d[:score].round(2)} | #{d[:pipeline].stages.size} stages"
          end
        else
          puts "  - Discovery failed: #{result.error}"
        end
      end

      def build_cinematic_pipeline
        puts "pipeline: interactive builder (coming soon)"
        puts "  pipeline = MASTER::Cinematic::Pipeline.new; pipeline.chain('stability-ai/sdxl', { prompt: 'cinematic' }); result = pipeline.execute(input)"
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
            puts "  * #{name}#{active_marker}"
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

      # Full self-run across entire pub4 repo
      def selftest_full(args)
        root = MASTER.root
        apply = args&.include?("-a") || args&.include?("--apply")
        lib_dir = File.join(root, "lib")

        rb_files = Dir.glob(File.join(lib_dir, "**", "*.rb")).sort
        puts "self: #{rb_files.count} files, mode: #{apply ? 'apply' : 'dry-run'}"

        # phase 1: syntax
        syntax_errors = rb_files.select { |f| !system("ruby", "-c", f, out: File::NULL, err: File::NULL) }
        puts "self: syntax #{syntax_errors.empty? ? 'ok' : "#{syntax_errors.count} errors"}"
        syntax_errors.each { |f| puts "  #{File.basename(f)}" }

        # phase 2: sprawl
        large = rb_files.select { |f| File.readlines(f).size > 300 rescue false }
        puts "self: #{large.count} files >300 lines" if large.any?
        large.each { |f| puts "  #{File.basename(f)} #{File.readlines(f).size}L" }

        # phase 3: enforcement pipeline (same as any code gets)
        total_violations = 0
        fixed = 0

        rb_files.each do |file|
          code = File.read(file)
          rel = file.sub("#{root}/", "")
          violations = []

          if defined?(MASTER::Enforcement)
            r = Enforcement.check(code, filename: rel) rescue nil
            violations.concat(r[:violations]) if r.is_a?(Hash) && r[:violations].is_a?(Array)
          end

          if defined?(MASTER::Smells)
            r = Smells.analyze(code, rel) rescue nil
            violations.concat(r[:findings] || r[:smells] || []) if r.is_a?(Hash)
            violations.concat(r) if r.is_a?(Array)
          end

          if defined?(MASTER::Violations)
            r = Violations.analyze(code, path: rel, llm: (LLM if defined?(LLM) && LLM.configured?)) rescue nil
            found = (r[:literal] || []) + (r[:conceptual] || []) if r.is_a?(Hash)
            violations.concat(found) if found&.any?
          end

          if defined?(MASTER::CodeQuality)
            r = CodeQuality.scan(rel, silent: true) rescue nil
            violations.concat(r[:findings]) if r.is_a?(Hash) && r[:findings].is_a?(Array)
          end

          next if violations.empty?

          total_violations += violations.count
          puts "  #{rel}: #{violations.count} violations"
          violations.each { |v| puts "    #{v[:axiom] || v[:type] || v[:pattern]}: #{v[:message]}" }

          next unless apply && defined?(LLM) && LLM.configured?

          prompt = "Fix these violations in #{rel}:\n" \
                   "#{violations.map { |v| "- #{v[:message]}" }.join("\n")}\n\n" \
                   "Return ONLY the corrected Ruby code, no explanation."
          result = LLM.ask(prompt, stream: false)
          if result&.ok? && result.value[:content].to_s.include?("def ")
            File.write(file, result.value[:content])
            if system("ruby", "-c", file, out: File::NULL, err: File::NULL)
              fixed += violations.count
              puts "    + fixed"
            else
              File.write(file, code)
              puts "    - rollback (syntax error)"
            end
          end
        end

        puts "self: #{total_violations} violations#{apply ? ", #{fixed} fixed" : ""}"

        # phase 4: git status
        if system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
          status = `git -C #{root} status --porcelain`.strip
          puts status.empty? ? "self: git clean" : "self: git #{status.lines.size} uncommitted"
        end

        # phase 5: reflect via LLM
        if defined?(LLM) && LLM.configured?
          facts = "#{rb_files.count} files, #{syntax_errors.count} syntax errors, " \
                  "#{large.count} >300L, #{total_violations} violations, #{fixed} fixed"
          prompt = "You just ran self-inspection on your own codebase. " \
                   "Facts: #{facts}. " \
                   "In 5 lines or fewer: what should be improved next? Be concrete and terse."
          r = LLM.ask(prompt, stream: true)
          puts r.value[:content] if r&.ok?
        end

        Result.ok("self complete: #{total_violations} violations, #{fixed} fixed")
      rescue StandardError => e
        Result.err("self failed: #{e.message}")
      end
    end
  end
end
