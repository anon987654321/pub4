# frozen_string_literal: true

module Master
  # Builder — assembles the dependency container.
  # Three phases: infrastructure → AI stack → pipeline + gateway.
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
      config = Config.new(root)
      config["model"] ||= Master.default_model

      bus = EventBus.new
      ring = RingBuffer.new(RING_SIZE)
      logging = Logging.new(ring_buffer: ring, event_bus: bus, trace_level: config.trace)
      session = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
      undo = Undo.new(session:, event_bus: bus, root:)
      breaker = CircuitBreakerRegistry.new(
        budget_max: config.budget_max, req_max: config.req_max, event_bus: bus
      )
      cache = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
      governor = Governor.new(config:, event_bus: bus)
      renderer = Renderer.new(config:)
      metrics = Metrics.new(root:, event_bus: bus)
      AuditLog.new(root:, event_bus: bus)

      code_index = CodeIndex.new(root:, event_bus: bus)
      diff_stager = config["staging_enabled"] ? DiffStager.new(root:, event_bus: bus) : nil
      mcp = McpCoordinator.new(root:, event_bus: bus)
      mcp.connect_all
      code_index.build_async
      bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }

      memory = Memory.new(root:)
      personality = Personality.new(
        config["persona"]&.to_sym || Personality::DEFAULT, root:
      )

      {
        config:, ring:, bus:, logging:, session:, undo:, breaker:, cache:,
        governor:, renderer:, metrics:, code_index:, diff_stager:, mcp:,
        memory:, personality:
      }
    end

    def build_ai_stack(root, infra)
      config = infra[:config]
      bus = infra[:bus]

      tools = build_tools(root:, infra:)
      tools += infra[:mcp].tools
      router = Routing::ModelRouter.new(config:)
      modes = Reasoning::Modes.new
      agent = Agent.new(
        config:, session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache],
        event_bus: bus, model_router: router, reasoning_modes: modes,
        memory: infra[:memory], personality: infra[:personality],
        code_index: infra[:code_index]
      )
      soul_doc = Soul.new(root:, agent:)
      tools << Tools::AskLlm.new(
        agent:, governor: infra[:governor],
        circuit_breaker: infra[:breaker], cache: infra[:cache],
        event_bus: bus
      )

      ctx_window = ContextWindow.new(
        session: infra[:session], agent:, model_context: CTX_WINDOW_SIZE
      )
      ctx_window.check_and_compact!
      agent.wire_context_window(ctx_window)

      scanner = build_scanner(root:, agent:, bus:)
      swarm = Swarm::Coordinator.new(agent:, event_bus: bus)
      personas = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
      deliberation = Council::Deliberation.new(personas:, agent:, event_bus: bus)
      council_stage = Stages::Council.new(deliberation:, config:)

      standing = StandingOrders.new(pipeline: nil, event_bus: bus)
      autoloop = AutoLoop.new(agent:, scanner:, root:, event_bus: bus, soul: soul_doc)
      skills = Skills.new(root:, event_bus: bus)
      skills.discover!
      heartbeat = Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory], event_bus: bus)
      triggers = Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!

      {
        agent:, soul: soul_doc, scanner:, swarm:, deliberation:,
        council_stage:, standing:, autoloop:,
        guard: Security::InjectionGuard.new,
        heartbeat:, skills:, triggers:
      }
    end

    def build_pipeline_and_gateway(root, infra, ai)
      config = infra[:config]
      bus = infra[:bus]
      commands = CommandRegistry.build(infra:, ai:, root:)

      stages = [
        Stages::Intake.new,
        Stages::Infer.new,
        Stages::Route.new(commands:, agent: ai[:agent]),
        Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
        Stages::Execute.new,
        Pipeline::ParallelGroup.new(
          ai[:council_stage],
          Stages::Lint.new(scanner: ai[:scanner], config:, autoloop: ai[:autoloop])
        ),
        Stages::Prune.new,
        Stages::Memo.new(memory: infra[:memory], event_bus: bus),
        Stages::Render.new(renderer: infra[:renderer])
      ]

      pipeline = Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
      ai[:standing].wire_pipeline(pipeline)

      gateway = Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
      commands["gateway"] = ->(ctx) { gateway.channels }

      [pipeline, gateway]
    end

    def build_tools(root:, infra:)
      bus = infra[:bus]
      undo = infra[:undo]
      governor = infra[:governor]
      [
        Tools::ReadFile.new(root:, undo:, event_bus: bus),
        Tools::WriteFile.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::StrReplace.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::ListDir.new(root:, event_bus: bus),
        Tools::SearchFiles.new(root:, event_bus: bus),
        Tools::WebSearch.new(governor:, event_bus: bus),
        Tools::Shell.new(root:, governor:, event_bus: bus),
        Tools::BatchReplace.new(root:, governor:, event_bus: bus),
        Tools::GitContext.new(root:, event_bus: bus),
        Tools::AstEdit.new(root:, undo:, event_bus: bus),
        Tools::Tree.new(root:, event_bus: bus),
        Tools::SymbolLookup.new(code_index: infra[:code_index], event_bus: bus),
        Tools::Clean.new(root:, governor:, event_bus: bus),
        Tools::SearchKnowledge.new(root:, event_bus: bus)
      ]
    end

    def build_scanner(root:, agent:, bus:)
      scanner = Scan::Scanner.new(event_bus: bus)
      [
        Scan::Rules::FrozenStringRule, Scan::Rules::BareRescueRule,
        Scan::Rules::ExplicitRule, Scan::Rules::ImmutableRule,
        Scan::Rules::CqsRule, Scan::Rules::SelfExplainingRule,
        Scan::Rules::LongMethodRule, Scan::Rules::GodClassRule,
        Scan::Rules::DuplicateCodeRule, Scan::Rules::PruneRule,
        Scan::Rules::SrpRule, Scan::Rules::PolaRule,
        Scan::Rules::NielsenRule, Scan::Rules::AxiomCoverageRule
      ].each { |klass| scanner.add_rule(klass.new) }
      scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
      scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
      scanner
    end

    def boot_snapshot(container)
      root = container[:root]
      out = File.join(root, ".master", "snapshot.md")
      dirs = SNAPSHOT_DIRS.map { |d| File.join(root, d) }
      files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                  .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
                  .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                  .sort
      header = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      body = files.flat_map do |f|
        rel = f.sub("#{root}/", "")
        lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        content = File.read(f, encoding: "UTF-8", invalid: :replace)
        ["## #{rel}", "```#{lang}", content.rstrip, "```", ""]
      rescue StandardError
        []
      end
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, (header + body).join("\n"))
      container[:bus]&.publish("boot:snapshot", files: files.size)
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end
  end
end
