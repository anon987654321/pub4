# frozen_string_literal: true

module Master
  module Plugins
    module Judge
      def self.configure(base, root: Dir.pwd, agent: nil, bus: nil, **_opts)
        Master::Judge::Scan::RuleDSL
        scanner = Master::Judge::Scan::Scanner.new(event_bus: bus)
        Master::Judge::Scan::Rule.registry.select(&:auto_build?).each { |k| scanner.add_rule(k.new) }
        scanner.add_rule(Master::Judge::Scan::Rules::RuleCoverageRule.new(root:))
        scanner.add_rule(Master::Judge::Scan::Rules::RubocopRule.new(root:))
        scanner.add_rule(Master::Judge::Scan::Rules::ReekRule.new(root:))
        scanner.add_rule(Master::Judge::Scan::Rules::InterconnectRule.new(root:))
        scanner.add_rule(Master::Judge::Scan::Rules::SemanticRule.new(agent:))
        scanner.add_rule(Master::Judge::Scan::Rules::AdversarialRule.new(agent:))
        scanner.add_rule(Master::Judge::Scan::Rules::CommentDriftRule.new(agent:))
        scanner.add_rule(Master::Judge::Scan::Rules::AstOmissionRule.new(root:))
        scanner
      end

      def self.build_ai(root, infra)
        bus          = infra[:bus]
        tools        = Plugins::Reach.build_tools(root:, infra:) + infra[:mcp].tools
        deps         = Master::Judge::Agent::Dependencies.from_kwargs(
          config: infra[:config], session: infra[:session], tools:,
          circuit_breaker: infra[:breaker], cache: infra[:cache], event_bus: bus,
          model_router: Master::Now::Routing::ModelRouter.new(
            config: infra[:config], provider_health: infra[:provider_health]
          ),
          reasoning_modes: Master::Judge::Modes.new,
          memory: infra[:memory], personality: infra[:personality],
          code_index: infra[:code_index], homeostat: infra[:homeostat]
        )
        agent        = Master::Judge::Agent.new(deps:)
        soul_doc     = Master::Voice::Soul.new(root:, agent:)
        tools << Master::Reach::AskLlm.new(agent:, governor: infra[:governor],
                                            circuit_breaker: infra[:breaker],
                                            cache: infra[:cache], event_bus: bus)
        ctx = Master::Now::ContextWindow.new(session: infra[:session], agent:,
          model_context: Master::CTX_WINDOW_SIZE, event_bus: bus, root:)
        ctx.check_and_compact!
        agent.wire_context_window(ctx)
        agent_pool = Master::Judge::AgentPool.new(governor: infra[:governor], tools:, event_bus: bus)
        Master::Ground::ActivePlan.attach(bus, root)
        agent.wire_constitution(Master::Ground::Constitution.new)
        scanner               = configure(nil, root:, agent:, bus:)
        swarm                 = Master::Judge::Swarm::Coordinator.new(agent:, event_bus: bus, parent_tools: tools)
        personas              = Master::Judge::Council::Personas.load(File.join(Master::ROOT, "data", "council.yml"))
        axioms                = Master::Ground::Rules.new(root:)
        deliberation          = Master::Judge::Council::Deliberation.new(personas:, agent:, event_bus: bus, axioms:)
        ideation              = Master::Judge::Council::Ideation.new(agent:, event_bus: bus)
        graph                 = Master::Ground::EvidenceGraph.new(Master::Ground::ClusterRegistry.new)
        council_stage         = Master::Now::Stages::Council.new(deliberation:, config: infra[:config], event_bus: bus, graph:)
        guard                 = Master::Judge::Security::InjectionGuard.new(mode: :permissive)
        autonomous = Plugins::Loop.boot_autonomous(root:, infra:, agent:, scanner:, soul: soul_doc)
                                 .merge(learnings: infra[:learnings], skills: boot_skills(root, bus))
        { agent:, soul: soul_doc, scanner:, swarm:, deliberation:, council_stage:, ideation:, guard:,
          agent_pool:, context_window: ctx, tools: }.merge(autonomous)
      end

      def self.boot_skills(root, bus)
        skills = Master::Now::Skills.new(root:, event_bus: bus)
        skills.discover!
        skills
      end

      Master::Plugin.register(:judge, self)
    end
  end
end
