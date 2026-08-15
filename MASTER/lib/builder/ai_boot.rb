# frozen_string_literal: true

module Master
  module Builder
    module_function

    def build_ai(root, infra)
      bus = infra[:bus]
      bundle = build_agent_bundle(root:, infra:, bus:)
      agent = bundle[:agent]
      tools = bundle[:tools]

      services = wire_agent_services(root:, infra:, agent:, tools:, bus:)
      scanner = services[:scanner]
      council = services[:council]
      autonomous = boot_autonomous(root:, infra:, agent:, scanner:, axioms: council[:axioms])
        .merge(learnings: infra[:learnings], skills: boot_skills(root, bus))
      finalize_ai_boot(bus:, root:, infra:, agent:, autonomous:, scanner:, lean_boot: services[:lean_boot])

      { agent:, soul: bundle[:soul], scanner:, ecology: infra[:ecology], swarm: services[:swarm],
        deliberation: council[:deliberation],
        ideation: council[:ideation], guard: services[:guard],
        reference_graph: infra[:reference_graph], agent_pool: bundle[:agent_pool],
        context_window: bundle[:context_window], tools: }.merge(autonomous)
    end

    def wire_agent_services(root:, infra:, agent:, tools:, bus:)
      Ground::ActivePlan.attach(bus, root)
      agent.wire_constitution(Ground::Constitution.new)
      scanner = build_scanner(root:, agent:, bus:, ecology: infra[:ecology])
      lean_boot = ENV["MASTER_FULL_BOOT"] != "1"
      swarm = lean_boot ? nil : Review::Swarm::Coordinator.new(agent:, event_bus: bus, parent_tools: tools)
      council = build_council(agent:, bus:, root:)
      # Permissive for user chat (CLI + web); strict guard remains in ToolContract for shell/git.
      guard = Review::Security::InjectionGuard.new(mode: :permissive)
      { scanner:, lean_boot:, swarm:, council:, guard: }
    end

    def finalize_ai_boot(bus:, root:, infra:, agent:, autonomous:, scanner:, lean_boot:)
      autonomous[:standing].wire_container(scanner:, agent:, root:, bus:)
      Trace::FeedbackLedger.new(event_bus: bus, learnings: autonomous[:learnings]).attach
      Trace::ReflexionLedger.new(event_bus: bus, root:).attach
      subscribe_graph_retriever(bus:, infra:, root:) unless lean_boot
      return if ENV["MASTER_SKIP_SELF_TEST"] == "1"

      publish_self_test(bus, Review::Scan::SelfTest.new(root:, event_bus: bus).call)
    end

    def build_agent_bundle(root:, infra:, bus:)
      tools = build_tools(root:, infra:) + infra[:mcp].tools
      deps = Review::Agent::Dependencies.from_kwargs(
        config: infra[:config], session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus,
        model_router: CLI::Routing::ModelRouter.new(config: infra[:config]),
        reasoning_modes: Review::Modes.new,
        memory: infra[:memory], personality: infra[:personality],
        code_index: infra[:code_index], homeostat: infra[:homeostat]
      )
      agent = Review::Agent.new(deps:)
      soul_doc = Voice::Soul.new(root:, agent:)
      tools << Io::AskLlm.new(agent:, governor: infra[:governor],
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus)
      ctx = CLI::ContextWindow.new(session: infra[:session], agent:, model_context: Master.context_window(agent.model),
        event_bus: bus, root:)
      ctx.check_and_compact!
      agent.wire_context_window(ctx)
      agent_pool = Review::AgentPool.new(governor: infra[:governor], tools:, event_bus: bus)
      { agent:, tools:, soul: soul_doc, context_window: ctx, agent_pool: }
    end

    def build_council(agent:, bus:, root:)
      personas = Review::Council::Personas.load(Master::COUNCIL_PATH)
      axioms = Ground::Rules.new(root:)
      deliberation = Review::Council::Deliberation.new(personas:, agent:, event_bus: bus, axioms:)
      ideation = Review::Council::Ideation.new(agent:, event_bus: bus)
      { axioms:, deliberation:, ideation: }
    end

    def subscribe_graph_retriever(bus:, infra:, root:)
      Review::GraphRetriever.new(reference_graph: infra[:reference_graph], root:).tap do |graph_retriever|
        bus.subscribe("tool:after") do |event|
          path = event[:path] || event["path"]
          next unless path

          neighbours = graph_retriever.neighbors([path])
          bus.publish("graph:neighbours", path:, neighbours:) unless neighbours.empty?
        end
      end
    end

    def publish_self_test(bus, self_test)
      if self_test.err?
        warn("builder: #{self_test.message}")
        bus&.publish("builder:self_test", ok: false, error: self_test.message)
      elsif !self_test.value!.ok?
        summary = self_test.value!
        bus&.publish("builder:self_test", ok: false, violations: summary.violation_count)
        if ENV["MASTER_STRICT_BOOT"] == "1"
          raise "builder: self_test failed with #{summary.violation_count} violation(s)"
        end
      end
    end

    def build_scanner(root:, agent: nil, bus: nil, ecology: nil)
      Review::Scan::InfraHelpers.build_scanner(root:, agent:, bus:, ecology:)
    end

    def boot_autonomous(root:, infra:, agent:, scanner:, axioms: nil)
      bus = infra[:bus]
      lean_boot = ENV["MASTER_FULL_BOOT"] != "1"
      core = build_autonomous_core(root:, infra:, agent:, scanner:, axioms:, bus:)
      monitors = build_autonomous_monitors(root:, infra:, agent:, scanner:, bus:, lean_boot:,
        fix_loop: core[:fix_loop], rollback: core[:rollback])
      core.merge(monitors)
    end

    def build_autonomous_core(root:, infra:, agent:, scanner:, axioms:, bus:)
      standing = Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
      git = Io::GitOperations.new(root)
      rules = scanner.instance_variable_get(:@rules)
      learnings = infra[:learnings]
      rollback = Fix::Rollback.new(root:, bus:)
      fix_loop = build_fix_loop(root:, infra:, agent:, scanner:, axioms:, rules:, learnings:, rollback:, bus:, git:)
      watch_loop = build_watch_loop(rules:, agent:, scanner:, root:, bus:, learnings:, fix_loop:)
      { standing:, git:, rollback:, fix_loop:, watch_loop: }
    end

    def build_autonomous_monitors(root:, infra:, agent:, scanner:, bus:, lean_boot:, fix_loop:, rollback:)
      heartbeat = Fix::Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory],
        event_bus: bus, homeostat: infra[:homeostat])
      triggers = Trace::Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!
      propose_tree = lean_boot ? nil : Fix::ProposeTree.new(root:, agent:, event_bus: bus)
      subscribe_fix_loop_events(bus:, propose_tree:, rollback:, fix_loop:, lean_boot:)
      watcher = build_watcher(bus:, root:)
      { heartbeat:, triggers:, propose_tree:, watcher: }
    end

    # MASTER_AUTOFIX=1 enables in-process convergence; off by default to avoid autocommits racing deploys.
    def build_fix_loop(root:, infra:, agent:, scanner:, axioms:, rules:, learnings:, rollback:, bus:, git:)
      fix_loop = Fix::FixLoop.new(
        rules:, axioms:, agent:, scanner:, root:, bus:, git:, learnings:, rollback:,
        incremental: ENV["MASTER_INCREMENTAL"] == "1",
        ground_truth: infra[:ground_truth], preserve_user_intent: infra[:preserve_user_intent],
        law_resolver: infra[:law_resolver], homeostat: infra[:homeostat]
      )
      start_fix_loop_background(fix_loop, root:, bus:) if ENV["MASTER_AUTOFIX"] == "1"
      fix_loop
    end

    # Pre-flight: refuse to start background self-mutation if MASTER's own
    # lib/ tree is already dirty by its own rules -- autofix compounding on
    # top of an existing violation is exactly the runaway-loop shape the
    # oscillation/cycle/plateau detectors exist to catch after the fact.
    def start_fix_loop_background(fix_loop, root:, bus:)
      report = Fix::SelfCheck.new(root:).gate!(bus:)
      unless report.clean?
        bus&.publish("fix_loop:background_refused", reason: "selfcheck dirty", total: report.total)
        return
      end
      fix_loop.start_background!(root)
    end

    # MASTER_WATCH=1 enables reactive file-watching (requires rb-kqueue or rb-inotify).
    def build_watch_loop(rules:, agent:, scanner:, root:, bus:, learnings:, fix_loop: nil)
      return unless ENV["MASTER_WATCH"] == "1"

      wl = Fix::WatchLoop.new(rules:, agent:, scanner:, root:, bus:, learnings:, fix_loop:)
      Thread.new { wl.run }.tap { |t| t.abort_on_exception = false }
      wl
    end

    def subscribe_fix_loop_events(bus:, propose_tree:, rollback:, fix_loop:, lean_boot:)
      unless lean_boot
        bus.subscribe("fix_loop:clean") { Thread.new { propose_tree.call } }
        bus.subscribe("fix_loop:plateau") { Thread.new { propose_tree.call } }
      end
      bus.subscribe("fix_loop:oscillation") { |payload| rollback.call(Master::Result.err("fix loop oscillation", category: :policy)) }
      bus.subscribe("fix_loop:cycle_detected") { |payload| rollback.call(Master::Result.err("fix loop cycle detected", category: :policy)) }
      bus.subscribe("system:crit") { Thread.new { fix_loop.stop_background! if fix_loop.background_alive? } }
      bus.subscribe("self_violation") { |payload| fix_loop.halt!(reason: "self_violation #{payload[:violations]} violations") }

      # Close the Homeostat loop for the fix_loop events PassRunner/
      # StagnationDetection/BackgroundRunner don't already observe directly
      # (they only see their own instance's state, not bus-level events).
      homeostat = fix_loop.instance_variable_get(:@homeostat)
      return unless homeostat

      bus.subscribe("fix_loop:llm_skipped") { homeostat.observe(:llm_failure) }
      bus.subscribe("fix_loop:timeout") { homeostat.observe(:llm_failure) }
    end

    # MASTER_WATCHER=0 disables the OpenBSD load watcher; on by default.
    def build_watcher(bus:, root:)
      watcher = Fix::Watcher.new(bus:, root:)
      if ENV["MASTER_WATCHER"] != "0"
        Thread.new { watcher.run_forever }.tap { |t| t.abort_on_exception = false }
      end
      watcher
    end

    def boot_skills(root, bus)
      skills = CLI::Skills.new(root:, event_bus: bus)
      skills.discover!
      skills
    end
  end
end
