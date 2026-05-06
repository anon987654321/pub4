# frozen_string_literal: true

module Master
  module CommandRegistry
    BINARY_SNIFF_BYTES = 512

    module_function

    def control_commands(standing, soul)
      {
        "orders" => ->(ctx) { dispatch_orders(standing, ctx[:args].to_s.strip) },
        "soul"   => ->(ctx) { dispatch_soul(soul, ctx[:args].to_s.strip) }
      }
    end

    def service_commands(ai, phase_gates = nil, diag: nil)
      heartbeat = ai[:heartbeat]
      skills    = ai[:skills]
      scanner   = ai[:scanner]
      {
        "heartbeat" => ->(ctx) { dispatch_heartbeat(heartbeat, ctx[:args].to_s.strip) },
        "skills"    => ->(ctx) {
          arg   = ctx[:args].to_s.strip
          found = skills&.find(arg)
          arg.empty? ? (skills&.list || "(no skills)") : (found ? "#{found[:name]}: #{found[:description]}" : "(not found: #{arg})")
        },
        "phase" => ->(ctx) { dispatch_phase(phase_gates, ctx[:args].to_s.strip) },
        "score" => ->(ctx) { score_file(scanner, ctx[:args].to_s.strip) },
        "diag"  => ->(ctx) { diag ? diag.render(ctx[:args].to_s.strip) : "diag: not configured" }
      }
    end

    def dispatch_phase(gates, arg)
      return "no phase_gates configured" unless gates
      case arg
      when "", "status" then gates.status
      when "advance"    then result = gates.advance!; result.ok? ? result.value! : result.message
      when /\Aforce (.+)\z/  then gates.force!($1.strip).value!
      when /\Ameet (.+)\z/   then gates.meet_gate!($1.strip); "gate met: #{$1.strip}"
      else "phase: #{gates.current}  /phase [status|advance|force <name>|meet <gate>]"
      end
    end

    def dispatch_orders(standing, arg)
      case arg
      when "list", "" then standing.list
      when /\Aenable (.+)\z/  then standing.enable($1.strip)
      when /\Adisable (.+)\z/ then standing.disable($1.strip)
      when /\Aadd name=(\S+) cmd=(.+)\z/ then standing.upsert(name: $1, command: $2.strip)
      when "run"
        results = standing.run_due!
        results.empty? ? "no orders due" :
          results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
      when /\Areset (.+)\z/ then standing.reset($1.strip)
      else "usage: /orders  /orders enable|disable|reset <name>  /orders run"
      end
    end

    def dispatch_soul(soul, arg)
      case arg
      when "", "show"          then soul.summary
      when "version", "changelog" then soul.changelog
      when "diff"              then soul.diff
      when "approve"           then soul.approve
      when "reject"            then soul.reject
      when "rollback"          then soul.rollback
      when /\Apropose (.+)\z/  then soul.propose($1.strip)
      else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
      end
    end

    TEXT_EXTS  = %w[.rb .py .js .ts .zsh .sh .bash .md .yml .yaml .json .toml .gemspec .txt .erb .conf .ini .env].to_set.freeze
    TEXT_NAMES = %w[Gemfile Rakefile Makefile Dockerfile].to_set.freeze
    SKIP_SEGS  = %w[.git vendor tmp var node_modules .bundle coverage log dist knowledge].to_set.freeze

    def dispatch_snapshot(root)
      out       = File.join(root, "snapshot_latest.md")
      skip_path = ->(rel) { rel.split("/").any? { |s| SKIP_SEGS.include?(s) } }
      text_file = ->(f)   { TEXT_EXTS.include?(File.extname(f).downcase) || TEXT_NAMES.include?(File.basename(f)) }

      all   = Dir.glob(File.join(root, "**", "*")).reject { |f| File.basename(f).start_with?(".") }
                 .reject { |f| skip_path.(f.delete_prefix("#{root}/")) }.sort
      dirs  = all.select { |f| File.directory?(f) }
      files = all.select { |f| File.file?(f) && text_file.(f) && File.size(f) < CTX_WINDOW_SIZE }

      stamp = Time.now.utc.iso8601
      buf   = ["# MASTER Snapshot — #{stamp}", "", "## Tree", "```"]
      dirs.each  { |d| buf << "#{d.delete_prefix("#{root}/")}/" }
      files.each { |f| buf << f.delete_prefix("#{root}/") }
      buf << "```" << ""

      max_file_lines = 400
      n_trunc = 0
      n_lines = 0

      files.each do |f|
        rel  = f.delete_prefix("#{root}/")
        lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        body = File.read(f, encoding: "UTF-8", invalid: :replace).lines
        n_lines += body.size
        buf << "## `#{rel}`" << "```#{lang}"
        if body.size > max_file_lines
          buf.concat(body.first(max_file_lines).map(&:rstrip))
          buf << "... #{body.size - max_file_lines} lines truncated (#{body.size} total)"
          n_trunc += 1
        else
          buf.concat(body.map(&:rstrip))
        end
        buf << "```" << ""
      rescue StandardError => e
        buf << "## `#{rel}`" << "[skipped: #{e.message}]" << ""
      end

      buf << "files: #{files.size} / lines: #{n_lines} / truncated: #{n_trunc} / est. tokens: ~#{n_lines * 6 / 5}"
      tmp = "#{out}.tmp.#{Process.pid}"
      File.write(tmp, buf.join("\n"))
      File.rename(tmp, out)

      day = Time.now.strftime("%Y-%m-%d")
      gist_out, gist_st = Open3.capture2e("gh", "gist", "create", out,
                                          "--public", "--desc", "MASTER #{day}",
                                          "--filename", "snapshot_latest.md")
      gist_url = gist_st.success? ? " → #{gist_out.strip}" : ""
      "snapshot: #{files.size} files #{n_lines} lines#{gist_url}"
    end

    SCORE_WEIGHTS = { error: 10, critical: 10, warning: 3, style: 1 }.freeze

    def score_file(scanner, arg)
      return "usage: /score <file>" if arg.empty?
      path = File.expand_path(arg)
      return "not found: #{arg}" unless File.exist?(path)

      src   = File.read(path, encoding: "UTF-8")
      lines = src.lines
      total = lines.size
      return "empty file" if total.zero?

      blank   = lines.count { |l| l.strip.empty? }
      comment = lines.count { |l| l.strip.start_with?("#") }
      long    = lines.count { |l| l.chomp.length > 100 }

      result = scanner&.scan(path, depth: :standard)
      violations = result.respond_to?(:ok?) && result.ok? ? result.value! : []

      penalty = violations.sum { |v| SCORE_WEIGHTS[v[:severity]] || 1 }
      score   = [100 - penalty, 0].max

      by_rule = violations.group_by { |v| v[:rule] }
                          .sort_by { |_, vs| -vs.size }
                          .map { |rule, vs| "  #{rule}: #{vs.size}" }

      lines_out = [
        "score: #{score}/100  #{path.split("/").last}",
        "  #{total} lines  #{blank} blank  #{comment} comment  #{long} over 100 chars",
        "  #{violations.size} violation(s)  -#{penalty} pts"
      ]
      lines_out.concat(by_rule) unless by_rule.empty?
      lines_out.join("\n")
    end

    def dispatch_heartbeat(heartbeat, arg)
      case arg
      when "run"   then heartbeat ? heartbeat.run_due!.map { |r| "#{r[:name]}: #{r[:result]}" }.join("\n") : "no heartbeat"
      when "start" then heartbeat&.start!; "heartbeat started"
      when "stop"  then heartbeat&.stop!;  "heartbeat stopped"
      else heartbeat&.list || "no heartbeat"
      end
    end

    def utility_commands(agent, root, cache)
      {
        "snapshot" => ->(_ctx) { dispatch_snapshot(root) },
        "cache" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "clear"
            cache.invalidate_all!
            "cache cleared"
          else
            stats = cache.stats
            suffix = arg == "stats" ? "" : "  (use /cache clear to purge)"
            "cache: #{stats[:entries]} entries, #{stats[:size_kb]} KB#{suffix}"
          end
        },
        "diff" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          base = arg.empty? ? "HEAD" : arg
          out, = Open3.capture2e("git", "-C", root, "diff", base, "--stat")
          out.strip.empty? ? "(no changes since #{base})" : out.strip
        },
        "commit" => ->(_ctx) {
          diff, = Open3.capture2e("git", "-C", root, "diff", "--cached", "--stat")
          diff, = Open3.capture2e("git", "-C", root, "diff", "--stat") if diff.strip.empty?
          next "nothing to commit" if diff.strip.empty?
          prompt = "Write a concise git commit message (1 line, imperative mood) for these changes:\n#{diff}"
          msg = agent.ask_once(prompt).strip.lines.first.to_s.strip
          Open3.capture2e("git", "-C", root, "add", "-u")
          out, = Open3.capture2e("git", "-C", root, "commit", "-m", msg)
          out.strip
        },
        "knowledge" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.start_with?("add ")
            url = arg.sub("add ", "").strip
            require "open-uri"
            next "usage: /knowledge add <url>" if url.empty?
            parsed = URI(url) rescue nil
            next "knowledge: only http/https URLs allowed" unless parsed && %w[http https].include?(parsed.scheme)
            slug = url.gsub(/[^a-z0-9._-]/i, "_").downcase[0, 60]
            kdir = File.join(root, "knowledge", "web")
            FileUtils.mkdir_p(kdir)
            dest = File.join(kdir, "#{slug}.txt")
            content = parsed.open(read_timeout: 15, &:read)
                            .encode("UTF-8", invalid: :replace, undef: :replace)
            File.write(dest, content, encoding: "UTF-8")
            "saved #{content.bytesize} bytes to knowledge/web/#{slug}.txt"
          else
            "usage: /knowledge add <url>"
          end
        }
      }
    end
  end
end
