# frozen_string_literal: true

require_relative "builder/infra_helpers"

module Master
  module Builder
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
      trace  = Plugins::Trace.boot(root:, config:)
      loop_c = Plugins::Loop.boot(root:, config:, bus: trace[:bus])
      reach  = Plugins::Reach.boot(root:, config:, bus: trace[:bus])
      ground = Plugins::Ground.boot(root:, config:, homeostat: loop_c[:homeostat])

      bus        = trace[:bus]
      renderer   = Voice::Renderer.new(config:)
      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      code_index.build_async
      bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }
      diag = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging])

      { config:, renderer:, code_index:, diag: }
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
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
      skills = Now::Skills.new(root:, event_bus: infra[:bus])
      skills.discover!
      Plugins::Loop.boot_autonomous(root:, infra:, agent:, scanner:, soul:)
                   .merge(learnings: infra[:learnings], skills:)
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
