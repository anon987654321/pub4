# frozen_string_literal: true

module Master
  module Builder
    module_function

    def build_ai(root, infra)
      bus = infra[:bus]
      tools = build_tools(root:, infra:) + infra[:mcp].tools
      deps = Judge::Agent::Dependencies.from_kwargs(
        config: infra[:config], session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus,
        model_router: Now::Routing::ModelRouter.new(config: infra[:config]),
        reasoning_modes: Judge::Modes.new,
        memory: infra[:memory], personality: infra[:personality],
        code_index: infra[:code_index], homeostat: infra[:homeostat]
      )
      agent = Judge::Agent.new(deps:)
      tools.each { |t| t.agent = agent if t.is_a?(Reach::Repligen) }
      soul_doc = Voice::Soul.new(root:, agent:)
      tools << Reach::AskLlm.new(agent:, governor: infra[:governor],
        circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus)
      ctx = Now::ContextWindow.new(session: infra[:session], agent:, model_context: Master::CTX_WINDOW_SIZE,
        event_bus: bus, root:)
      ctx.check_and_compact!
      agent.wire_context_window(ctx)
      agent_pool = Judge::AgentPool.new(governor: infra[:governor], tools:, event_bus: bus)
      Ground::ActivePlan.attach(bus, root)
      agent.wire_constitution(Ground::Constitution.new)
      ecology = infra[:ecology]
      scanner = build_scanner(root:, agent:, bus:, ecology:)
      swarm = Judge::Swarm::Coordinator.new(agent:, event_bus: bus, parent_tools: tools)
      personas = Judge::Council::Personas.load(File.join(Master::ROOT, "data", "council.yml"))
      axioms = Ground::Rules.new(root:)
      deliberation = Judge::Council::Deliberation.new(personas:, agent:, event_bus: bus, axioms:)
      ideation = Judge::Council::Ideation.new(agent:, event_bus: bus)
      council_stage = Now::Stages::Council.new(deliberation:, config: infra[:config], event_bus: bus,
                                               ground_truth: infra[:ground_truth])
      # Permissive for user chat (CLI + web); strict guard remains in ToolContract for shell/git.
      guard = Judge::Security::InjectionGuard.new(mode: :permissive)
      autonomous = boot_autonomous(root:, infra:, agent:, scanner:, axioms:)
        .merge(learnings: infra[:learnings], skills: boot_skills(root, bus))
      autonomous[:standing].wire_container(scanner:, agent:, root:, bus:)
      Trace::FeedbackLedger.new(event_bus: bus, learnings: autonomous[:learnings]).attach
      Trace::ReflexionLedger.new(event_bus: bus, root: root).attach
      Judge::GraphRetriever.new(reference_graph: infra[:reference_graph], root: root).tap do |graph_retriever|
        bus.subscribe("tool:after") do |event|
          path = event[:path] || event["path"]
          next unless path

          neighbours = graph_retriever.neighbors([path])
          bus.publish("graph:neighbours", path: path, neighbours: neighbours) unless neighbours.empty?
        end
      end
      unless ENV["MASTER_SKIP_SELF_TEST"] == "1"
        publish_self_test(bus, Judge::Scan::SelfTest.new(root: root, event_bus: bus).call)
      end
      { agent:, soul: soul_doc, scanner:, ecology:, swarm:, deliberation:, council_stage:, ideation:, guard:,
        reference_graph: infra[:reference_graph], agent_pool:, context_window: ctx, tools: }.merge(autonomous)
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
      Judge::Scan::InfraHelpers.build_scanner(root:, agent:, bus:, ecology:)
    end

    def boot_autonomous(root:, infra:, agent:, scanner:, axioms: nil)
      bus = infra[:bus]
      standing = Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
      git = Reach::GitOperations.new(root)
      rules = scanner.instance_variable_get(:@rules)
      learnings = infra[:learnings]
      rollback = Loop::Rollback.new(root:, bus:)

      # MASTER_AUTOFIX=1 enables in-process convergence; off by default to avoid autocommits racing deploys.
      fix_loop = Loop::FixLoop.new(
        rules:, axioms:, agent:, scanner:, root:, bus:, git:, learnings:, rollback:,
        incremental: ENV["MASTER_INCREMENTAL"] == "1",
        ground_truth: infra[:ground_truth], preserve_user_intent: infra[:preserve_user_intent],
        law_resolver: infra[:law_resolver]
      )
      fix_loop.start_background!(root) if ENV["MASTER_AUTOFIX"] == "1"

      # MASTER_WATCH=1 enables reactive file-watching (requires rb-kqueue or rb-inotify).
      watch_loop = if ENV["MASTER_WATCH"] == "1"
                     wl = Loop::WatchLoop.new(rules:, agent:, scanner:, root:, bus:, learnings:)
        Thread.new { wl.run }.tap { |t| t.abort_on_exception = false }
        wl
      end

      heartbeat = Loop::Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory],
        event_bus: bus, homeostat: infra[:homeostat])
      triggers = Trace::Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!

      propose_tree = Loop::ProposeTree.new(root:, agent:, event_bus: bus)
      bus.subscribe("fix_loop:clean") { Thread.new { propose_tree.call } }
      bus.subscribe("fix_loop:plateau") { Thread.new { propose_tree.call } }
      bus.subscribe("fix_loop:oscillation") { |payload| rollback.call(Master::Result.err("fix loop oscillation", category: :policy)) }
      bus.subscribe("fix_loop:cycle_detected") { |payload| rollback.call(Master::Result.err("fix loop cycle detected", category: :policy)) }

      # MASTER_WATCHER=0 disables the OpenBSD load watcher; on by default.
      watcher = Loop::Watcher.new(bus:, root:)
      if ENV["MASTER_WATCHER"] != "0"
        Thread.new { watcher.run_forever }.tap { |t| t.abort_on_exception = false }
      end
      bus.subscribe("system:crit") { Thread.new { fix_loop.stop_background! if fix_loop.background_alive? } }
      bus.subscribe("self_violation") { |payload| fix_loop.halt!(reason: "self_violation #{payload[:violations]} violations") }

      { standing:, fix_loop:, watch_loop:, heartbeat:, triggers:, propose_tree:, watcher:, git:, rollback: }
    end

    def boot_skills(root, bus)
      skills = Now::Skills.new(root:, event_bus: bus)
      skills.discover!
      skills
    end
  end
end
