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

    def self.boot_autonomous(root:, infra:, agent:, scanner:, soul:, axioms: nil)
      bus        = infra[:bus]
      standing   = Master::Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
      git        = Master::Reach::GitOperations.new(root)
      rules      = scanner.instance_variable_get(:@rules)
      learnings  = infra[:learnings]

      super_loop = Master::Loop::SuperLoop.new(
        rules:, axioms:, agent:, scanner:, root:, bus:, git:, learnings:
      )
      Thread.new { super_loop.run_forever(root) }.tap { |t| t.abort_on_exception = false }

      # Architecture #7: reactive file-watcher instead of polling.
      # Activate with MASTER_WATCH=1 on VPS (requires rb-kqueue or rb-inotify).
      watch_loop = if ENV["MASTER_WATCH"] == "1"
        wl = Master::Loop::WatchLoop.new(rules:, agent:, scanner:, root:, bus:, learnings:)
        Thread.new { wl.run }.tap { |t| t.abort_on_exception = false }
        wl
      end

      heartbeat = Master::Loop::Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory],
                                              event_bus: bus, homeostat: infra[:homeostat])
      triggers  = Master::Trace::Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!
      { standing:, super_loop:, watch_loop:, heartbeat:, triggers: }
    end

    Master::Plugin.register(:loop, self)
  end
  end
end
