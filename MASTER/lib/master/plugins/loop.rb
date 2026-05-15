# frozen_string_literal: true

module Master
  module Plugins
  module Loop
    def self.boot(root:, config:, bus:)
      homeostat   = Master::Loop::Homeostat.new(event_bus: bus)
      governor    = Master::Loop::Governor.new(config:, event_bus: bus)
      diff_stager = config["staging_enabled"] ? Master::Loop::DiffStager.new(root:, event_bus: bus) : nil
      phase_gates = Master::Loop::PhaseGates.new(root:, event_bus: bus)
      { homeostat:, governor:, diff_stager:, phase_gates: }
    end

    def self.boot_autonomous(root:, infra:, agent:, scanner:, soul:)
      bus       = infra[:bus]
      standing  = Master::Ground::StandingOrders.new(pipeline: nil, event_bus: bus)
      autoloop  = Master::Loop::AutoLoop.new(agent:, scanner:, root:, event_bus: bus, soul:, learnings: infra[:learnings])
      git       = Master::Reach::GitOperations.new(root)
      super_loop = Master::Loop::SuperLoop.new(rules: scanner.instance_variable_get(:@rules),
                                               agent:, scanner:, root:, bus:, git:)
      Thread.new { super_loop.run_forever(root) }.tap { |t| t.abort_on_exception = false }
      heartbeat = Master::Loop::Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory],
                                              event_bus: bus, homeostat: infra[:homeostat])
      triggers  = Master::Loop::Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!
      { standing:, autoloop:, super_loop:, heartbeat:, triggers: }
    end

    Master::Plugin.register(:loop, self)
  end
  end
end
