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
    end

    def scan_loop_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      bus = infra[:bus]
      deliberation = ai[:deliberation]
      autoloop = ai[:autoloop]
      {
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          result = autoloop.run(max_cycles: max) { |cycle, violations|
            top = violations.first(3).map { |v| "#{File.basename(v[:file])}:#{v[:rule]}" }.join(" ")
            $stdout.puts "autoloop: cycle #{cycle} #{violations.size} violation(s) #{top}"
            $stdout.flush
          }
          result.ok? ? result.value! : result.message
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus, code_index: infra[:code_index])
          result = sweeper.run(target) { |cycle, file, delta|
            $stdout.puts "sweep: cycle #{cycle} #{file} +#{delta}"
            $stdout.flush
          }
          result.ok? ? result.value! : result.message
        },
        "scan" => ->(ctx) { dispatch_scan(scanner, root, ctx[:args].to_s.strip) }
      }
    end

    def dispatch_scan(scanner, root, arg)
      profile, depth, rule_filter = resolve_scan_profile(arg, root)
      raw_arg    = arg.sub(/\A(?:deep|quick|full|critical|solid|axioms)\s*/, "").strip
      target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
      pairs = if target_arg && File.file?(target_arg)
        [[target_arg, scanner.scan(target_arg, depth:)]]
      elsif target_arg && File.directory?(target_arg)
        result = scanner.scan_dir(target_arg, depth:, glob: "**/*", stream: true)
        return "scan failed" unless result.ok?
        result.value!
      else
        result = scanner.scan_dir(File.join(root, "lib"), depth:, stream: true)
        return "scan failed" unless result.ok?
        result.value!
      end
      by_rule = Hash.new { |h, k| h[k] = [] }
      pairs.each do |_file, file_result|
        next unless file_result.respond_to?(:ok?) && file_result.ok?
        file_result.value!.each do |v|
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
      profiles_cfg = begin
        data = Master.load_yaml(File.join(root, "data", "workflow.yml"))
        groups  = data.dig("principle_groups") || {}
        profiles = data.dig("scan_profiles") || {}
        [groups, profiles]
      rescue StandardError => _e
        [{}, {}]
      end
      groups, profiles = profiles_cfg

      profile_name = %w[quick full critical solid axioms].find { |p| arg.start_with?(p) }
      profile_name ||= "deep" if arg.start_with?("deep")

      if profile_name && profile_name != "deep"
        cfg   = profiles[profile_name] || {}
        depth = (cfg["depth"] == "deep") ? :deep : :standard
        rule_ids = groups[cfg["rules"].to_s]
        rule_filter = (rule_ids && cfg["rules"] != "*") ? rule_ids.map(&:to_s).to_set : nil
        [profile_name, depth, rule_filter]
      elsif profile_name == "deep"
        [nil, :deep, nil]
      else
        [nil, :deep, nil]
      end
    end

    def model_agent_commands(ai:, root:, infra:)
      council_meta_commands(ai:, root:).merge(model_commands(ai:, root:, infra:))
    end

    def council_meta_commands(ai:, root:)
      council_stage = ai[:council_stage]
      swarm         = ai[:swarm]
      {
        "council" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then council_stage.enable!; "council: enabled"
          when "off" then council_stage.disable!; "council: disabled"
          else "council: #{council_stage.enabled? ? "on" : "off"}"
          end
        },
        "swarm"   => ->(ctx) { dispatch_swarm(swarm, ctx[:args].to_s.strip) },
        "explain" => ->(_ctx) { explain_master(root) }
      }
    end

    def dispatch_swarm(swarm, arg)
      parts = arg.split(" ", 2)
      role  = parts[0]&.to_sym
      task  = parts[1].to_s
      return "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}" if role.nil? || task.empty?
      result = swarm.dispatch(role, task:, context_slice: {})
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
        "model" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next list_models(root, metrics, agent) if arg == "list"
          next "model: #{agent.model}" if arg.empty?
          agent.model = arg; config.save!; "model: #{arg}"
        },
        "why" => ->(ctx) {
          rule = ctx[:args].to_s.strip
          next "usage: /why <rule_name>" if rule.empty?
          agent.ask_once("Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                         "give a before/after Ruby example, and state why it matters.")
        }
      }
    end

    def list_models(root, metrics, agent)
      yml_path = File.join(root, "data", "models.yml")
      return "model: #{agent.model}" unless File.exist?(yml_path)
      data = Master.load_yaml(yml_path)
      tiers = data["models"] || {}
      model_lines = tiers.flat_map { |tier, ms| ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" } }
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
        "crit" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /crit <file|text>" if arg.empty?
          payload = if File.exist?(File.expand_path(arg, root))
            File.read(File.expand_path(arg, root), encoding: "UTF-8")
          else
            arg
          end
          result = deliberation.review(payload, context: "explicit /crit session")
          next result.message if result.err?
          format_crit_feedback(result.value!)
        }
      }
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
        "topic" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            current_topic = session.respond_to?(:topic) ? session.topic : nil
            current_topic ? "topic: #{current_topic}" : "no topic set  /topic <description>"
          else
            session.topic = arg if session.respond_to?(:topic=)
            "topic: #{arg}"
          end
        }
      }
    end

    def ideate_command(ai:)
      ideation = ai[:ideation]
      {
        "ideate" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          next "usage: /ideate <prompt> [-- constraint1, constraint2]" if arg.empty?
          prompt, constraints_raw = arg.split(" -- ", 2)
          constraints = constraints_raw ? constraints_raw.split(",").map(&:strip).reject(&:empty?) : []
          result = ideation.ideate(prompt.strip, constraints:)
          next result.message if result.err?
          v = result.value!
          lines = []
          lines << "ideas (#{v[:ideas].size}):"
          v[:ideas].each { |i| lines << "  - #{i}" }
          lines << ""
          v[:critiques].each_with_index { |c, n| lines << "critique #{n + 1}: #{c}" }
          lines << ""
          lines << "synthesis:"
          lines << v[:final]
          lines.join("\n")
        }
      }
    end

    def rsi_command(infra:)
      learnings = infra[:learnings]
      {
        "rsi" => ->(ctx) { dispatch_rsi(learnings, ctx[:args].to_s.strip) }
      }
    end

    def dispatch_rsi(learnings, arg)
      return "no learnings configured" unless learnings

      case arg
      when "stats"
        # Show all dimensions with recorded events
        all = learnings.all
        return "no learnings recorded" if all.empty?
        lines = all.last(10).map { |e| "  #{e["trigger"][0, 40]}: #{e["outcome"]} (conf=#{e["confidence"]})" }
        "learnings (last 10):\n#{lines.join("\n")}"
      when /\Astats (.+)\z/
        dim = $1.strip
        stats = learnings.stats_by_dimension(dim)
        "#{dim}: success=#{stats[:success]} failure=#{stats[:failure]} fail_rate=#{stats[:fail_rate]}"
      else
        ops = learnings.opportunities
        return "rsi: no opportunities detected in last 7 days" if ops.empty?
        lines = ops.map { |o|
          case o[:category]
          when :high_failure       then "  HIGH_FAIL  #{o[:dimension]}: fail_rate=#{o[:fail_rate]} (#{o[:total]} calls)"
          when :repeated_correction then "  CORRECTION #{o[:dimension]}: #{o[:count]} corrections"
          when :provider_errors    then "  PROVIDER   #{o[:dimension]}: #{o[:count]} errors"
          end
        }
        "rsi opportunities (7d):\n#{lines.join("\n")}\n\nuse /rsi stats [dimension] for details"
      end
    end
  end
end
