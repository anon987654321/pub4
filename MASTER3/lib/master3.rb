# frozen_string_literal: true

require "zeitwerk"

module Master3
  ROOT = File.expand_path("..", __dir__).freeze

  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "cli"          => "CLI",
    "mcp_server"   => "MCPServer"
  )
  loader.setup

  def self.boot(root: Dir.pwd, argv: [])
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

    tools    = build_tools(root:, undo:, governor:, bus:)
    agent    = Agent.new(config:, session:, tools:, circuit_breaker: breaker, cache:, event_bus: bus)

    guard      = Security::InjectionGuard.new
    scanner    = Scan::Scanner.new(event_bus: bus)
    personas   = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
    deliberation = Council::Deliberation.new(personas:, agent:, event_bus: bus)

    council_stage = Stages::Council.new(deliberation:)

    stages = [
      Stages::Intake.new,
      Stages::Route.new(
        commands: build_commands(session:, undo:, logging:, config:, renderer:, agent:, council_stage:),
        agent:
      ),
      Stages::Guard.new(governor:, injection_guard: guard),
      Stages::Execute.new,
      council_stage,
      Stages::Lint.new(scanner:),
      Stages::Strunk.new,
      Stages::Render.new(renderer:)
    ]

    pipeline  = Pipeline.new(stages)
    container = {
      config:, session:, agent:, renderer:, logging:, undo:, pipeline:,
      scanner:, bus:, breaker:, cache:, governor:, metrics:, council_stage:
    }

    puts renderer.banner(agent.model)
    CLI.new(container:)
  end

  def self.default_model
    if ENV["OPENROUTER_API_KEY"].to_s.length > 10
      "meta-llama/llama-3.3-70b-instruct:free"
    elsif ENV["ANTHROPIC_API_KEY"].to_s.length > 10
      "claude-opus-4-6"
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
      Tools::Zsh.new(root:, governor:, event_bus: bus)
    ]
  end

  def self.build_commands(session:, undo:, logging:, config:, renderer:, agent:, council_stage:)
    {
      "clear"   => ->(ctx) { session.clear!  ; "context cleared" },
      "save"    => ->(ctx) { session.save!   ; "session saved" },
      "tokens"  => ->(ctx) { "~#{session.token_est} tokens" },
      "undo"    => ->(ctx) { r = undo.undo! ; r.ok? ? "reverted: #{r.value!}" : r.message },
      "dmesg"   => ->(ctx) { logging.dmesg },
      "cost"    => ->(ctx) { "$#{"%.4f" % session.cost}" },
      "config"  => ->(ctx) { config.data.inspect },
      "model"   => ->(ctx) { "model: #{agent.model}" },
      "council" => ->(ctx) {
        case ctx[:args].to_s.strip
        when "on"  then council_stage.enable!  ; "council: enabled"
        when "off" then council_stage.disable! ; "council: disabled"
        else "council: #{council_stage.instance_variable_get(:@enabled) ? "on" : "off"}"
        end
      },
      "help"    => ->(ctx) {
        cmds = %w[clear save tokens undo dmesg cost config model council help exit]
        cmds.map { "/#{_1}" }.join("  ")
      }
    }
  end
end
