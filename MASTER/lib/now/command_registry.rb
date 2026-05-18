# frozen_string_literal: true

require "open3"
require_relative "command_registry/memory_commands"

module Master
  module Now
  # CommandRegistry — all pipeline-routable slash commands.
  module CommandRegistry
    module_function

    def build(infra:, ai:, root:)
      session_commands(infra).merge(
        mode_commands(infra[:config]),
        memory_commands(infra[:memory], ai[:agent]),
        work_commands(ai:, root:, infra:),
        control_commands(ai[:standing], ai[:soul]),
        system_commands(ai[:agent], infra[:diag], root),
        "orient" => ->(_ctx) { Master::Orient.render(root:) },
        "help" => ->(_ctx) {
          [
            "session: /save /clear /history [N] /tokens /cost /undo /redo /exit",
            "work:    /scan [profile] [path]  /fix [path]  /review [on|off|path]  /critique <text>  /why <rule>  /axioms  /topic [desc]",
            "model:   /model [id|list] /mode /persona /task",
            "memory:  /memory  /dreams",
            "system:  /orient /tree [N] /diff [ref] /commit /snapshot /diag [section] /dmesg /reload /help"
          ].join("\n")
        }
      )
    end

    # ── Session ──────────────────────────────────────────────────────────────

    def session_commands(infra)
      session = infra[:session]
      undo    = infra[:undo]
      logging = infra[:logging]
      config  = infra[:config]
      {
        "clear"   => ->(_ctx) { session.clear!; "context cleared" },
        "save"    => ->(_ctx) { session.save!; "session saved" },
        "history" => ->(ctx) {
          n = ctx[:args].to_s.strip.to_i
          n = 10 if n <= 0
          recent = session.messages.last(n)
          next "history: empty" if recent.empty?
          recent.map { |m| "[#{m[:role]}] #{m[:content].to_s.gsub(/\s+/, " ")[0, 120]}" }.join("\n")
        },
        "tokens"  => ->(_ctx) { "~#{session.token_est} tokens" },
        "cost"    => ->(_ctx) { "$#{"%.4f" % session.cost}" },
        "undo"    => ->(_ctx) { r = undo.undo!;  r.ok? ? "reverted: #{r.value!}"   : r.message },
        "redo"    => ->(_ctx) { r = undo.redo!;  r.ok? ? "reapplied: #{r.value!}"  : r.message },
        "dmesg"   => ->(_ctx) { logging.dmesg },
        "config"  => ->(_ctx) { config.to_h.inspect }
      }
    end

    # ── Mode / persona / model flag commands ─────────────────────────────────

    def mode_commands(config)
      reasoning_commands(config).merge(persona_commands(config)).merge(flag_commands(config))
    end

    def reasoning_commands(config)
      {
        "mode" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          Master::Judge::Modes::SUPPORTED.include?(arg) ?
            (config["reasoning_mode"] = arg; config.save!; "mode: #{arg}") :
            "mode: #{config.reasoning_mode} (supported: #{Master::Judge::Modes::SUPPORTED.join(", ")})"
        },
        "task" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          arg.empty? ? "task_type: #{config.task_type}" : (config["task_type"] = arg; config.save!; "task_type: #{arg}")
        }
      }
    end

    def persona_commands(config)
      {
        "persona" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          return "persona: #{config.persona}" if arg.empty?
          config["persona"] = arg; config.save!; "persona: #{arg}"
        }
      }
    end

    def flag_commands(config)
      flags = %w[auto_review auto_lint auto_commit]
      flags.each_with_object({}) do |flag, h|
        h[flag] = ->(ctx) {
          arg = ctx[:args].to_s.strip
          arg.empty? ? "#{flag}: #{config[flag]}" : (config[flag] = arg == "on"; config.save!; "#{flag}: #{config[flag]}")
        }
      end
    end

    # ── Control (standing orders, soul) ──────────────────────────────────────

    def control_commands(standing, soul)
      {
        "orders" => cmd(:dispatch_orders, standing),
        "soul"   => cmd(:dispatch_soul, soul)
      }
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

    # ── Work (scan, fix, review, critique, model, why, topic) ───────────────

    def work_commands(ai:, root:, infra:)
      scanner      = ai[:scanner]
      super_loop   = ai[:super_loop]
      deliberation = ai[:deliberation]
      council_stage = ai[:council_stage]
      agent        = ai[:agent]
      session      = infra[:session]
      bus          = infra[:bus]
      trace        = infra[:trace]
      config       = infra[:config]
      metrics      = infra[:metrics]
      {
        "scan"     => cmd(:dispatch_scan, scanner, root),
        "fix"      => ->(ctx) {
          target = expand_or_root(arg_for(ctx), root)
          result = super_loop.run_to_convergence(target)
          rows   = result[:rule_results].map { |r| "#{r[:rule]}: #{r[:status]} (#{r[:fixed]} fixed)" }
          rows.empty? ? "clean" : "#{rows.join("\n")}\n(#{result[:passes]} pass#{result[:passes] == 1 ? "" : "es"}, #{result[:converged] ? "converged" : "plateau"})"
        },
        "review"   => ->(ctx) { dispatch_review(council_stage:, deliberation:, root:, bus:, arg: arg_for(ctx)) },
        "critique" => cmd(:dispatch_critique, deliberation, root),
        "model"    => ->(c) { dispatch_model(agent:, config:, metrics:, root:, arg: arg_for(c)) },
        "why"      => cmd(:dispatch_why, agent, root),
        "axioms"   => cmd(:dispatch_axioms, scanner, root),
        "topic"    => cmd(:dispatch_topic, session)
      }
    end

    # Constitutional scoreboard: per-axiom violation counts over lib/, plus a
    # rule dep-graph completeness report. /why explains one rule; /axioms the whole.
    AXIOM_SCAN_CAP = 400

    def dispatch_axioms(scanner, root, _arg)
      files    = axiom_scan_files(root)
      by_axiom = tally_axioms(scanner, files)
      [axiom_table(files, by_axiom), "", dep_graph_line(root)].join("\n")
    end

    def axiom_scan_files(root)
      Dir.glob(File.join(root, "lib", "**", "*.rb"))
         .reject { |p| p.include?("/knowledge/") || p.include?("/vendor/") }
         .sort.first(AXIOM_SCAN_CAP)
    end

    # axiom_tag => violation count, across the scanned files.
    def tally_axioms(scanner, files)
      files.each_with_object(Hash.new(0)) do |path, acc|
        result = scanner.scan(path, depth: :deep)
        next unless result.ok?
        result.value!.each { |f| Array(f[:tags]).each { |t| acc[t.to_s] += 1 } }
      end
    end

    def axiom_table(files, by_axiom)
      head = "constitution — #{files.size} files scanned"
      return "#{head}\n  clean: no axiom violations" if by_axiom.empty?
      rows = by_axiom.sort_by { |_, n| -n }.map { |tag, n| "  #{tag.ljust(24)} #{n}" }
      ([head] + rows + ["  total#{" " * 19}#{by_axiom.values.sum}"]).join("\n")
    end

    def dep_graph_line(root)
      gap = ungraphed_rules(root)
      tail = gap.empty? ? " (complete)" : " — #{gap.first(8).join(", ")}"
      "rule dep-graph: #{gap.size} rule(s) absent from rule_deps.yml#{tail}"
    end

    # Scan rules absent from the topological dep graph — surfaces silent staleness.
    def ungraphed_rules(root)
      registered = Master::Judge::Scan::Rule.registry.map { |k| k.new.id.upcase }.uniq
      graph      = (Master.load_yaml(File.join(root, "data", "rule_deps.yml")) || {})["deps"] || {}
      graphed    = (graph.keys + graph.values.flat_map { |v| Array(v["after"]) }).map(&:to_s).uniq
      (registered - graphed).sort
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "command_registry.ungraphed_rules")
      []
    end

    # scan

    VIOLATION_TRUNCATE = Master::VIOLATION_TRUNCATE

    def dispatch_scan(scanner, root, arg)
      profile, depth, rule_filter = resolve_scan_profile(arg, root)
      pairs = collect_scan_pairs(scanner:, root:, arg:, depth:)
      return pairs if pairs.is_a?(String)
      format_scan_results(pairs, profile, rule_filter)
    end

    def collect_scan_pairs(scanner:, root:, arg:, depth:)
      raw_arg    = arg.sub(/\A(?:critical|solid|axioms)\s*/, "").strip
      target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
      if target_arg && File.file?(target_arg)
        [[target_arg, scanner.scan(target_arg, depth:)]]
      else
        dir = (target_arg && File.directory?(target_arg)) ? target_arg : File.join(root, "lib")
        result = scanner.scan_dir(dir, depth:, glob: "**/*", stream: true)
        result.ok? ? result.value! : "scan failed"
      end
    end

    def format_scan_results(pairs, profile, rule_filter)
      by_rule = Hash.new { |h, k| h[k] = [] }
      pairs.each do |_file, file_result|
        Result.wrap(file_result).value_or([]).each do |v|
          next if rule_filter && !rule_filter.include?(v[:rule].to_s)
          by_rule[v[:rule].to_s] << v
        end
      end
      total  = by_rule.values.sum(&:size)
      header = profile ? "[profile: #{profile}] " : ""
      return "#{header}clean -- no violations" if total.zero?
      lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
        ["[#{rule}] #{vs.size}"] + vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
      end
      lines << "#{header}#{total} total violations"
      lines.join("\n")
    end

    def resolve_scan_profile(arg, root)
      groups, profiles = load_workflow_profiles(root)
      profile_name = %w[critical solid axioms].find { |p| arg.start_with?(p) }
      return [nil, :deep, nil] if profile_name.nil?
      cfg         = profiles[profile_name] || {}
      rule_ids    = groups[cfg["rules"].to_s]
      rule_filter = (rule_ids && cfg["rules"] != "*") ? rule_ids.map(&:to_s).to_set : nil
      [profile_name, :deep, rule_filter]
    end

    def load_workflow_profiles(root)
      data = Master.load_yaml(File.join(root, "data", "workflow.yml"))
      [data["principle_groups"] || {}, data["scan_profiles"] || {}]
    rescue StandardError
      [{}, {}]
    end

    # review / critique

    def dispatch_review(council_stage:, deliberation:, root:, bus:, arg:)
      case arg
      when "on"     then council_stage.enable!;  "review: enabled in pipeline"
      when "off"    then council_stage.disable!; "review: disabled in pipeline"
      when "status" then "review: #{council_stage.enabled? ? "on" : "off"} in pipeline"
      else
        target   = arg.empty? ? "." : arg
        artifact = snapshot_artifact(expand_or_root(target, root))
        run_tribunal(deliberation:, artifact:, target:, bus:)
      end
    end

    def run_tribunal(deliberation:, artifact:, target:, bus: nil)
      return "tribunal: deliberation not configured" unless deliberation
      result = deliberation.review_convergent(artifact, context: target)
      return result.message if result.err?
      format_tribunal(result.value!, bus)
    rescue StandardError => e
      "tribunal: #{e.message}"
    end

    def format_tribunal(feedback, bus = nil)
      judge  = feedback.find { |f| f[:role] == "Synthesis" }
      jurors = feedback.reject { |f| f[:role] == "Synthesis" }
      vetoes = jurors.select { |f| f[:veto_role] && f[:feedback].to_s.strip =~ /\AVETO:/i }
      out = []
      out << "verdict: #{judge[:feedback].to_s.strip}" if judge
      unless vetoes.empty?
        out << "" << "vetoes:"
        vetoes.each { |v| out << "  #{v[:persona]}: #{v[:feedback].to_s.strip.sub(/\AVETO:\s*/i, "")}" }
      end
      out << "" << "jurors:"
      jurors.each do |f|
        axiom = f[:axiom] ? "[#{f[:axiom]}] " : ""
        body  = f[:feedback].to_s.strip.lines.first(3).map(&:chomp).join(" ")
        out << "  #{axiom}#{f[:persona]} (#{f[:role]}): #{body}"
      end
      bus&.publish("tribunal:rendered", jurors: jurors.size, vetoes: vetoes.size, judge: !judge.nil?)
      out.join("\n")
    end

    def snapshot_artifact(abs_path)
      return "not found: #{abs_path}" unless File.exist?(abs_path)
      return File.read(abs_path).b[0, 16_000] if File.file?(abs_path)
      files = Dir.glob(File.join(abs_path, "**/*.{rb,erb,yml}")).first(40)
      files.map { |f| "--- #{f.sub(abs_path + "/", "")} ---\n#{File.read(f).b[0, 800]}" }.join("\n\n")[0, 24_000]
    end

    def dispatch_critique(deliberation, root, arg)
      return "usage: /critique <file|text>" if arg.empty?
      path    = File.expand_path(arg, root)
      payload = File.exist?(path) ? File.read(path, encoding: "UTF-8") : arg
      result  = deliberation.review_convergent(payload, context: "explicit /critique session")
      return result.message if result.err?
      deliberation_feedback(result.value!)
    end

    def deliberation_feedback(feedback)
      feedback.map { |f|
        veto = f[:veto_role] ? " [VETO ELIGIBLE]" : ""
        "#{f[:persona]} (#{f[:role]})#{veto}:\n#{f[:feedback].to_s.strip}"
      }.join("\n\n---\n\n")
    end

    # model / why / topic

    def dispatch_model(agent:, config:, metrics:, root:, arg:)
      return list_models(root, metrics, agent) if arg == "list"
      return "model: #{agent.model}" if arg.empty?
      agent.model = arg; config.save!; "model: #{arg}"
    end

    def list_models(root, metrics, agent)
      yml_path = File.join(root, "data", "models.yml")
      return "model: #{agent.model}" unless File.exist?(yml_path)
      data  = Master.load_yaml(yml_path)
      tiers = data["models"] || {}
      model_lines   = tiers.flat_map { |tier, ms| ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" } }
      quality_lines = metrics&.model_quality&.map { |mod, stat|
        "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
      } || []
      sections = ["available models:"] + model_lines
      sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
      sections.join("\n")
    end

    def dispatch_why(agent, root, rule)
      return "usage: /why <law|scan_rule|anti_pattern|style.key>" if rule.empty?
      local = Trace::WhyExplainer.new(root:).explain(rule)
      return local if local
      agent.ask_once("Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                     "give a before/after Ruby example, and state why it matters.")
    end

    def dispatch_topic(session, arg)
      if arg.empty?
        current = session.respond_to?(:topic) ? session.topic : nil
        current ? "topic: #{current}" : "no topic set  /topic <description>"
      else
        session.topic = arg if session.respond_to?(:topic=)
        "topic: #{arg}"
      end
    end

    # ── System (tree, diff, commit, snapshot, diag, reload) ─────────────────

    TEXT_EXTS  = %w[.rb .py .js .ts .zsh .sh .bash .md .yml .yaml .json .toml .gemspec .txt .erb .conf .ini .env].to_set.freeze
    TEXT_NAMES = %w[Gemfile Rakefile Makefile Dockerfile].to_set.freeze
    SKIP_SEGS  = %w[.git vendor tmp var node_modules .bundle coverage log dist knowledge].to_set.freeze

    def system_commands(agent, diag, root)
      {
        "tree"     => cmd(:dispatch_tree, root),
        "diff"     => cmd(:dispatch_diff, root),
        "commit"   => ->(_ctx) { dispatch_commit(agent, root) },
        "snapshot" => ->(_ctx) { dispatch_snapshot(root) },
        "diag"     => ->(ctx) { diag ? diag.render(ctx[:args].to_s.strip) : "diag: not configured" },
        "reload"   => ->(_ctx) { "reload: not supported in this context" }
      }
    end

    def dispatch_tree(root, arg)
      cfg   = (Master.load_yaml(File.join(root, "data", "rules.yml")) || {}).dig("paths", "tree") || {}
      depth = arg.to_i.positive? ? arg.to_i : (cfg["max_depth"] || 2)
      cap   = cfg["max_lines"] || 200
      buf   = []
      walker = lambda do |dir, level|
        return if level > depth || buf.size >= cap
        Dir.children(dir).sort.each do |name|
          break if buf.size >= cap
          next if name.start_with?(".") || SKIP_SEGS.include?(name)
          path = File.join(dir, name)
          buf << "#{"  " * (level - 1)}#{name}#{File.directory?(path) ? "/" : ""}"
          walker.call(path, level + 1) if File.directory?(path)
        end
      rescue Errno::EACCES, Errno::ENOENT
        nil
      end
      walker.call(root, 1)
      buf.join("\n")
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
      msg    = agent.ask_once(prompt).to_s.strip.lines.first.to_s.strip
      Open3.capture2e("git", "-C", root, "add", "-u")
      out, = Open3.capture2e("git", "-C", root, "commit", "-m", msg)
      out.strip
    end

    def dispatch_snapshot(root)
      [
        publish_snapshot(root, "MASTER"),
        publish_snapshot(File.expand_path("../DEPLOY", root), "DEPLOY")
      ].join("\n")
    end

    def publish_snapshot(target, label)
      return "snapshot:#{label.downcase}: not found: #{target}" unless File.directory?(target)
      skip  = ->(rel) { rel.split("/").any? { |s| SKIP_SEGS.include?(s) } }
      text? = ->(f)   { TEXT_EXTS.include?(File.extname(f).downcase) || TEXT_NAMES.include?(File.basename(f)) }
      all   = Dir.glob(File.join(target, "**", "*"))
                 .reject { |f| File.basename(f).start_with?(".") }
                 .reject { |f| skip.(f.delete_prefix("#{target}/")) }.sort
      dirs  = all.select { |f| File.directory?(f) }
      files = all.select { |f| File.file?(f) && text?.(f) && File.size(f) < Master::CTX_WINDOW_SIZE }
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
        "--public", "--desc", "#{label} #{day}",
        "--filename", "snapshot_latest.md",
        stdin_data: md.join("\n"))
      status.success? ? "snapshot:#{label.downcase}: #{files.size} files #{n_lines} lines → #{out.strip}" :
                        "snapshot:#{label.downcase}: gist publish failed: #{out.strip}"
    end

    # ── Helpers ──────────────────────────────────────────────────────────────

    def arg_for(ctx) = ctx[:args].to_s.strip
    def expand_or_root(arg, root) = arg.empty? ? root : File.expand_path(arg, root)
    def cmd(method, *services) = ->(ctx) { send(method, *services, arg_for(ctx)) }
  end
  end
end
