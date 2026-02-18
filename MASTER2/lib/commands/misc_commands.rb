# frozen_string_literal: true

require "yaml"
require "fileutils"
require "open3"
require "timeout"

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

        # Check style guide catalog
        guides_ok = File.exist?(File.join(MASTER.root, "data", "style_guides.yml"))
        checks << { name: "Style guides catalog", ok: guides_ok }

        checks.each do |c|
          status = c[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{status} #{c[:name]}"
        end

        all_ok = checks.all? { |c| c[:ok] }
        puts all_ok ? "health: ok" : "health: some checks failed"
      end

      def bootstrap(_args = nil)
        UI.header("Bootstrap")
        checks = startup_checks

        checks.each do |c|
          status = c[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{status} #{c[:name]}#{c[:detail] ? " (#{c[:detail]})" : ""}"
        end

        missing_gems = AutoInstall.missing_gems rescue []
        if missing_gems.any?
          puts UI.dim("Installing #{missing_gems.size} missing gems into local bundle path...")
          ok = system("bundle", "install")
          return Result.err("bundle install failed") unless ok
        end

        Result.ok(checks: checks, installed: missing_gems.size)
      end

      def doctor(args = nil)
        verbose = args.to_s.include?("--verbose")
        UI.header("Doctor")

        checks = startup_checks
        checks.each do |c|
          status = c[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{status} #{c[:name]}#{c[:detail] ? " (#{c[:detail]})" : ""}"
          puts UI.dim("    fix: #{c[:fix]}") if verbose && !c[:ok] && c[:fix]
        end

        plugin_check = plugin_manifest_check
        plugin_icon = plugin_check[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
        puts "#{plugin_icon} Plugins#{plugin_check[:detail] ? " (#{plugin_check[:detail]})" : ""}"
        puts UI.dim("    fix: #{plugin_check[:fix]}") if verbose && !plugin_check[:ok] && plugin_check[:fix]

        tidy = repo_cleanliness
        puts "#{UI.pastel.cyan("*")} Repo dirtiness #{tidy[:dirty_count]} files (#{tidy[:state]})"

        all_ok = (checks + [plugin_check]).all? { |c| c[:ok] }
        puts all_ok ? "doctor: ok" : "doctor: attention required"
        Result.ok(ok: all_ok, checks: checks, plugins: plugin_check, cleanliness: tidy)
      end

      def history_dig(args = nil)
        target = args.to_s.strip
        target = "master.yml" if target.empty?
        return Result.err("history-dig target must be master.yml or master.json") unless %w[master.yml master.json].include?(target)

        commits_out, status = Open3.capture2("git", "rev-list", "--all", "--", target)
        return Result.err("git history unavailable for #{target}") unless status.success?

        commit = commits_out.lines.map(&:strip).find do |sha|
          _out, ok = Open3.capture2("git", "cat-file", "-e", "#{sha}:#{target}")
          ok.success?
        end
        return Result.err("No historical blob found for #{target}") if commit.nil?

        content, show_status = Open3.capture2("git", "show", "#{commit}:#{target}")
        return Result.err("Failed to extract #{target} from #{commit}") unless show_status.success?

        dest = File.join(Paths.var, "#{target}.history.snapshot")
        File.write(dest, content)
        puts "history-dig: #{target} -> #{dest}"
        puts "history-dig: source commit #{commit}"
        Result.ok(target: target, commit: commit, snapshot: dest)
      end

      def codify(args = nil)
        return Result.err("Design codex unavailable") unless defined?(Review::DesignCodex)

        summary = Review::DesignCodex.summary
        mode = args.to_s.strip

        if mode == "json" || mode == "export-json"
          out = File.join(Paths.var, "design_codex.json")
          File.write(out, Review::DesignCodex.to_json)
          puts "codify: exported #{out}"
          return Result.ok(path: out, summary: summary)
        end

        UI.header("Codified Rules")
        puts "version: #{summary[:version]}"
        puts "typography sections: #{summary[:typography_rules]}"
        puts "layout sections: #{summary[:layout_rules]}"
        puts "hierarchy sections: #{summary[:hierarchy_rules]}"
        puts "code sections: #{summary[:code_rules]}"
        puts "run: codify export-json  (to emit machine JSON)"
        Result.ok(summary)
      end

      def style_guides(args = nil)
        catalog_path = File.join(MASTER.root, "data", "style_guides.yml")
        return Result.err("style guide catalog missing: #{catalog_path}") unless File.exist?(catalog_path)

        catalog = YAML.safe_load_file(catalog_path, symbolize_names: true) || {}
        entries = Array(catalog[:guides]).flat_map { |_, list| Array(list) } + Array(catalog[:awesome_lists])

        if args.to_s.include?("sync")
          dest = File.join(Paths.var, "style_guides")
          FileUtils.mkdir_p(dest)
          synced = 0

          entries.each do |entry|
            repo = entry[:repo].to_s
            next unless repo.start_with?("https://github.com/")

            name = repo.split("/").last
            path = File.join(dest, name)
            if Dir.exist?(path)
              system("git", "-C", path, "pull", "--ff-only", out: File::NULL, err: File::NULL)
            else
              system("git", "clone", "--depth", "1", repo, path, out: File::NULL, err: File::NULL)
            end
            synced += 1
          end

          puts "style-guides: synced #{synced} repos -> #{dest}"
          return Result.ok(synced: synced, dest: dest)
        end

        puts "Style Guides:"
        (catalog[:guides] || {}).each do |lang, list|
          puts "  #{lang}:"
          Array(list).each { |entry| puts "    - #{entry[:name]}: #{entry[:repo]}" }
        end

        puts "\nAwesome Lists:"
        Array(catalog[:awesome_lists]).each do |entry|
          puts "  - #{entry[:name]}: #{entry[:repo]}"
        end

        Result.ok(total: entries.size)
      rescue StandardError => e
        Result.err("style-guides failed: #{e.message}")
      end

      private

      def startup_checks
        bundle_ok = begin
          gemfile_lock = File.join(MASTER.root, "Gemfile.lock")
          gemfile = File.join(MASTER.root, "Gemfile")
          File.exist?(gemfile) && (!File.exist?(gemfile_lock) || File.read(gemfile_lock).include?("BUNDLED WITH"))
        rescue StandardError
          false
        end

        [
          {
            name: "Constitution parses",
            ok: File.exist?(File.join(MASTER.root, "data", "constitution.yml")),
            fix: "Ensure data/constitution.yml exists"
          },
          {
            name: "Bundler metadata",
            ok: bundle_ok,
            fix: "Run: bin/master bootstrap"
          },
          {
            name: "Writable var/",
            ok: File.writable?(Paths.var),
            fix: "Ensure #{Paths.var} is writable"
          },
          {
            name: "OpenRouter key",
            ok: ENV.fetch("OPENROUTER_API_KEY", "").strip != "",
            fix: "Set OPENROUTER_API_KEY for LLM features"
          }
        ]
      end

      def plugin_manifest_check
        return { ok: false, detail: "bridges unavailable", fix: "require bridges before doctor" } unless defined?(Bridges)

        missing = (Bridges.respond_to?(:validate_plugins) ? Bridges.validate_plugins : [])
        return { ok: true, detail: "all bridge plugins resolved" } if missing.empty?

        { ok: false, detail: "missing: #{missing.join(", ")}", fix: "reinstall dependencies or restore bridge files" }
      rescue StandardError => e
        { ok: false, detail: e.message, fix: "check bridge plugin wiring" }
      end

      def repo_cleanliness
        root = MASTER.root
        out, status = Open3.capture2("git", "-C", root, "status", "--porcelain")
        return { dirty_count: 0, state: "unknown" } unless status.success?

        count = out.lines.size
        {
          dirty_count: count,
          state: if count == 0
            "clean"
          elsif count <= 8
            "tidy"
          else
            "messy"
          end
        }
      rescue StandardError
        { dirty_count: 0, state: "unknown" }
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
