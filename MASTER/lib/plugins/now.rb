# frozen_string_literal: true


module Master
  module Plugins
    module Now
      def self.build_pipeline(root, infra, ai)
        config   = infra[:config]
        bus      = infra[:bus]
        commands = Master::Now::CommandRegistry.build(infra:, ai:, root:)
        stages   = [
          Master::Now::Stages::Intake.new,
          Master::Now::Stages::Infer.new,
          Master::Now::Stages::Route.new(commands:, agent: ai[:agent]),
          Master::Now::Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
          Master::Now::Stages::Deliberate.new(agent: ai[:agent], config:),
          Master::Now::Stages::Execute.new,
          Master::Now::Pipeline::SkipOnPressure.new(Master::Now::Stages::Review.new(
            council: ai[:council_stage], scanner: ai[:scanner], config:, root:, event_bus: bus
          ), bus:),
          Master::Now::Stages::Memory.new(memory: infra[:memory], event_bus: bus),
          Master::Now::Stages::Render.new(renderer: infra[:renderer])
        ]
        pipeline = Master::Now::Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:, scanner: ai[:scanner])
        ai[:standing].wire_pipeline(pipeline)
        gateway = Master::Reach::Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
        commands["gateway"] = ->(ctx) { gateway.channels }
        [pipeline, gateway]
      end

      Master::Plugin.register(:now, self)
    end
  end
end
