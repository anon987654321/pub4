# frozen_string_literal: true

module Master
  module Plugins
  module Trace
    RING_SIZE = 1000

    def self.boot(root:, config:)
      event_log = Master::Runtime::EventLog.new(root:)
      bus       = Master::Trace::EventBus.new(event_log:)
      ring      = Master::Trace::RingBuffer.new(RING_SIZE)
      logging   = Master::Trace::Logging.new(ring_buffer: ring, event_bus: bus)
      session   = Master::Trace::Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
      undo      = Master::Trace::Undo.new(session:, event_bus: bus, root:)
      metrics   = Master::Trace::Metrics.new(root:, event_bus: bus)
      Master::Trace::AuditLog.new(root:, event_bus: bus)
      recorder  = Master::Trace::Recorder.new(root:, event_bus: bus)
      { event_log:, bus:, ring:, logging:, session:, undo:, metrics:, trace: recorder }
    end

    Master::Plugin.register(:trace, self)
  end
  end
end
