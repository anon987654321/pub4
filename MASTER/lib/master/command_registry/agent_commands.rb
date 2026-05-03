# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def agent_commands(ai:, root:, infra:)
      scan_loop_commands(ai:, root:, infra:)
        .merge(model_agent_commands(ai:, root:, infra:))
        .merge(crit_command(ai:, root:))
    end

    def scan_loop_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      bus = infra[:bus]
      deliberation = ai[:deliberation]
      {
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          looper = AutoLoop.new(agent:, scanner:, root:, event_bus: bus)
          log = []
          result = looper.run(max_cycles: max) { |cycle, violations|
            log << "  cycle #{cycle}: #{violations.size} violation(s)"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus, code_index: infra[:code_index])
          log = []
          result = sweeper.run(target) { |cycle, file, delta|
            log << "  cycle #{cycle}  #{file}  +#{delta}"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "scan" => ->(ctx) {
          depth = ctx[:args].to_s.include?("deep") ? :deep : :standard
          raw_arg = ctx[:args].to_s.sub("deep", "").strip
          target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
          pairs = if target_arg && File.file?(target_arg)
            fr = scanner.scan(target_arg, depth:)
            [[target_arg, fr]]
          elsif target_arg && File.directory?(target_arg)
            dir_result = scanner.scan_dir(target_arg, depth:, glob: "**/*")
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          else
            dir_result = scanner.scan_dir(File.join(root, "lib"), depth:)
            next "scan failed" unless dir_result.ok?
            dir_result.value!
          end
          by_rule = Hash.new { |h, k| h[k] = [] }
          pairs.each do |_file, file_result|
            next unless file_result.respond_to?(:ok?) && file_result.ok?
            file_result.value!.each { |v| by_rule[v[:rule].to_s] << v }
          end
          total = by_rule.values.sum(&:size)
          next "clean -- no violations" if total.zero?
          lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
            ["[#{rule}] #{vs.size}"] +
              vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
          end
          lines << "#{total} total violations"
          lines.join("\n")
        }
      }
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
        "swarm"   => ->(ctx) { handle_swarm(swarm, ctx[:args].to_s.strip) },
        "explain" => ->(_ctx) { explain_master(root) }
      }
    end

    def handle_swarm(swarm, arg)
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
  end
end
