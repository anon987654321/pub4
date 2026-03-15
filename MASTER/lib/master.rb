# frozen_string_literal: true

require "zeitwerk"

module Master
  ROOT = File.expand_path("..", __dir__).freeze

  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "autoloop"   => "AutoLoop",
    "cli"        => "CLI",
    "mcp_server" => "MCPServer",
    "git_context" => "GitContext",
    "ast_edit"    => "AstEdit",
    "llm"         => "LLM"
  )
  loader.setup

  # Build the full container without starting the CLI
  def self.build(root: Dir.pwd)
    config   = Config.new(root)
    config["model"] ||= default_model

    ring     = RingBuffer.new(1000)
    bus      = EventBus.new(log: ring)
    logging  = Logging.new(ring_buffer: ring, event_bus: bus, trace_level: config.trace)
    session  = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
    undo     = Undo.new(session:, event_bus: bus)
    breaker  = CircuitBreaker.new(budget_max: config.budget_max, req_max: config.req_max, event_bus: bus)
    cache    = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
    governor = Governor.new(config:, event_bus: bus)
    renderer = Renderer.new(config:)
    metrics  = Metrics.new(root:, event_bus: bus)

    memory      = Memory.new(root:)
    personality = Personality.new(config["persona"]&.to_sym || Personality::DEFAULT)

    tools    = build_tools(root:, undo:, governor:, bus:)
    router   = Routing::ModelRouter.new(config:)
    modes    = Reasoning::Modes.new
    agent    = Agent.new(config:, session:, tools:, circuit_breaker: breaker, cache:, event_bus: bus,
                         model_router: router, reasoning_modes: modes,
                         memory:, personality:)
    tools << Tools::AskLlm.new(agent:, governor:, circuit_breaker: breaker, cache:, event_bus: bus)

    guard        = Security::InjectionGuard.new
    scanner      = Scan::Scanner.new(event_bus: bus)
    scanner.add_rule(Scan::Rules::FrozenStringRule.new)
    scanner.add_rule(Scan::Rules::BareRescueRule.new)
    scanner.add_rule(Scan::Rules::ExplicitRule.new)
    scanner.add_rule(Scan::Rules::ImmutableRule.new)
    scanner.add_rule(Scan::Rules::CqsRule.new)
    scanner.add_rule(Scan::Rules::SelfExplainingRule.new)
    scanner.add_rule(Scan::Rules::LongMethodRule.new)
    scanner.add_rule(Scan::Rules::GodClassRule.new)
    scanner.add_rule(Scan::Rules::DuplicateCodeRule.new)
    scanner.add_rule(Scan::Rules::StrunkRule.new)
    scanner.add_rule(Scan::Rules::AxiomCoverageRule.new(root:))
    scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
    swarm        = Swarm::Coordinator.new(agent:, event_bus: bus)
    personas     = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
    deliberation = Council::Deliberation.new(personas:, agent:, event_bus: bus)
    council_stage = Stages::Council.new(deliberation:, config:)

    stages = [
      Stages::Intake.new,
      Stages::Infer.new,
      Stages::Route.new(
        commands: build_commands(session:, undo:, logging:, config:, renderer:, agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:),
        agent:
      ),
      Stages::Guard.new(governor:, injection_guard: guard),
      Stages::Execute.new,
      council_stage,
      Stages::Lint.new(scanner:, config:),
      Stages::Strunk.new,
      Stages::Memo.new(memory:),
      Stages::Render.new(renderer:)
    ]

    pipeline = Pipeline.new(stages)

    {
      config:, session:, agent:, renderer:, logging:, undo:, pipeline:,
      scanner:, bus:, breaker:, cache:, governor:, metrics:, council_stage:,
      memory:, personality:, swarm:, root:
    }
  end

  # Boot the CLI (wraps build)
  def self.boot(root: Dir.pwd, argv: [])
    container = build(root:)
    container[:renderer].tap { |r| puts r.banner(container[:agent].model) }
    CLI.new(container:)
  end

  def self.default_model
    if ENV["OPENROUTER_API_KEY"].to_s.length > 10
      "nvidia/nemotron-nano-12b-v2-vl:free"
    elsif ENV["ANTHROPIC_API_KEY"].to_s.length > 10
      "claude-sonnet-4-6"
    else
      "gpt-4o"
    end
  end

  def self.build_tools(root:, undo:, governor:, bus:)
    [
      Tools::ReadFile.new(root:, undo:, event_bus: bus),
      Tools::WriteFile.new(root:, undo:, governor:, event_bus: bus),
      Tools::StrReplace.new(root:, undo:, governor:, event_bus: bus),
      Tools::ListDir.new(root:, event_bus: bus),
      Tools::SearchFiles.new(root:, event_bus: bus),
      Tools::WebSearch.new(governor:, event_bus: bus),
      Tools::Zsh.new(root:, governor:, event_bus: bus),
      Tools::Replace.new(root:, governor:, event_bus: bus),
      Tools::GitContext.new(root:, event_bus: bus),
      Tools::AstEdit.new(root:, undo:, event_bus: bus)
    ]
  end

  def self.build_commands(session:, undo:, logging:, config:, renderer:, agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:)
    {
      "clear"   => ->(ctx) { session.clear!  ; "context cleared" },
      "save"    => ->(ctx) { session.save!   ; "session saved" },
      "tokens"  => ->(ctx) { "~#{session.token_est} tokens" },
      "undo"    => ->(ctx) { r = undo.undo! ; r.ok? ? "reverted: #{r.value!}" : r.message },
      "dmesg"   => ->(ctx) { logging.dmesg },
      "cost"    => ->(ctx) { "$#{"%.4f" % session.cost}" },
      "config"  => ->(ctx) { config.data.inspect },
      "model"   => ->(ctx) { "model: #{agent.model}" },
      "mode"    => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if Reasoning::Modes::SUPPORTED.include?(arg)
          config["reasoning_mode"] = arg
          config.save!
          "mode: #{arg}"
        else
          "mode: #{config.reasoning_mode} (supported: #{Reasoning::Modes::SUPPORTED.join(", ")})"
        end
      },
      "task"    => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if arg.empty?
          "task_type: #{config.task_type}"
        else
          config["task_type"] = arg
          config.save!
          "task_type: #{arg}"
        end
      },
      "autotest" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        case arg
        when "on"  then config["auto_testing"] = true;  config.save!; "autotest: on"
        when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
        else "autotest: #{config.auto_testing? ? "on" : "off"}"
        end
      },
      "council" => ->(ctx) {
        case ctx[:args].to_s.strip
        when "on"  then council_stage.enable!  ; "council: enabled"
        when "off" then council_stage.disable! ; "council: disabled"
        else "council: #{council_stage.instance_variable_get(:@enabled) ? "on" : "off"}"
        end
      },
      "swarm" => ->(ctx) {
        args = ctx[:args].to_s.strip.split(" ", 2)
        role, task = args[0]&.to_sym, args[1].to_s
        if role.nil? || task.empty?
          "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}"
        else
          r = swarm.dispatch(role, task: task, context_slice: {})
          r.ok? ? r.value!.inspect : r.message
        end
      },
      "autoloop" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        cycles = arg.match?(/^\d+$/) ? arg.to_i : 8
        loop_obj = AutoLoop.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
        output = []
        result = loop_obj.run(max_cycles: cycles) { |cycle, violations|
          output << "cycle #{cycle}: #{violations.size} violation(s)"
        }
        (output + [result.ok? ? result.value! : result.message]).join("\n")
      },
