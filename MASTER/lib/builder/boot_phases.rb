# frozen_string_literal: true

module Master
  module Builder
    class TraceBoot
      def initialize(root:, config:)
        @root = root
        @config = config
      end

      def call
        event_log = Trace::EventLog.new(root: @root)
        evidence_log = Trace::EvidenceLog.new(root: @root)
        bus = Trace::EventBus.new(event_log: event_log, evidence_log: evidence_log)
        ring = Trace::RingBuffer.new(RING_SIZE)
        logging = Trace::Logging.new(ring_buffer: ring, event_bus: bus)
        session = Trace::Session.new(root: @root, budget_max: @config.budget_max, req_max: @config.req_max)
        undo = Trace::Undo.new(session: session, event_bus: bus, root: @root)
        metrics = Trace::Metrics.new(root: @root, event_bus: bus)
        Trace::AuditLog.new(root: @root, event_bus: bus)
        Trace::SwallowLedger.new(event_bus: bus, root: @root).attach
        recorder = Trace::Recorder.new(root: @root, event_bus: bus)
        { event_log: event_log, bus: bus, ring: ring, logging: logging, session: session, undo: undo, metrics: metrics, trace: recorder }
      end
    end

    class LoopBoot
      def initialize(root:, config:, bus:)
        @root = root
        @config = config
        @bus = bus
      end

      def call
        homeostat = Loop::Homeostat.new(event_bus: @bus)
        governor = Loop::Governor.new(config: @config, event_bus: @bus)
        diff_stager = @config["staging_enabled"] ? Loop::DiffStager.new(root: @root, event_bus: @bus) : nil
        phase_gates = Ground::PhaseGates.new(root: @root, event_bus: @bus)
        { homeostat: homeostat, governor: governor, diff_stager: diff_stager, phase_gates: phase_gates }
      end
    end

    class ReachBoot
      def initialize(root:, config:, bus:)
        @root = root
        @config = config
        @bus = bus
      end

      def call
        breaker = Reach::CircuitBreakerRegistry.new(
          budget_max: @config.budget_max,
          req_max: @config.req_max,
          warn_at: @config.warn_at,
          max_per_file: @config.max_per_file,
          event_bus: @bus
        )
        cache = Reach::SemanticCache.new(root: @root, ttl: @config["cache_ttl"], event_bus: @bus)
        mcp = Reach::McpCoordinator.new(root: @root, event_bus: @bus)
        mcp.connect_all
        { breaker: breaker, cache: cache, mcp: mcp }
      end
    end

    class GroundBoot
      def initialize(root:, config:, homeostat:)
        @root = root
        @config = config
        @homeostat = homeostat
      end

      def call
        memory = Ground::Memory.new(root: @root)
        personality = Voice::Personality.new(@config["persona"]&.to_sym || Voice::Personality::DEFAULT,
                                             root: @root, homeostat: @homeostat)
        learnings = Ground::KnowledgeStore.new(root: @root)
        ground_truth = Ground::GroundTruth.new(event_bus: nil)
        { memory: memory, personality: personality, learnings: learnings, ground_truth: ground_truth }
      end
    end
  end
end
