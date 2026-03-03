# frozen_string_literal: true

require "yaml"
require "fileutils"
require "open3"
require "timeout"

require_relative "misc_commands/self_run"
require_relative "misc_commands/cinematic_persona"

module MASTER
  module Commands
    # Miscellaneous commands — flat, direct, no indirection layers.
    module MiscCommands
      TEXT_EXTENSIONS = %w[rb py js ts css svg zsh sh bash md yml yaml json toml gemspec txt erb conf ini env].freeze
      TEXT_BASENAMES  = %w[Gemfile Rakefile Makefile Dockerfile].freeze
      SKIP_DIRS       = Paths::SKIP_DIRS

      # fix [path] — unified scan+fix+commit pipeline; defaults to project root
      def fix_code(args)
        path = args&.strip
        path = nil if path.nil? || path.empty? || path.start_with?("--")
        self_run(path || MASTER.root)
      end

      def git_commit_fixes(root, fixed, cmd)
        return unless system("git", "-C", root, "rev-parse", "--git-dir",
                              out: File::NULL, err: File::NULL)

        porcelain, = Open3.capture2("git", "-C", root, "status", "--porcelain")
        return if porcelain.strip.empty?

        system("git", "-C", root, "add", "-A")
        msg = "#{cmd}: #{fixed} fixes [#{Time.now.utc.iso8601}]"
        system("git", "-C", root, "commit", "-m", msg) ? puts("#{cmd}: committed") : puts("#{cmd}: git commit failed")
      end

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

      def browse_url(args)
        return puts "  Usage: browse <url>" unless args

        url = args.strip
        if defined?(Web)
          result = Web.browse(url)
          result.ok? ? puts("\n  Content (first 1000 chars):\n#{result.value[:content][0..1000]}\n") : puts("  Error: #{result.error}")
        else
          puts "  Web module not available"
        end
      end

      def ideate(args)
        topic = args&.strip
        return Result.err("Usage: ideate <topic>.") unless topic && !topic.empty?

        UI.header("Ideating on: #{topic}")
        prompt = "Brainstorm 5 creative ideas for: #{topic}\n\nFormat:\n1. Idea name -- brief description\n..."
        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?

        puts result.value[:content]
        puts
        Result.ok(result.value[:content])
      end

      def session_capture
        defined?(SessionCapture) ? SessionCapture.capture : puts("  SessionCapture not available")
      end

      def review_captures
        return puts "  SessionCapture not available" unless defined?(SessionCapture)

        result = SessionCapture.review
        return puts "  #{result.error}" unless result.ok?

        captures = result.value[:captures]
        puts "#{captures.size} session captures:"
        captures.last(10).each do |capture|
          puts UI.dim(capture[:timestamp])
          capture[:answers].each { |cat, ans| puts "  #{UI.bold(cat)}: #{ans}" }
        end
      end

      def print_health(args = nil)
        tokens = args.to_s.split
        deep  = tokens.delete("--deep") || tokens.delete("--verbose")
        return run_bootstrap if tokens.delete("--setup")

        UI.header(deep ? "Health (deep)" : "Health Check")
        checks = health_checks

        checks.each do |check|
          icon = check[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{icon} #{check[:name]}#{" (#{check[:detail]})" if check[:detail]}"
          puts UI.dim("    fix: #{check[:fix]}") if deep && !check[:ok] && check[:fix]
        end

        if deep
          pc = plugin_manifest_check
          puts "#{pc[:ok] ? UI.pastel.green('+') : UI.pastel.red('-')} Plugins#{" (#{pc[:detail]})" if pc[:detail]}"
          tidy = repo_cleanliness
          puts "#{UI.pastel.cyan('*')} Repo dirtiness #{tidy[:dirty_count]} files (#{tidy[:state]})"
        end

        all_ok = checks.all? { |c| c[:ok] }
        puts all_ok ? "health: ok" : "health: attention required"
        Result.ok(ok: all_ok, checks: checks)
      end

      def doctor(args = nil)    = print_health(args)
      def bootstrap(args = nil) = print_health(args)

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
          Array(list).each { |e| puts "    - #{e[:name]}: #{e[:repo]}" }
        end
        puts "\nAwesome Lists:"
        Array(catalog[:awesome_lists]).each { |e| puts "  - #{e[:name]}: #{e[:repo]}" }
        Result.ok(total: entries.size)
      rescue StandardError => err
        Result.err("style-guides failed: #{err.message}")
      end

      def start_web_server(args)
        port = args.to_s.strip.match?(/\A\d+\z/) ? args.strip.to_i : nil
        server = Server.new(port: port)
        server.start
        puts "  web: http://localhost:#{server.port}/?token=#{Server::AUTH_TOKEN}"
      end

      def creative_chamber(args)
        prompt = args.to_s.strip
        return Result.err("Usage: creative <prompt>") if prompt.empty?

        if defined?(Chamber)
          result = Chamber.deliberate(prompt)
          puts result.respond_to?(:ok?) && result.ok? ? (result.value[:summary] || result.value[:response]) : result.respond_to?(:error) ? result.error : result.to_s
        else
          result = LLM.ask("Creative exploration: #{prompt}", tier: :strong)
          puts result.ok? ? result.value[:content] : "Error: #{result.error}"
        end
        Result.ok
      end

      def harvest_data(args)
        target = args.to_s.strip
        return Result.err("Usage: harvest <url|topic>") if target.empty?

        if target.match?(%r{\Ahttps?://}) && defined?(Web)
          result = Web.browse(target)
          result.ok? ? puts(result.value[:content].to_s[0, 2000]) : puts("Error: #{result.error}")
        else
          result = LLM.ask("Research and summarize: #{target}", tier: :fast)
          puts result.ok? ? result.value[:content] : "Error: #{result.error}"
        end
        Result.ok
      end

      def manage_queue(args)
        cmd = args.to_s.strip.split.first
        case cmd
        when "list", nil, ""
          if defined?(Scheduler)
            jobs = Scheduler.list_jobs
            jobs.empty? ? puts("queue: empty") : jobs.each { |j| puts "  #{j[:id]} #{j[:status]} #{j[:description]}" }
          else
            puts "Scheduler not available"
          end
        when "clear"
          Scheduler.clear! if defined?(Scheduler)
          puts "queue: cleared"
        else
          puts "Usage: queue [list|clear]"
        end
        Result.ok
      end

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

      def multi_refactor(args)
        return puts "  MultiRefactor not available" unless defined?(MultiRefactor)

        path    = args&.split&.first || MASTER.root
        dry_run = args&.include?("--dry-run")
        MultiRefactor.new(dry_run: dry_run).run(path: path)
      end

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
          Array(ctx["decisions"]).each { |d| puts UI.dim("  * #{d}") }
        end
      end

      CONTEXT_DEPTHS = %w[shallow own deep full].freeze

      def manage_context(args)
        parts = args.to_s.strip.split(" ", 2)
        sub   = parts[0].to_s.downcase
        val   = parts[1].to_s.strip

        case sub
        when "", "show"
          depth   = ExecutionContext.current_depth
          hist    = Session.current.metadata_value(:context_history_max) || 12
          pinned  = Session.current.metadata_value(:context_pin)
          approx  = ExecutionContext.build_system_message(depth: depth).length / 4

          puts UI.dim("depth:   #{depth}  (shallow|own|deep|full)")
          puts UI.dim("history: #{hist} messages")
          puts UI.dim("tokens:  ~#{approx} in system message")
          puts UI.dim("pin:     #{pinned || 'none'}")
          puts
          puts UI.dim("  context depth shallow     -- code-free, conversational")
          puts UI.dim("  context depth full        -- inject full source files")
          puts UI.dim("  context history 6         -- limit to 6 prior exchanges")
          puts UI.dim("  context pin <note>        -- append note to every prompt")
          puts UI.dim("  context unpin             -- remove pinned note")

        when "depth"
          unless CONTEXT_DEPTHS.include?(val)
            puts UI.dim("depth must be: #{CONTEXT_DEPTHS.join(' | ')}")
            return
          end
          ExecutionContext.current_depth = val.to_sym
          puts UI.dim("context depth: #{val}")

        when "history"
          n = val.to_i
          if n < 1 || n > 100
            puts UI.dim("history must be 1..100")
            return
          end
          Session.current.set_metadata(:context_history_max, n)
          puts UI.dim("context history: #{n} messages")

        when "pin"
          return puts UI.dim("usage: context pin <note>") if val.empty?

          Session.current.set_metadata(:context_pin, val)
          puts UI.dim("pinned: #{val}")

        when "unpin"
          Session.current.set_metadata(:context_pin, nil)
          puts UI.dim("pin cleared")

        else
          puts UI.dim("context [show|depth|history|pin|unpin]")
        end
      end

      def run_webtest(_args)
        require "net/http"

        server = defined?(MASTER::Server) ? ObjectSpace.each_object(MASTER::Server).first : nil
        unless server&.running?
          puts UI.warn("webtest: web server not running")
          return
        end

        base  = "http://localhost:#{server.port}"
        token = MASTER::Server::AUTH_TOKEN
        results = []

        results << web_probe("GET", "#{base}/health") { |b| JSON.parse(b)["status"] == "ok" ? "ok" : "bad status" }
        results << web_probe("GET", base) { |b| %w[canvas orb-name].all? { |el| b.include?(el) } ? "ok" : "missing elements" }
        results << web_probe("POST", "#{base}/chat",
                             body: { message: "ping", session_id: "webtest" }.to_json,
                             token: token, content_type: "application/json") { |b| JSON.parse(b)["status"] == "processing" ? "ok" : "unexpected" rescue "non-json" }
        sleep 2
        results << web_probe("GET", "#{base}/poll", token: token) { |b| JSON.parse(b).key?("text") ? "ok" : "missing text key" rescue "non-json" }

        pass = results.count { |r| r[:status] == :ok }
        results.each { |r| puts "  #{r[:status] == :ok ? UI.pastel.green('ok') : UI.pastel.red('!!')} #{r[:label]}" }
        puts pass == results.size ? UI.success("webtest: #{pass}/#{results.size} passed") : UI.warn("webtest: #{results.size - pass} failed")
      end

      private

      def ascii_tree(root, prefix = "", path = root, buf = [])
        entries = Dir.entries(path).reject { |e| e.start_with?(".") || SKIP_DIRS.include?(e) }.sort
        entries.each_with_index do |entry, idx|
          last    = idx == entries.size - 1
          pointer = last ? "`-- " : "|-- "
          buf << "#{prefix}#{pointer}#{entry}"
          child = File.join(path, entry)
          ascii_tree(root, prefix + (last ? "    " : "|   "), child, buf) if File.directory?(child)
        end
        buf.join("\n")
      end

      def health_checks
        bundle_ok = File.exist?(File.join(MASTER.root, "Gemfile")) &&
                    (!File.exist?(File.join(MASTER.root, "Gemfile.lock")) ||
                     File.read(File.join(MASTER.root, "Gemfile.lock")).include?("BUNDLED WITH"))
        [
          { name: "Constitution parses", ok: File.exist?(Paths.data_file("constitution.yml")), fix: "Ensure data/constitution.yml exists" },
          { name: "Bundler metadata",    ok: bundle_ok,                                         fix: "Run: bin/master bootstrap" },
          { name: "Writable var/",       ok: File.writable?(Paths.var),                         fix: "Ensure #{Paths.var} is writable" },
          { name: "OpenRouter key",      ok: ENV.fetch("OPENROUTER_API_KEY", "").strip != "",    fix: "Set OPENROUTER_API_KEY for LLM features" },
        ]
      rescue StandardError
        []
      end

      def run_bootstrap
        UI.header("Bootstrap")
        checks = health_checks
        checks.each do |check|
          icon = check[:ok] ? UI.pastel.green("+") : UI.pastel.red("-")
          puts "#{icon} #{check[:name]}#{" (#{check[:detail]})" if check[:detail]}"
        end

        if defined?(PlatformCheck)
          issues = PlatformCheck.diagnose
          if issues.empty?
            puts "#{UI.pastel.green('+')} platform: #{PlatformCheck.summary}"
          else
            puts "#{UI.pastel.red('-')} platform: #{issues.size} issue(s)"
            PlatformCheck.print_diagnostics
          end
        end

        missing_gems = AutoInstall.missing_gems rescue []
        if missing_gems.any?
          puts UI.dim("Installing #{missing_gems.size} missing gems...")
          return Result.err("bundle install failed") unless system("bundle", "install")
        end

        Result.ok(checks: checks, installed: missing_gems.size)
      end

      def plugin_manifest_check
        unless defined?(Bridges)
          return { ok: false, detail: "bridges unavailable", fix: "require bridges before doctor" }
        end

        missing = Bridges.respond_to?(:validate_plugins) ? Bridges.validate_plugins : []
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
        { dirty_count: count, state: count == 0 ? "clean" : count <= 8 ? "tidy" : "messy" }
      rescue StandardError
        { dirty_count: 0, state: "unknown" }
      end

      def web_probe(method, url, body: nil, token: nil, content_type: nil, &check)
        uri  = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 10

        req = (method == "POST" ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
        req["Authorization"] = "Bearer #{token}" if token
        req["Content-Type"]  = content_type if content_type
        req.body = body if body

        resp  = http.request(req)
        label = "#{method} #{uri.path.empty? ? '/' : uri.path} -> #{resp.code}"
        if resp.code.start_with?("2")
          result = check ? check.call(resp.body) : "ok"
          { status: result == "ok" ? :ok : :fail, label: "#{label} (#{result})" }
        else
          { status: :fail, label: label }
        end
      rescue StandardError => err
        { status: :fail, label: "#{method} #{url} -> #{err.message}" }
      end
    end
  end
end
