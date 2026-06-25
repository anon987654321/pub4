# frozen_string_literal: true

module Master
  module Plugins
    module Loop
      def self.boot(root:, config:, bus:)
        homeostat   = Master::Loop::Homeostat.new(event_bus: bus)
        governor    = Master::Loop::Governor.new(config:, event_bus: bus)
        diff_stager = config["staging_enabled"] ? Master::Loop::DiffStager.new(root:, event_bus: bus) : nil
        phase_gates = Master::Ground::PhaseGates.new(root:, event_bus: bus)
        { homeostat:, governor:, diff_stager:, phase_gates: }
      end

      def self.boot_autonomous(root:, infra:, agent:, scanner:, soul: nil, axioms: nil)
        bus = infra[:bus]
        standing = Master::Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
        git = Master::Reach::GitOperations.new(root)
        rules = scanner.instance_variable_get(:@rules)
        learnings = infra[:learnings]
        rollback = Master::Loop::Rollback.new(root:, bus:)

        fix_loop = Master::Loop::FixLoop.new(
          rules:, axioms:, agent:, scanner:, root:, bus:, git:, learnings:, rollback:,
          incremental: ENV["MASTER_INCREMENTAL"] == "1",
          ground_truth: infra[:ground_truth], preserve_user_intent: infra[:preserve_user_intent],
          law_resolver: infra[:law_resolver]
        )
        fix_loop.start_background!(root) if ENV["MASTER_AUTOFIX"] == "1"

        watch_loop = if ENV["MASTER_WATCH"] == "1"
                       wl = Master::Loop::WatchLoop.new(rules:, agent:, scanner:, root:, bus:, learnings:)
          Thread.new { wl.run }.tap { |t| t.abort_on_exception = false }
          wl
        end

        heartbeat = Master::Loop::Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory],
          event_bus: bus, homeostat: infra[:homeostat])
        triggers = Master::Trace::Triggers.new(event_bus: bus, scanner:, agent:)
        triggers.install_defaults!

        propose_tree = Master::Loop::ProposeTree.new(root:, agent:, event_bus: bus)
        bus.subscribe("fix_loop:clean") { Thread.new { propose_tree.call } }
        bus.subscribe("fix_loop:plateau") { Thread.new { propose_tree.call } }
        bus.subscribe("fix_loop:oscillation") { |_| rollback.call(Master::Result.err("fix loop oscillation", category: :policy)) }
        bus.subscribe("fix_loop:cycle_detected") { |_| rollback.call(Master::Result.err("fix loop cycle detected", category: :policy)) }

        watcher = Master::Loop::Watcher.new(bus:, root:)
        if ENV["MASTER_WATCHER"] != "0"
          Thread.new { watcher.run_forever }.tap { |t| t.abort_on_exception = false }
        end
        bus.subscribe("system:crit") { Thread.new { fix_loop.stop_background! if fix_loop.background_alive? } }
        bus.subscribe("self_violation") { |payload| fix_loop.halt!(reason: "self_violation #{payload[:violations]} violations") }

        { standing:, fix_loop:, watch_loop:, heartbeat:, triggers:, propose_tree:, watcher:, git:, rollback: }
      end

      Master::Plugin.register(:loop, self)
    end
  end
end