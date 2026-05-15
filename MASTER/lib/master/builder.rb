# frozen_string_literal: true

require_relative "builder/infra_helpers"

module Master
  module Builder
    RING_SIZE = 1000
    SNAPSHOT_MAX_BYTES = 50_000
    SNAPSHOT_DIRS = %w[exe lib/master data].freeze

    module_function

    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = build_ai_stack(root, infra)
      pipeline, gateway = build_pipeline_and_gateway(root, infra, ai)
      infra.merge(ai).merge(pipeline:, gateway:, root:)
    end

    def build_infrastructure(root)
      config = Ground::Config.new(root)
      config["model"] ||= Master.default_model

      event_log = Runtime::EventLog.new(root:)
      bus = Trace::EventBus.new(event_log:)
      ring = Trace::RingBuffer.new(RING_SIZE)
      logging = Trace::Logging.new(ring_buffer: ring, event_bus: bus)
      homeostat = Loop::Homeostat.new(event_bus: bus)
      session = Trace::Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
      undo = Trace::Undo.new(session:, event_bus: bus, root:)
      breaker = Reach::CircuitBreakerRegistry.new(
        budget_max: config.budget_max, req_max: config.req_max, event_bus: bus
      )
      cache = Reach::SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
      governor = Loop::Governor.new(config:, event_bus: bus)
      renderer = Voice::Renderer.new(config:)
      metrics = Trace::Metrics.new(root:, event_bus: bus)
      Trace::AuditLog.new(root:, event_bus: bus)

      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      diff_stager = config["staging_enabled"] ? Loop::DiffStager.new(root:, event_bus: bus) : nil
      mcp = Reach::McpCoordinator.new(root:, event_bus: bus)
      mcp.connect_all
      code_index.build_async
      bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }

      memory = Ground::Memory.new(root:)
      personality = Voice::Personality.new(
        config["persona"]&.to_sym || Voice::Personality::DEFAULT, root:, homeostat:
      )
      learnings   = Ground::Learnings.new(root:)

      phase_gates = Loop::PhaseGates.new(root:, event_bus: bus)
      diag        = Trace::Diag.new(homeostat:, breaker:, logging:)
      trace       = Trace::Recorder.new(root:, event_bus: bus)
      {
        config:, event_log:, ring:, bus:, logging:, homeostat:, session:, undo:, breaker:, cache:,
        governor:, renderer:, metrics:, code_index:, diff_stager:, mcp:,
        memory:, personality:, phase_gates:, learnings:, diag:, trace:
      }
    end

    def build_ai_stack(root, infra)
      agent, soul_doc, scanner, swarm, deliberation, council_stage, ideation = build_agent_core(root, infra)
      autonomous = build_autonomous(root, infra, agent:, scanner:, soul: soul_doc)
      {
        agent:, soul: soul_doc, scanner:, swarm:, deliberation:, council_stage:, ideation:,
        guard: Judge::Security::InjectionGuard.new
      }.merge(autonomous)
    end

    def build_agent_core(root, infra)
      bus          = infra[:bus]
      agent, tools = build_agent_instance(root, infra)
      soul_doc     = Voice::Soul.new(root:, agent:)
      tools << Reach::AskLlm.new(agent:, governor: infra[:governor],
                                  circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus)
      ctx = Now::ContextWindow.new(session: infra[:session], agent:, model_context: CTX_WINDOW_SIZE)
      ctx.check_and_compact!
      agent.wire_context_window(ctx)
      constitution = Ground::Constitution.new
      agent.wire_constitution(constitution)
      scanner               = Plugins::Judge.configure(self, root:, agent:, bus:)
      swarm                 = Judge::Swarm::Coordinator.new(agent:, event_bus: bus)
      deliberation, council, ideation = build_council(root, infra, agent:)
      [agent, soul_doc, scanner, swarm, deliberation, council, ideation]
    end

    def build_council(root, infra, agent:)
      personas     = Judge::Council::Personas.load(File.join(ROOT, "data", "council.yml"))
      axioms       = Ground::Rules.new(root:)
      deliberation = Judge::Council::Deliberation.new(personas:, agent:, event_bus: infra[:bus], axioms:)
      ideation     = Judge::Council::Ideation.new(agent:, event_bus: infra[:bus])
      [deliberation, Now::Stages::Council.new(deliberation:, config: infra[:config], event_bus: infra[:bus]), ideation]
    end

    def build_agent_instance(root, infra)
      tools = Plugins::Reach.build_tools(root:, infra:) + infra[:mcp].tools
      deps  = Judge::Agent::Dependencies.from_kwargs(
        config: infra[:config], session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: infra[:bus],
        model_router: Now::Routing::ModelRouter.new(config: infra[:config]),
        reasoning_modes: Judge::Reasoning::Modes.new,
        memory: infra[:memory], personality: infra[:personality],
        code_index: infra[:code_index], homeostat: infra[:homeostat]
      )
      [Judge::Agent.new(deps:), tools]
    end

    def build_autonomous(root, infra, agent:, scanner:, soul:)
      bus       = infra[:bus]
      standing  = Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
      learnings = infra[:learnings]
      autoloop  = Loop::AutoLoop.new(agent:, scanner:, root:, event_bus: bus, soul:, learnings:)
      rules     = scanner.instance_variable_get(:@rules)
      git       = Reach::GitOperations.new(root)
      super_loop = Loop::SuperLoop.new(rules:, agent:, scanner:, root:, bus:, git:)
      Thread.new { super_loop.run_forever(root) }.tap { |t| t.abort_on_exception = false }
      skills    = Now::Skills.new(root:, event_bus: bus)
      skills.discover!
      heartbeat = Loop::Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory], event_bus: bus,
                               homeostat: infra[:homeostat])
      triggers  = Loop::Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!
      { standing:, learnings:, autoloop:, super_loop:, skills:, heartbeat:, triggers: }
    end

    def build_pipeline_and_gateway(root, infra, ai)
      config   = infra[:config]
      bus      = infra[:bus]
      commands = Now::CommandRegistry.build(infra:, ai:, root:)
      stages   = build_stages(root:, infra:, ai:, commands:)
      pipeline = Now::Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
      ai[:standing].wire_pipeline(pipeline)
      gateway = Reach::Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
      commands["gateway"] = ->(ctx) { gateway.channels }
      [pipeline, gateway]
    end

    def build_stages(root:, infra:, ai:, commands:)
      config = infra[:config]
      bus    = infra[:bus]
      [
        Now::Stages::Intake.new,
        Now::Stages::Infer.new,
        Now::Stages::Route.new(commands:, agent: ai[:agent]),
        Now::Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
        Now::Stages::Deliberate.new(agent: ai[:agent], config:),
        Now::Stages::Execute.new,
        Now::Pipeline::SkipOnPressure.new(Now::Pipeline::ParallelGroup.new(
          ai[:council_stage],
          Now::Stages::Lint.new(scanner: ai[:scanner], config:, autoloop: ai[:autoloop], root:, event_bus: bus),
          bus:
        ), bus:),
        Now::Pipeline::SkipOnPressure.new(Now::Stages::Prune.new, bus:),
        Now::Stages::Memo.new(memory: infra[:memory], event_bus: bus),
        Now::Stages::Render.new(renderer: infra[:renderer])
      ]
    end

  end
end
