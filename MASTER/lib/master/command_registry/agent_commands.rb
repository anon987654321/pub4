# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def agent_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      config = infra[:config]
      bus = infra[:bus]
      metrics = infra[:metrics]
      deliberation = ai[:deliberation]
      council_stage = ai[:council_stage]
      swarm = ai[:swarm]
      {
        "council" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then council_stage.enable!; "council: enabled"
          when "off" then council_stage.disable!; "council: disabled"
          else "council: #{council_stage.enabled? ? "on" : "off"}"
          end
        },
        "swarm" => ->(ctx) {
          args = ctx[:args].to_s.strip.split(" ", 2)
          role = args[0]&.to_sym
          task = args[1].to_s
          if role.nil? || task.empty?
            "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}"
          else
            result = swarm.dispatch(role, task:, context_slice: {})
            result.ok? ? result.value!.inspect : result.message
          end
        },
        "explain" => ->(_ctx) {
          map = Introspection::SelfMap.new(root:)
          info = map.describe
          coverage = map.axiom_coverage
          cov_lines = coverage.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
          stages = "Intake->Infer->Route->Guard->Execute->Council->Lint->Prune->Memo->Render"
          "MASTER -- #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov_lines}"
        },
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          looper = AutoLoop.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
          log = []
          result = looper.run(max_cycles: max) { |cycle, violations|
            log << "  cycle #{cycle}: #{violations.size} violation(s)"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
          log = []
          result = sweeper.run(target) { |cycle, file, delta|
            log << "  cycle #{cycle}  #{file}  +#{delta}"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "model" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "list"
            yml_path = File.join(root, "data", "models.yml")
            if File.exist?(yml_path)
              data = Master.load_yaml(yml_path)
              tiers = data["models"] || {}
              model_lines = tiers.flat_map { |tier, ms|
                ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" }
              }
              quality_lines = metrics&.model_quality&.map { |mod, stat|
                "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
              } || []
              sections = ["available models:"] + model_lines
              sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
              sections.join("\n")
            else
              "model: #{agent.model}"
            end
          elsif arg.empty?
            "model: #{agent.model}"
          else
            agent.model = arg
            config.save!
            "model: #{arg}"
          end
        },
        "why" => ->(ctx) {
          rule = ctx[:args].to_s.strip
          if rule.empty?
            "usage: /why <rule_name>"
          else
            prompt = "Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                     "give a before/after Ruby example, and state why it matters."
            agent.ask_once(prompt)
          end
        },
        "scan" => ->(ctx) {
          depth = ctx[:args].to_s.include?("deep") ? :deep : :standard
          target = File.join(root, "lib")
          result = scanner.scan_dir(target, depth:)
          next "scan failed" unless result.ok?
          by_rule = Hash.new { |h, k| h[k] = [] }
          result.value!.each do |_file, file_result|
            next unless file_result.ok?
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
  end
end
