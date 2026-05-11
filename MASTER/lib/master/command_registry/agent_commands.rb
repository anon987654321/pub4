# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def agent_commands(ai:, root:, infra:)
      scan_loop_commands(ai:, root:, infra:)
        .merge(model_agent_commands(ai:, root:, infra:))
        .merge(crit_command(ai:, root:))
        .merge(ideate_command(ai:))
        .merge(topic_command(infra:))
        .merge(rsi_command(infra:))
        .merge(triad_command(ai:, root:, infra:))
        .merge(why_command(infra:))
    end

    def why_command(infra:)
      trace = infra[:trace]
      {
        "why" => ->(_ctx) { trace ? trace.pretty_last : "trace not configured" }
      }
    end

    AUTO_MAX_ROUNDS = 4
    AUTO_PLATEAU_RATIO = 0.05

    def triad_command(ai:, root:, infra:)
      bus          = infra[:bus]
      cmds         = scan_loop_commands(ai:, root:, infra:)
      deliberation = ai[:deliberation]
      auto = ->(ctx) {
        target = arg_for(ctx)
        target = "." if target.empty?
        run_auto_cascade(target, cmds, deliberation, bus)
      }
      { "auto" => auto }
    end

    def run_auto_cascade(target, cmds, deliberation, bus)
      bus&.publish("auto:start", target: target)
      prev_violations = nil
      transcript = []
      AUTO_MAX_ROUNDS.times do |round|
        scan_out  = cmds["scan"].call(args: target)
        violations = scan_out.scan(/(\d+) violation/).flatten.map(&:to_i).sum
        bus&.publish("auto:round", round: round + 1, violations: violations)
        if prev_violations && violations > 0 && (prev_violations - violations).abs.to_f / prev_violations < AUTO_PLATEAU_RATIO
          transcript << "round #{round + 1}: plateau at #{violations} violation(s)"
          break
        end
        sweep_out = cmds["sweep"].call(args: target)
        artifact  = "scan:\n#{scan_out}\n\nsweep:\n#{sweep_out}"
        verdict   = run_tribunal(deliberation, artifact, target, bus)
        transcript << "round #{round + 1}: violations=#{violations}\n#{verdict.lines.first(3).join}"
        prev_violations = violations
        break if violations.zero?
      end
      bus&.publish("auto:done", rounds: transcript.size)
      "auto cascade (#{transcript.size} round(s)):\n#{transcript.join("\n---\n")}"
    end

    def run_tribunal(deliberation, artifact, target, bus = nil)
      return "tribunal: deliberation not configured" unless deliberation

      result = deliberation.review(artifact, context: target)
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
        out << ""
        out << "vetoes:"
        vetoes.each { |v| out << "  #{v[:persona]}: #{v[:feedback].to_s.strip.sub(/\AVETO:\s*/i, '')}" }
      end
      out << ""
      out << "jurors:"
      jurors.each do |f|
        axiom = f[:axiom] ? "[#{f[:axiom]}] " : ""
        body  = f[:feedback].to_s.strip.lines.first(3).map(&:chomp).join(" ")
        out << "  #{axiom}#{f[:persona]} (#{f[:role]}): #{body}"
      end
      bus&.publish("tribunal:rendered", jurors: jurors.size, vetoes: vetoes.size, judge: !judge.nil?)
      out.join("\n")
    end

    def scan_loop_commands(ai:, root:, infra:)
      agent        = ai[:agent]
      scanner      = ai[:scanner]
      bus          = infra[:bus]
      deliberation = ai[:deliberation]
      autoloop     = ai[:autoloop]
      code_index   = infra[:code_index]
      {
        "autoloop" => cmd(:run_autoloop, autoloop),
        "sweep"    => ->(ctx) {
          target = expand_or_root(arg_for(ctx), root)
          run_sweep(agent, scanner, deliberation, root, bus, code_index, target)
        },
        "scan"     => cmd(:dispatch_scan, scanner, root)
      }
    end

    def run_autoloop(autoloop, raw)
      max = raw.to_i
      max = AutoLoop::MAX_CYCLES if max <= 0
      result = autoloop.run(max_cycles: max) { |cycle, violations|
        top = violations.first(3).map { |v| "#{File.basename(v[:file])}:#{v[:rule]}" }.join(" ")
        $stdout.puts "autoloop: cycle #{cycle} #{violations.size} violation(s) #{top}"
        $stdout.flush
      }
      result.ok? ? result.value! : result.message
    end

    def run_sweep(agent, scanner, deliberation, root, bus, code_index, target)
      sweeper = Sweep.new(
        agent:, scanner:, council: deliberation, root:,
        event_bus: bus, code_index: code_index
      )
      result = sweeper.run(target) { |cycle, file, delta|
        $stdout.puts "sweep: cycle #{cycle} #{file} +#{delta}"
        $stdout.flush
      }
      result.ok? ? result.value! : result.message
    end

    def dispatch_scan(scanner, root, arg)
      profile, depth, rule_filter = resolve_scan_profile(arg, root)
      pairs = collect_scan_pairs(scanner, root, arg, depth)
      return pairs if pairs.is_a?(String)
      format_scan_results(pairs, profile, rule_filter)
    end

    def collect_scan_pairs(scanner, root, arg, depth)
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

    def model_agent_commands(ai:, root:, infra:)
      council_meta_commands(ai:, root:, infra:).merge(model_commands(ai:, root:, infra:))
    end

    def council_meta_commands(ai:, root:, infra:)
      stage        = ai[:council_stage]
      swarm        = ai[:swarm]
      deliberation = ai[:deliberation]
      bus          = infra[:bus]
      {
        "council" => ->(ctx) { dispatch_council(stage, deliberation, root, bus, arg_for(ctx)) },
        "swarm"   => cmd(:dispatch_swarm, swarm),
        "explain" => ->(_ctx) { explain_master(root) }
      }
    end

    def dispatch_council(stage, deliberation, root, bus, arg)
      case arg
      when "on"     then stage.enable!;  "council: enabled in pipeline"
      when "off"    then stage.disable!; "council: disabled in pipeline"
      when "status" then "council: #{stage.enabled? ? "on" : "off"} in pipeline"
      else
        target   = arg.empty? ? "." : arg
        artifact = snapshot_artifact(expand_or_root(target, root))
        run_tribunal(deliberation, artifact, target, bus)
      end
    end

    def snapshot_artifact(abs_path)
      return "not found: #{abs_path}" unless File.exist?(abs_path)
      return File.read(abs_path).b[0, 16_000] if File.file?(abs_path)
      files = Dir.glob(File.join(abs_path, "**/*.{rb,erb,yml}")).first(40)
      files.map { |f| "--- #{f.sub(abs_path + "/", "")} ---\n#{File.read(f).b[0, 800]}" }.join("\n\n")[0, 24_000]
    end

    def dispatch_swarm(swarm, arg)
      role, task = arg.split(" ", 2)
      task = task.to_s
      return "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}" if role.nil? || task.empty?
      result = swarm.dispatch(role.to_sym, task:, context_slice: {})
      result.ok? ? result.value!.inspect : result.message
    end

    def explain_master(root)
      map    = Introspection::SelfMap.new(root:)
      info   = map.describe
      cov    = map.axiom_coverage.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
      stages = "Intake->Infer->Route->Guard->Execute->Council->Lint->Prune->Memo->Render"
      "MASTER -- #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov}"
    end

    def model_commands(ai:, root:, infra:)
      agent   = ai[:agent]
      config  = infra[:config]
      metrics = infra[:metrics]
      {
        "model" => cmd(:dispatch_model, agent, config, metrics, root),
        "why"   => cmd(:dispatch_why, agent, root)
      }
    end

    def dispatch_model(agent, config, metrics, root, arg)
      return list_models(root, metrics, agent) if arg == "list"
      return "model: #{agent.model}" if arg.empty?
      agent.model = arg
      config.save!
      "model: #{arg}"
    end

    def dispatch_why(agent, root, rule)
      return "usage: /why <law|scan_rule|anti_pattern|style.key>" if rule.empty?
      local = WhyExplainer.new(root:).explain(rule)
      return local if local
      agent.ask_once("Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                     "give a before/after Ruby example, and state why it matters.")
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

    def crit_command(ai:, root:)
      deliberation = ai[:deliberation]
      {
        "crit" => cmd(:dispatch_crit, deliberation, root)
      }
    end

    def dispatch_crit(deliberation, root, arg)
      return "usage: /crit <file|text>" if arg.empty?
      path    = File.expand_path(arg, root)
      payload = File.exist?(path) ? File.read(path, encoding: "UTF-8") : arg
      result  = deliberation.review(payload, context: "explicit /crit session")
      return result.message if result.err?
      format_crit_feedback(result.value!)
    end

    def format_crit_feedback(feedback)
      feedback.map { |f|
        veto = f[:veto_role] ? " [VETO ELIGIBLE]" : ""
        "#{f[:persona]} (#{f[:role]})#{veto}:\n#{f[:feedback].to_s.strip}"
      }.join("\n\n---\n\n")
    end

    def topic_command(infra:)
      session = infra[:session]
      {
        "topic" => cmd(:dispatch_topic, session)
      }
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

    def ideate_command(ai:)
      ideation = ai[:ideation]
      {
        "ideate" => cmd(:dispatch_ideate, ideation)
      }
    end

    def dispatch_ideate(ideation, arg)
      return "usage: /ideate <prompt> [-- constraint1, constraint2]" if arg.empty?
      prompt, constraints_raw = arg.split(" -- ", 2)
      constraints = constraints_raw ? constraints_raw.split(",").map(&:strip).reject(&:empty?) : []
      result = ideation.ideate(prompt.strip, constraints:)
      return result.message if result.err?
      format_ideate(result.value!)
    end

    def format_ideate(v)
      lines = ["ideas (#{v[:ideas].size}):"]
      v[:ideas].each { |i| lines << "  - #{i}" }
      lines << ""
      v[:critiques].each_with_index { |c, n| lines << "critique #{n + 1}: #{c}" }
      lines << ""
      lines << "synthesis:"
      lines << v[:final]
      lines.join("\n")
    end

    def rsi_command(infra:)
      learnings = infra[:learnings]
      {
        "rsi" => cmd(:dispatch_rsi, learnings)
      }
    end

    def dispatch_rsi(learnings, arg)
      return "no learnings configured" unless learnings

      case arg
      when "stats"            then format_rsi_stats(learnings)
      when /\Astats (.+)\z/   then format_rsi_dimension(learnings, $1.strip)
      else                         format_rsi_opportunities(learnings)
      end
    end

    def format_rsi_stats(learnings)
      all = learnings.all
      return "no learnings recorded" if all.empty?
      lines = all.last(10).map { |e| "  #{e["trigger"][0, 40]}: #{e["outcome"]} (conf=#{e["confidence"]})" }
      "learnings (last 10):\n#{lines.join("\n")}"
    end

    def format_rsi_dimension(learnings, dim)
      stats = learnings.stats_by_dimension(dim)
      "#{dim}: success=#{stats[:success]} failure=#{stats[:failure]} fail_rate=#{stats[:fail_rate]}"
    end

    def format_rsi_opportunities(learnings)
      ops = learnings.opportunities
      return "rsi: no opportunities detected in last 7 days" if ops.empty?
      lines = ops.map { |o| format_rsi_opportunity(o) }
      "rsi opportunities (7d):\n#{lines.join("\n")}\n\nuse /rsi stats [dimension] for details"
    end

    def format_rsi_opportunity(o)
      case o[:category]
      when :high_failure        then "  HIGH_FAIL  #{o[:dimension]}: fail_rate=#{o[:fail_rate]} (#{o[:total]} calls)"
      when :repeated_correction then "  CORRECTION #{o[:dimension]}: #{o[:count]} corrections"
      when :provider_errors     then "  PROVIDER   #{o[:dimension]}: #{o[:count]} errors"
      end
    end

    def arg_for(ctx)
      ctx[:args].to_s.strip
    end

    def expand_or_root(arg, root)
      arg.empty? ? root : File.expand_path(arg, root)
    end

    # cmd — DSL helper. Wraps `->(ctx) { send(method, *services, arg_for(ctx)) }`.
    def cmd(method, *services)
      ->(ctx) { send(method, *services, arg_for(ctx)) }
    end
  end
end
