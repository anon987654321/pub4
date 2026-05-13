# frozen_string_literal: true

module Master
  module CommandRegistry
    BINARY_SNIFF_BYTES = 512

    module_function

    def control_commands(standing, soul)
      {
        "orders" => cmd(:dispatch_orders, standing),
        "soul"   => cmd(:dispatch_soul, soul)
      }
    end

    def service_commands(ai, phase_gates = nil, diag: nil)
      heartbeat = ai[:heartbeat]
      skills    = ai[:skills]
      scanner   = ai[:scanner]
      {
        "heartbeat" => cmd(:dispatch_heartbeat, heartbeat),
        "skills"    => cmd(:dispatch_skills, skills),
        "phase"     => cmd(:dispatch_phase, phase_gates),
        "score"     => cmd(:score_file, scanner),
        "diag"      => ->(ctx) { diag ? diag.render(arg_for(ctx)) : "diag: not configured" }
      }
    end

    def dispatch_skills(skills, arg)
      return skills&.list || "(no skills)" if arg.empty?
      found = skills&.find(arg)
      found ? "#{found[:name]}: #{found[:description]}" : "(not found: #{arg})"
    end

    def dispatch_phase(gates, arg)
      return "no phase_gates configured" unless gates
      case arg
      when "", "status"      then gates.status
      when "advance"         then advance_phase(gates)
      when /\Aforce (.+)\z/  then gates.force!($1.strip).value!
      when /\Ameet (.+)\z/   then gates.meet_gate!($1.strip); "gate met: #{$1.strip}"
      else "phase: #{gates.current}  /phase [status|advance|force <name>|meet <gate>]"
      end
    end

    def advance_phase(gates)
      result = gates.advance!
      result.ok? ? result.value! : result.message
    end

    def dispatch_orders(standing, arg)
      case arg
      when "list", ""                    then standing.list
      when /\Aenable (.+)\z/             then standing.enable($1.strip)
      when /\Adisable (.+)\z/            then standing.disable($1.strip)
      when /\Aadd name=(\S+) cmd=(.+)\z/ then standing.upsert(name: $1, command: $2.strip)
      when "run"                         then run_due_orders(standing)
      when /\Areset (.+)\z/              then standing.reset($1.strip)
      else "usage: /orders  /orders enable|disable|reset <name>  /orders run"
      end
    end

    def run_due_orders(standing)
      results = standing.run_due!
      return "no orders due" if results.empty?
      results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
    end

    def dispatch_soul(soul, arg)
      case arg
      when "", "show"             then soul.summary
      when "version", "changelog" then soul.changelog
      when "diff"                 then soul.diff
      when "approve"              then soul.approve
      when "reject"               then soul.reject
      when "rollback"             then soul.rollback
      when /\Apropose (.+)\z/     then soul.propose($1.strip)
      else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
      end
    end

    TEXT_EXTS = %w[
      .rb .py .js .ts .zsh .sh .bash .md .yml .yaml .json
      .toml .gemspec .txt .erb .conf .ini .env
    ].to_set.freeze
    TEXT_NAMES = %w[Gemfile Rakefile Makefile Dockerfile].to_set.freeze
    DEFAULT_SKIP = %w[.git vendor tmp var node_modules .bundle coverage log dist knowledge].freeze

    def paths_config
      @paths_config ||= (Master.load_yaml(File.join(Master::ROOT, "data", "rules.yml")) || {})["paths"] || {}
    end

    def skip_segs
      @skip_segs ||= (paths_config["skip_dirs"] || DEFAULT_SKIP).to_set
    end

    SKIP_SEGS = DEFAULT_SKIP.to_set.freeze

    def tree_lines(root, max_depth: nil, max_lines: nil)
      cfg = paths_config["tree"] || {}
      depth = max_depth || cfg["max_depth"] || 2
      cap   = max_lines || cfg["max_lines"] || 200
      skip  = skip_segs
      buf   = []
      walker = lambda do |dir, level|
        return if level > depth || buf.size >= cap
        Dir.children(dir).sort.each do |name|
          break if buf.size >= cap
          next if name.start_with?(".") || skip.include?(name)
          path   = File.join(dir, name)
          indent = "  " * (level - 1)
          if File.directory?(path)
            buf << "#{indent}#{name}/"
            walker.call(path, level + 1)
          else
            buf << "#{indent}#{name}"
          end
        end
      rescue Errno::EACCES, Errno::ENOENT
        nil
      end
      walker.call(root, 1)
      buf
    end

    def dispatch_tree(root, arg)
      depth = arg.to_i.positive? ? arg.to_i : nil
      tree_lines(root, max_depth: depth).join("\n")
    end

    def dispatch_snapshot(root)
      [
        publish_snapshot(root, "MASTER"),
        publish_snapshot(File.expand_path("../DEPLOY", root), "DEPLOY")
      ].join("\n")
    end

    def publish_snapshot(target, label)
      return "snapshot:#{label.downcase}: not found: #{target}" unless File.directory?(target)
      dirs, files = collect_snapshot_files(target)
      stamp       = Time.now.utc.iso8601
      buf, stats  = render_snapshot_body(target, label, stamp, dirs, files)
      publish_snapshot_gist(label, buf, files.size, stats)
    end

    def collect_snapshot_files(root)
      skip_path = ->(rel) { rel.split("/").any? { |s| SKIP_SEGS.include?(s) } }
      text_file = ->(f)   { TEXT_EXTS.include?(File.extname(f).downcase) || TEXT_NAMES.include?(File.basename(f)) }
      all = Dir.glob(File.join(root, "**", "*"))
               .reject { |f| File.basename(f).start_with?(".") }
               .reject { |f| skip_path.(f.delete_prefix("#{root}/")) }
               .sort
      dirs  = all.select { |f| File.directory?(f) }
      files = all.select { |f| File.file?(f) && text_file.(f) && File.size(f) < CTX_WINDOW_SIZE }
      [dirs, files]
    end

    def render_snapshot_body(root, label, stamp, dirs, files)
      buf = ["# #{label} Snapshot — #{stamp}", "", "## Tree", "```"]
      buf.concat(render_tree(root, dirs, files))
      buf << "```" << ""
      n_lines, n_trunc = render_snapshot_files(buf, root, files)
      buf << "files: #{files.size} / lines: #{n_lines} / truncated: #{n_trunc}"
      [buf.join("\n"), { lines: n_lines, truncated: n_trunc }]
    end

    # Indented tree: one entry per line, two spaces per depth, dirs with trailing slash.
    def render_tree(root, dirs, files)
      entries = dirs.map { |d| [d.delete_prefix("#{root}/"), :dir] } +
                files.map { |f| [f.delete_prefix("#{root}/"), :file] }
      entries.sort_by { |rel, _| rel.split("/") }.map do |rel, kind|
        depth  = rel.count("/")
        name   = File.basename(rel)
        suffix = kind == :dir ? "/" : ""
        "#{"  " * depth}#{name}#{suffix}"
      end
    end

    def render_snapshot_files(buf, root, files)
      max_lines = 400
      n_trunc   = 0
      n_lines   = 0
      files.each do |f|
        rel  = f.delete_prefix("#{root}/")
        lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        body = File.read(f, encoding: "UTF-8", invalid: :replace).lines
        n_lines += body.size
        buf << "## `#{rel}`" << "```#{lang}"
        if body.size > max_lines
          buf.concat(body.first(max_lines).map(&:rstrip))
          buf << "... #{body.size - max_lines} lines truncated (#{body.size} total)"
          n_trunc += 1
        else
          buf.concat(body.map(&:rstrip))
        end
        buf << "```" << ""
      rescue StandardError => e
        buf << "## `#{rel}`" << "[skipped: #{e.message}]" << ""
      end
      [n_lines, n_trunc]
    end

    def publish_snapshot_gist(label, body, file_count, stats)
      day = Time.now.strftime("%Y-%m-%d")
      out, status = Open3.capture2e(
        "gh", "gist", "create", "-",
        "--public", "--desc", "#{label} #{day}",
        "--filename", "snapshot_latest.md",
        stdin_data: body
      )
      return "snapshot:#{label.downcase}: gist publish failed: #{out.strip}" unless status.success?
      "snapshot:#{label.downcase}: #{file_count} files #{stats[:lines]} lines → #{out.strip}"
    end

    SCORE_WEIGHTS = { error: 10, critical: 10, warning: 3, style: 1 }.freeze

    def score_file(scanner, arg)
      return "usage: /score <file>" if arg.empty?
      path = File.expand_path(arg)
      return "not found: #{arg}" unless File.exist?(path)

      lines = File.read(path, encoding: "UTF-8").lines
      return "empty file" if lines.empty?

      stats      = score_line_stats(lines)
      violations = score_violations(scanner, path)
      penalty    = violations.sum { |v| SCORE_WEIGHTS[v[:severity]] || 1 }
      score      = [100 - penalty, 0].max

      format_score(path, lines.size, stats, violations, penalty, score)
    end

    def score_line_stats(lines)
      {
        blank:   lines.count { |l| l.strip.empty? },
        comment: lines.count { |l| l.strip.start_with?("#") },
        long:    lines.count { |l| l.chomp.length > 100 }
      }
    end

    def score_violations(scanner, path)
      result = scanner&.scan(path, depth: :standard)
      Result.wrap(result).value_or([])
    end

    def format_score(path, total, stats, violations, penalty, score)
      by_rule = violations.group_by { |v| v[:rule] }
                          .sort_by { |_, vs| -vs.size }
                          .map { |rule, vs| "  #{rule}: #{vs.size}" }
      out = [
        "score: #{score}/100  #{path.split("/").last}",
        "  #{total} lines  #{stats[:blank]} blank  #{stats[:comment]} comment  #{stats[:long]} over 100 chars",
        "  #{violations.size} violation(s)  -#{penalty} pts"
      ]
      out.concat(by_rule) unless by_rule.empty?
      out.join("\n")
    end

    def dispatch_heartbeat(heartbeat, arg)
      case arg
      when "run"   then run_heartbeat(heartbeat)
      when "start" then heartbeat&.start!; "heartbeat started"
      when "stop"  then heartbeat&.stop!;  "heartbeat stopped"
      else heartbeat&.list || "no heartbeat"
      end
    end

    def run_heartbeat(heartbeat)
      return "no heartbeat" unless heartbeat
      heartbeat.run_due!.map { |r| "#{r[:name]}: #{r[:result]}" }.join("\n")
    end

    def utility_commands(agent, root, cache, code_index = nil)
      {
        "snapshot"  => ->(_ctx) { dispatch_snapshot(root) },
        "repo_map"  => cmd(:dispatch_repo_map, code_index, root),
        "tree"      => cmd(:dispatch_tree, root),
        "cache"     => cmd(:dispatch_cache, cache),
        "diff"      => cmd(:dispatch_diff, root),
        "commit"    => ->(_ctx) { dispatch_commit(agent, root) },
        "knowledge" => cmd(:dispatch_knowledge, root)
      }
    end

    def dispatch_repo_map(code_index, root, arg)
      return "no code_index" unless code_index
      budget = arg.to_i.positive? ? arg.to_i : Master::RepoMap::DEFAULT_TOKEN_BUDGET
      Master::RepoMap.new(code_index:, root:, token_budget: budget).render
    end

    def dispatch_cache(cache, arg)
      if arg == "clear"
        cache.invalidate_all!
        return "cache cleared"
      end
      stats  = cache.stats
      suffix = arg == "stats" ? "" : "  (use /cache clear to purge)"
      "cache: #{stats[:entries]} entries, #{stats[:size_kb]} KB#{suffix}"
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
      prompt = "Write a concise git commit message (1 line, imperative mood) for these changes:\n#{diff}"
      msg = agent.ask_once(prompt).strip.lines.first.to_s.strip
      Open3.capture2e("git", "-C", root, "add", "-u")
      out, = Open3.capture2e("git", "-C", root, "commit", "-m", msg)
      out.strip
    end

    def dispatch_knowledge(root, arg)
      return "usage: /knowledge add <url>" unless arg.start_with?("add ")
      url = arg.sub("add ", "").strip
      return "usage: /knowledge add <url>" if url.empty?

      require "open-uri"
      parsed = URI(url) rescue nil
      return "knowledge: only http/https URLs allowed" unless parsed && %w[http https].include?(parsed.scheme)

      slug = url.gsub(/[^a-z0-9._-]/i, "_").downcase[0, 60]
      kdir = File.join(root, "knowledge", "web")
      FileUtils.mkdir_p(kdir)
      dest    = File.join(kdir, "#{slug}.txt")
      content = parsed.open(read_timeout: 15, &:read)
                      .encode("UTF-8", invalid: :replace, undef: :replace)
      File.write(dest, content, encoding: "UTF-8")
      "saved #{content.bytesize} bytes to knowledge/web/#{slug}.txt"
    end
  end
end
