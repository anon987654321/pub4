    module CoreBridge
      module_function

      def run(goal, root:, bus: nil, model: nil, model_id: nil, max_turns: 40, on_turn: nil, memory: nil,
              container: nil, risk: :low, mode: nil)
        workspace_root = workspace_root_for(root)
        transcript = []
        observer = build_turn_observer(transcript, root: workspace_root, bus:, on_turn:)

        memory ||= Master::Core::Memory.new(risk:)
        model ||= Master::Core::Model.new(**{ model_id:, chat: agent_chat(container, bus:) }.compact)
        requested_mode = mode ? Master::Operator::Mode.for(mode) : Master::Operator::Mode.for(risk)
        mission = start_mission(
          goal,
          root:,
          bus:,
          model: model_id || model,
          mode: requested_mode,
          risk:,
          intent: Master::CLI::IntentRouter.new.classify(goal),
        )
        seed_continuation(memory, mission.record)
        begin
          mission.transition!(
            :plan,
            plan: Master::Ground::ActivePlan.read(root) || "fold plan: constitutional turn loop",
          )
          operator_mode = Master::Operator::Mode.for(mission.record.dig("operator", "mode") || requested_mode)
          mode_spec = Master::Operator::Mode.spec(operator_mode)
          capabilities = Master::Operator::Mode.capabilities(operator_mode)
          bus&.publish(
            "operator:mode",
            mode: operator_mode,
            risk: mission.record.dig("operator", "risk") || mode_spec[:risk],
            model_tier: mode_spec[:model_tier],
            council_required: mode_spec[:council],
          )
          world = build_world(root: workspace_root, container:, capabilities:, network: network_client(container))
          mission.transition!(:execute)
          done = build_fold(root:, model:, memory:, world:, max_turns:, observer:, capabilities:).run(goal)
          mission.transition!(:verify, summary: continuation_summary(done))
          settle_mission(mission, done)

          { mission: mission.record, reason: done.reason, turns: done.turns, summary: done.summary,
            transcript:, risk: memory.proof.risk }
        rescue StandardError => e