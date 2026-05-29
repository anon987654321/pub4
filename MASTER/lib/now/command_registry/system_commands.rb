# frozen_string_literal: true

require "open3"

module Master
  module Now
  module CommandRegistry
    module_function

    TEXT_EXTS = %w[.rb .py .js .ts .zsh .sh .bash .md .yml .yaml .json .toml .gemspec .txt .erb .conf .ini .env].to_set.freeze
    TEXT_NAMES = %w[Gemfile Rakefile Makefile Dockerfile].to_set.freeze
    SKIP_SEGS = %w[.git vendor tmp var node_modules .bundle coverage log dist knowledge].to_set.freeze

    def system_commands(agent, diag, root)
      {
        "orient" => cmd(:dispatch_orient, root),
        "explain" => ->(_ctx) { dispatch_orient(root, "") },
        "tree" => cmd(:dispatch_tree, root),
        "diff" => cmd(:dispatch_diff, root),
        "commit" => ->(_ctx) { dispatch_commit(agent, root) },
        "snapshot" => ->(_ctx) { dispatch_snapshot(root) },
        "diag" => ->(ctx) { diag ? diag.render(ctx[:args].to_s.strip) : "diag: not configured" },
        "reload" => ->(_ctx) { "reload: not supported in this context" }
      }
    end

    ORIENT_FILES = {
      "soul" => ["data/soul.yml", "constitution: axioms, voice, persona, prompt order"],
      "rules" => ["data/rules.yml", "universal cross-disciplinary rules"],
      "style" => ["data/ruby_style.yml", "ruby/shell/git/css/html/typography idioms"],
      "workflow" => ["data/workflow.yml", "agent loops, pipeline, council, gates"],
      "orders" => ["data/standing_orders.yml", "event triggers and standing operating procedures"],
      "patterns" => ["data/patterns.yml", "gh/openbsd/zsh tool idioms"],
      "openbsd" => ["data/openbsd.yml", "pf/nsd/httpd/relayd config validators"]
    }.freeze

    def dispatch_orient(root, arg)
      return cat_orient(root, arg) unless arg.empty?
      [
        "MASTER — constitutional AI runtime for any text artifact",
        "modules: now · loop · judge · voice · ground · reach · trace",
        "pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render",
        "",
        "constitution:",
        *ORIENT_FILES.map { |k, (path, desc)| "  /orient #{k.ljust(10)} #{path.ljust(28)} #{desc}" }
      ].join("\n")
    end

    def cat_orient(root, arg)
      entry = ORIENT_FILES[arg]
      return "unknown: #{arg} (try: #{ORIENT_FILES.keys.join(", ")})" unless entry
      full = File.join(root, entry[0])
      File.exist?(full) ? File.read(full) : "missing: #{full}"
    end

    def dispatch_tree(root, arg)
      cfg   = (Master.load_yaml(File.join(root, "data", "rules.yml")) || {}).dig("paths", "tree") || {}
      depth = arg.to_i.positive? ? arg.to_i : (cfg["max_depth"] || 2)
      cap   = cfg["max_lines"] || 200
      tree_lines = []
      walker = lambda do |dir, level|
        return if level > depth || tree_lines.size >= cap
        Dir.children(dir).sort.each do |name|
          break if tree_lines.size >= cap
          next if name.start_with?(".") || SKIP_SEGS.include?(name)
          path = File.join(dir, name)
          tree_lines << "#{"  " * (level - 1)}#{name}#{File.directory?(path) ? "/" : ""}"
          walker.call(path, level + 1) if File.directory?(path)
        end
      rescue Errno::EACCES, Errno::ENOENT
        nil
      end
      walker.call(root, 1)
      tree_lines.join("\n")
    end

    def dispatch_diff(root, arg)
      base = arg.empty? ? "HEAD" : arg
      out, = Open3.capture2e("git", "-C", root, "diff", base, "--stat")
      out.strip.empty? ? "(no changes since #{base})" : out.strip
    end

    def dispatch_commit(agent, root)
      diff, = Open3.capture2e("git", "-C", root, "diff", "--cached", "--stat")
      diff, = Open3.capture2e("git", "-C", root, "diff", "--stat") if diff.strip.empty?
      return "nothing to commit" if diff.strip.empty?
      prompt = "Write a concise git commit message (1 line, imperative mood) for:\n#{diff}"
      commit_message = agent.ask_once(prompt).to_s.strip.lines.first.to_s.strip
      Open3.capture2e("git", "-C", root, "add", "-u")
      out, = Open3.capture2e("git", "-C", root, "commit", "-m", commit_message)
      out.strip
    end

    def dispatch_snapshot(root)
      purge_snapshot_gists
      [
        publish_snapshot(root, "MASTER"),
        publish_snapshot(File.expand_path("../DEPLOY", root), "DEPLOY")
      ].join("\n")
    end

    def purge_snapshot_gists
      list, status = Open3.capture2e("gh", "gist", "list", "--limit", "100", "--public")
      return unless status.success?
      list.lines.each do |line|
        id = line.split.first
        next unless line.include?("snapshot")
        Open3.capture2e("gh", "gist", "delete", "--yes", id) if id
      end
    rescue StandardError
      nil
    end

    def publish_snapshot(target, label)
      return "snapshot:#{label.downcase}: not found: #{target}" unless File.directory?(target)
      skip      = ->(rel) { rel.split("/").any? { |s| SKIP_SEGS.include?(s) } }
      text_file = ->(f) { TEXT_EXTS.include?(File.extname(f).downcase) || TEXT_NAMES.include?(File.basename(f)) }
      all   = Dir.glob(File.join(target, "**", "*"))
                 .reject { |f| File.basename(f).start_with?(".") }
                 .reject { |f| skip.(f.delete_prefix("#{target}/")) }.sort
      dirs  = all.select { |f| File.directory?(f) }
      files = all.select { |f| File.file?(f) && text_file.(f) && File.size(f) < Master::CTX_WINDOW_SIZE }
      stamp = Time.now.utc.iso8601
      md    = ["# #{label} Snapshot — #{stamp}", "", "## Tree", "```"]
      entries = (dirs.map { |d| [d, :dir] } + files.map { |f| [f, :file] })
                  .sort_by { |p, _| p.split("/") }
                  .map { |p, k| "#{"  " * p.delete_prefix("#{target}/").count("/")}#{File.basename(p)}#{k == :dir ? "/" : ""}" }
      md.concat(entries) << "```" << ""
      n_lines = 0
      files.each do |f|
        rel  = f.delete_prefix("#{target}/")
        lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        body = File.read(f, encoding: "UTF-8", invalid: :replace).lines
        n_lines += body.size
        md << "## `#{rel}`" << "```#{lang}"
        md.concat(body.map(&:rstrip))
        md << "```" << ""
      rescue StandardError => e
        md << "## `#{rel}`" << "[skipped: #{e.message}]" << ""
      end
      md << "files: #{files.size} / lines: #{n_lines}"
      day = Time.now.strftime("%Y-%m-%d")
      out, status = Open3.capture2e("gh", "gist", "create", "-",
        "--public", "--desc", "#{label} snapshot #{day}",
        "--filename", "#{label}.md",
        stdin_data: md.join("\n"))
      status.success? ? "snapshot:#{label.downcase}: #{files.size} files #{n_lines} lines → #{out.strip}" :
                        "snapshot:#{label.downcase}: gist failed: #{out.strip}"
    end
  end
  end
end
