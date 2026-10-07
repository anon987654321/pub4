        workspace_root = workspace_root_for(root)
        transcript = []
        observer = build_turn_observer(transcript, root: workspace_root, bus:, on_turn:)

        memory ||= Master::Core::Memory.new(risk:)
        model ||= Master::Core::Model.new(**{ model_id:, chat: agent_chat(container, bus:) }.compact)
        requested_mode = mode ? Master::Operator::Mode.for(mode) : :repair
        mission = start_mission(
          goal,
          root:,