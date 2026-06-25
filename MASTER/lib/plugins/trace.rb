# frozen_string_literal: true

require "fileutils"
require_relative "../trace/hooks"

module Master
  module Plugins
    module Trace
      RING_SIZE = 1000

      def self.boot(root:, config:)
        event_log = Master::Trace::EventLog.new(root:)
        evidence_log = Master::Trace::EvidenceLog.new(root:)
        bus       = Master::Trace::EventBus.new(event_log:, evidence_log:)
        ring      = Master::Trace::RingBuffer.new(RING_SIZE)
        logging   = Master::Trace::Logging.new(ring_buffer: ring, event_bus: bus)
        session   = Master::Trace::Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
        undo      = Master::Trace::Undo.new(session:, event_bus: bus, root:)
        metrics   = Master::Trace::Metrics.new(root:, event_bus: bus)
        Master::Trace::AuditLog.new(root:, event_bus: bus)
        Master::Trace::SwallowLedger.new(event_bus: bus, root:).attach
        Master::Trace::Hooks.new(root: root, event_bus: bus, budget_max: config.budget_max).attach
        recorder  = Master::Trace::Recorder.new(root:, event_bus: bus)
        { event_log:, bus:, ring:, logging:, session:, undo:, metrics:, trace: recorder }
      end

      def self.boot_snapshot(container)
        Master::Builder.boot_snapshot(container)
      end

      Master::Plugin.register(:trace, self)
    end
  end
end