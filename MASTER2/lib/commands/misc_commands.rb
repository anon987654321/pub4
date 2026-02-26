# frozen_string_literal: true

require "yaml"
require "fileutils"
require "open3"
require "timeout"

require_relative "misc_commands/self_run"
require_relative "misc_commands/cinematic_persona"

module MASTER
  module Commands
    # Miscellaneous commands
    module MiscCommands
      TEXT_EXTENSIONS = %w[rb py js ts css svg zsh sh bash md yml yaml json toml gemspec txt erb conf ini env].freeze
      TEXT_BASENAMES  = %w[Gemfile Rakefile Makefile Dockerfile].freeze
      SKIP_DIRS       = Paths::SKIP_DIRS

      def run_snapshot(args)
        ts  = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        out = args&.strip&.then { |a| a.empty? ? nil : a } || Paths.var_file("snapshot-#{ts}.md")
        max = 400
        puts "  generating snapshot..."

        n_files = n_lines = n_trunc = 0
        buf = StringIO.new
        buf.puts "# Project Snapshot - #{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}"
        buf.puts
        buf.puts "## Tree"
        buf.puts "```"
        buf.puts ascii_tree(Dir.pwd)
        buf.puts "```"
        buf.puts

        Dir.glob("**/*", base: Dir.pwd).sort.each do |rel|
          next if File.directory?(File.join(Dir.pwd, rel))
          next if rel == out
          parts = rel.split("/")
          next if parts.any? { |p| SKIP_DIRS.include?(p) }
          ext  = File.extname(rel).delete_prefix(".")
          base = File.basename(rel)
          next unless TEXT_EXTENSIONS.include?(ext) || TEXT_BASENAMES.include?(base)

          lines = File.readlines(File.join(Dir.pwd, rel), encoding: "utf-8:utf-8", chomp: true)
          n = lines.size
          # Skip bulky data YAMLs — loaded at runtime, not useful in snapshots
          next if rel.start_with?("data/") && ext == "yml" && n > 300
          buf.puts "## `#{rel}`"
          buf.puts "```#{ext}"
          if n > max
            buf.puts lines.first(max).join("\n")
            buf.puts "... #{n - max} lines truncated (#{n} total)"
            n_trunc += 1
          else
            buf.puts lines.join("\n")
          end
          buf.puts "```"
          buf.puts
          n_files += 1
          n_lines  += n
        rescue Errno::ENOENT, Encoding::UndefinedConversionError
          next
        end

        est = n_lines * 6 / 5
        buf.puts "files: #{n_files} / lines: #{n_lines} / truncated: #{n_trunc} / est. tokens: ~#{est}"
        File.write(out, buf.string)
        puts "  saved: #{out}  (#{n_files} files, #{n_lines} lines, ~#{est} tokens)"
      end

      def speak(text)
        return puts "  Usage: speak <text>" unless text

        result = Speech.speak(text)
        puts "  TTS Error: #{result.error}" if result.err?
      end

      def fix_code(args)
        path = args&.strip
        path = "." if path.nil? || path.empty?

        fixer = MASTER::Review::Fixer.new(mode: :moderate)
        if File.directory?(path)
          result = fixer.fix_directory(path)
          if result.ok?
            puts "  Fixed #{result.value[:files_fixed]} files, #{result.value[:issues_fixed]} issues"
          else
            puts "  Error: #{result.error}"
          end
        else
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
            captures.last(10).each do |capture|
              puts UI.dim(capture[:timestamp])
              capture[:answers].each do |category, answer|
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

      def print_health(args = nil)
        tokens = args.to_s.split
        deep   = tokens.delete("--deep") || tokens.delete("--verbose")
        setup  = tokens.delete("--setup")

        if setup
          return bootstrap_setup
        end

        UI.header(deep ? "Health (deep)" : "Health Check")
        checks = startup_checks

        checks.each do |check|
          status = check[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{status} #{check[:name]}#{" (#{check[:detail]})" if check[:detail]}"
          puts UI.dim("    fix: #{check[:fix]}") if deep && !check[:ok] && check[:fix]
        end

        if deep
          plugin_check = plugin_manifest_check
          plugin_icon = plugin_check[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{plugin_icon} Plugins#{" (#{plugin_check[:detail]})" if plugin_check[:detail]}"
          puts UI.dim("    fix: #{plugin_check[:fix]}") if !plugin_check[:ok] && plugin_check[:fix]

          tidy = repo_cleanliness
          puts "#{UI.pastel.cyan('*')} Repo dirtiness #{tidy[:dirty_count]} files (#{tidy[:state]})"
        end

        all_ok = checks.all? { |c| c[:ok] }
        puts all_ok ? "health: ok" : "health: attention required"
        Result.ok(ok: all_ok, checks: checks)
      end

      # Legacy aliases — delegate to unified print_health
      def doctor(args = nil)  = print_health("#{args} --deep")
      def bootstrap(args = nil) = print_health("#{args} --setup")

      def history_dig(args = nil)
        target = args.to_s.strip
        target = "master.yml" if target.empty?
        return Result.err("history-dig target must be master.yml or master.json") unless %w[master.yml
                                                                                            master.json].include?(target)

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

        if ["json", "export-json"].include?(mode)
          out = File.join(Paths.var, "design.json")
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
        catalog_path = Paths.data_file("style_guides.yml")
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
      rescue StandardError => err
        Result.err("style-guides failed: #{err.message}")
      end

      def start_web_server(args)
        port = args.to_s.strip.match?(/\A\d+\z/) ? args.strip.to_i : nil
        server = Server.new(port: port)
        server.start
        token = Server::AUTH_TOKEN
        puts "  web: http://localhost:#{server.port}/?token=#{token}"
      end

      private

      def bootstrap_setup
        UI.header("Bootstrap")
        checks = startup_checks

        checks.each do |check|
          status = check[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{status} #{check[:name]}#{" (#{check[:detail]})" if check[:detail]}"
        end

        if defined?(PlatformCheck)
          issues = PlatformCheck.diagnose
          if issues.empty?
            summary = PlatformCheck.summary
            puts "#{UI.pastel.green('+')} platform: #{summary}" if summary
          else
            puts "#{UI.pastel.red('-')} platform: #{issues.size} issue(s) found"
            PlatformCheck.print_diagnostics
          end
        end

        missing_gems = begin
          AutoInstall.missing_gems
        rescue StandardError
          []
        end
        if missing_gems.any?
          puts UI.dim("Installing #{missing_gems.size} missing gems into local bundle path...")
          ok = system("bundle", "install")
          return Result.err("bundle install failed") unless ok
        end

        Result.ok(checks: checks, installed: missing_gems.size)
      end

      def ascii_tree(root, prefix = "", path = root, buf = [])
        entries = Dir.entries(path).reject { |e| e.start_with?(".") || SKIP_DIRS.include?(e) }.sort
        entries.each_with_index do |entry, idx|
          last    = idx == entries.size - 1
          pointer = last ? "`-- " : "|-- "
          buf << "#{prefix}#{pointer}#{entry}"
          child = File.join(path, entry)
          if File.directory?(child)
            extension = last ? "    " : "|   "
            ascii_tree(root, prefix + extension, child, buf)
          end
        end
        buf.join("\n")
      end

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
            ok: File.exist?(Paths.data_file("constitution.yml")),
            fix: "Ensure data/constitution.yml exists",
          },
          {
            name: "Bundler metadata",
            ok: bundle_ok,
            fix: "Run: bin/master bootstrap",
          },
          {
            name: "Writable var/",
            ok: File.writable?(Paths.var),
            fix: "Ensure #{Paths.var} is writable",
          },
          {
            name: "OpenRouter key",
            ok: ENV.fetch("OPENROUTER_API_KEY", "").strip != "",
            fix: "Set OPENROUTER_API_KEY for LLM features",
          },
        ]
      end

      def plugin_manifest_check
        unless defined?(Bridges)
          return { ok: false, detail: "bridges unavailable",
                   fix: "require bridges before doctor" }
        end

        missing = (Bridges.respond_to?(:validate_plugins) ? Bridges.validate_plugins : [])
        return { ok: true, detail: "all bridge plugins resolved" } if missing.empty?

        { ok: false, detail: "missing: #{missing.join(', ')}", fix: "reinstall dependencies or restore bridge files" }
      rescue StandardError => err
        { ok: false, detail: err.message, fix: "check bridge plugin wiring" }
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
                 end,
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
        mr.run(path: path)
      end

      # Project memory - persistent goal/context across sessions and models
      def project_goal(args)
        return show_project_context unless args&.strip&.length&.> 0

        ProjectMemory.save(root: Dir.pwd, goal: args.strip)
        puts UI.dim("goal: #{args.strip}")
      end

      def project_remember(args)
        return puts UI.dim("usage: remember <decision or fact>") unless args&.strip&.length&.> 0

        ProjectMemory.save(root: Dir.pwd, decisions: args.strip)
        puts UI.dim("remembered.")
      end

      def project_forget
        path = File.join(Dir.pwd, ".master", "context.yml")
        File.delete(path) if File.exist?(path)
        puts UI.dim("context cleared.")
      end

      def show_project_context
        ctx = defined?(ProjectMemory) ? ProjectMemory.load(root: Dir.pwd) : {}
        if ctx.empty?
          puts UI.dim("no project context - set one with: goal <text>")
        else
          puts UI.dim("goal: #{ctx['goal']}") if ctx["goal"]
          puts UI.dim("stack: #{ctx['stack']}") if ctx["stack"]
          puts UI.dim("constraints: #{ctx['constraints']}") if ctx["constraints"]
          Array(ctx["decisions"]).each { |decision| puts UI.dim("  * #{decision}") }
        end
      end

      def run_webtest(_args)
        require "net/http"
        require "json"

        server = defined?(MASTER::Server) ? ObjectSpace.each_object(MASTER::Server).first : nil
        unless server&.running?
          puts UI.warn("webtest: web server not running")
          return
        end

        base = "http://localhost:#{server.port}"
        token = MASTER::Server::AUTH_TOKEN
        results = []

        # 1. GET /health -- no auth required
        results << web_probe("GET", "#{base}/health") do |body|
          data = JSON.parse(body)
          data["status"] == "ok" ? "ok" : "bad status: #{data['status']}"
        end

        # 2. GET / -- verify chat UI with orb + canvas + TTS
        results << web_probe("GET", base) do |body|
          missing = %w[canvas orb-name NEURAL\ CORE].reject { |el| body.include?(el) }
          missing.empty? ? "ok" : "missing: #{missing.join(', ')}"
        end

        # 3. POST /chat -- returns {"status":"processing"} async; poll /poll for result
        results << web_probe("POST", "#{base}/chat",
                             body: { message: "ping", session_id: "webtest" }.to_json,
                             token: token,
                             content_type: "application/json") do |body|
          data = JSON.parse(body)
          data["status"] == "processing" ? "ok" : "unexpected: #{body[0, 40]}"
        rescue JSON::ParserError
          "non-json response"
        end

        # 4. GET /poll -- should return queued output from chat
        sleep 2 # give pipeline time to respond
        results << web_probe("GET", "#{base}/poll", token: token) do |body|
          JSON.parse(body).key?("text") ? "ok" : "missing text key"
        rescue JSON::ParserError
          "non-json"
        end

        pass = results.count { |r| r[:status] == :ok }
        fail_count = results.size - pass
        results.each { |r| puts "  #{r[:status] == :ok ? UI.pastel.green('ok') : UI.pastel.red('!!')} #{r[:label]}" }
        puts fail_count.zero? ? UI.success("webtest: #{pass}/#{results.size} passed") : UI.warn("webtest: #{fail_count} failed")
      end

      private

      def web_probe(method, url, body: nil, token: nil, content_type: nil, &check)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 10

        req = (method == "POST" ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
        req["Authorization"] = "Bearer #{token}" if token
        req["Content-Type"] = content_type if content_type
        req.body = body if body

        resp = http.request(req)
        label = "#{method} #{uri.path.empty? ? '/' : uri.path} -> #{resp.code}"
        if resp.code.start_with?("2")
          result = check ? check.call(resp.body) : "ok"
          { status: result == "ok" ? :ok : :fail, label: "#{label} (#{result})" }
        else
          { status: :fail, label: "#{label}" }
        end
      rescue StandardError => err
        { status: :fail, label: "#{method} #{url} -> #{err.message}" }
      end
    end
  end
end
