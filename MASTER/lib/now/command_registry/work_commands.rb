# frozen_string_literal: true

module Master
  module Now
  module CommandRegistry
    module_function

    VIOLATION_TRUNCATE = Master::VIOLATION_TRUNCATE

    def work_commands(ai:, root:, infra:)
      scanner      = ai[:scanner]
      fix_loop     = ai[:fix_loop]
      deliberation = ai[:deliberation]
      council_stage = ai[:council_stage]
      agent        = ai[:agent]
      propose_tree = ai[:propose_tree]
      session      = infra[:session]
      bus          = infra[:bus]
      config       = infra[:config]
      metrics      = infra[:metrics]
      {
        "scan" => cmd(:dispatch_scan, scanner, root),
        "fix" => ->(ctx) {
          target = expand_or_root(arg_for(ctx), root)
          result = fix_loop.run(target)
          result.ok? ? result.value! : "fix: #{result.message}"
        },
        "review" => ->(ctx) { dispatch_review(council_stage:, deliberation:, root:, bus:, arg: arg_for(ctx)) },
        "critique" => cmd(:dispatch_critique, deliberation, root),
        "model" => ->(c) { dispatch_model(agent:, config:, metrics:, root:, arg: arg_for(c)) },
        "why" => cmd(:dispatch_why, agent, root),
        "axioms" => cmd(:dispatch_axioms, scanner, root),
        "topic" => cmd(:dispatch_topic, session),
        "propose-tree" => ->(_ctx) { propose_tree&.call || "propose-tree: not wired" }
      }
    end

    # Constitutional scoreboard: per-axiom violation counts over lib/, plus a
    # rule dep-graph completeness report.
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

    def ungraphed_rules(root)
      registered = Master::Judge::Scan::Rule.registry.map { |k| k.new.id.upcase }.uniq
      graph      = (Master.load_yaml(File.join(root, "data", "rule_deps.yml")) || {})["deps"] || {}
      graphed    = (graph.keys + graph.values.flat_map { |v| Array(v["after"]) }).map(&:to_s).uniq
      (registered - graphed).sort
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "command_registry.ungraphed_rules")
      []
    end

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
  end
  end
end