"explain" => ->(ctx) {
  map  = Introspection::SelfMap.new(root:)
  info = map.describe
  cov  = map.axiom_coverage
  cov_lines = cov.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
  stages = "Intake→Infer→Route→Guard→Execute→Council→Lint→Strunk→Memo→Render"
  "MASTER — #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov_lines}"
},
"persona" => ->(ctx) {
  arg   = ctx[:args].to_s.strip.to_sym
  names = Personality::PERSONAS.keys
  if names.include?(arg)
    config["persona"] = arg.to_s
    config.save!
    "persona: #{arg}"
  else
    "persona: #{config["persona"] || "dark_malay"} — available: #{names.join(", ")}"
  end
},
"sweep" => ->(ctx) {

        arg     = ctx[:args].to_s.strip
        target  = arg.empty? ? root : File.expand_path(arg, root)
        sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
        log     = []
        result  = sweeper.run(target) { |cycle, file, delta|
          log << "  cycle #{cycle}  #{file}  +#{delta}"
        }
        ([result.ok? ? result.value! : result.message] + log).join("\n")
      },
      "memory"  => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if arg.start_with?("forget ")
          key = arg.sub("forget ", "").strip
          memory.forget(key)
          "forgot: #{key}"
        elsif arg.start_with?("remember ")
          parts = arg.sub("remember ", "").split("=", 2)
          key, val = parts[0].strip, parts[1]&.strip
          val ? (memory.remember(key, val); "remembered: #{key}") : "usage: /memory remember key=value"
        elsif arg.empty?
          entries = memory.all
          entries.empty? ? "(no memories)" : entries.map { |k, v| "#{k}: #{v}" }.join("\n")
        else
          val = memory.recall(arg)
          val ? "#{arg}: #{val}" : "(not found: #{arg})"
        end
      },
      "help"    => ->(ctx) {
        cmds = %w[clear save tokens undo dmesg cost config model mode task autotest council autoloop swarm sweep memory help exit]
        cmds.map { "/#{_1}" }.join("  ")
      }
    }
  end
end
