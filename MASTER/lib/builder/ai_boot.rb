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
      council_stage = Now::Stages::Council.new(deliberation:, config: infra[:config], event_bus: bus)
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
      # Strict in build: always run self_test + require evidence (rules.yml ground_truth, self_apply)
      self_test = Judge::Scan::SelfTest.new(root: root, event_bus: bus).call
      bus&.publish("builder:self_test", ok: self_test.ok?) unless self_test.ok?
      { agent:, soul: soul_doc, scanner:, ecology:, swarm:, deliberation:, council_stage:, ideation:, guard:,
        reference_graph: infra[:reference_graph], agent_pool:, context_window: ctx, tools: }.merge(autonomous)
    end

    def build_scanner(root:, agent: nil, bus: nil, ecology: nil)
      Judge::Scan::RuleDSL
      wf = Master.load_yaml(File.join(root, "data", "workflow.yml")) rescue {}
      sleep_s = wf.dig("autoloop", "scan_file_sleep_s").to_f
      scanner = Judge::Scan::Scanner.new(event_bus: bus, file_sleep_s: sleep_s)
      Judge::Scan::Rule.registry.select(&:auto_build?).each { |k| scanner.add_rule(k.new) }
      scanner.add_rule(Judge::Scan::Rules::CoChangeCouplingRule.new(root:, ecology:))
      scanner.add_rule(Judge::Scan::Rules::RuleCoverageRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::InterconnectRule.new(root:))
      scanner.add_rule(Judge::Scan::Rules::SemanticRule.new(agent:))
      scanner.add_rule(Judge::Scan::Rules::AdversarialRule.new(agent:))
      scanner.add_rule(Judge::Scan::Rules::CommentDriftRule.new(agent:))
      scanner.add_rule(Judge::Scan::Rules::AstOmissionRule.new(root:))
      scanner
    end

    def boot_autonomous(root:, infra:, agent:, scanner:, axioms: nil)
      bus = infra[:bus]
      standing = Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
      git = Reach::GitOperations.new(root)
      rules = scanner.instance_variable_get(:@rules)
      learnings = infra[:learnings]
      rollback = Loop::Rollback.new(root:, bus:)

      # MASTER_AUTOFIX=1 enables in-process convergence; off by default to avoid autocommits racing deploys.
      fix_loop = Loop::FixLoop.new(rules:, axioms:, agent:, scanner:, root:, bus:, git:, learnings:, rollback:)
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
