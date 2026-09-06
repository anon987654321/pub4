# frozen_string_literal: true

require_relative "../trace/write_tracker"

module Master
  module Builder
    class TraceBoot
      def initialize(root:, config:)
        @root = root
        @config = config
      end

      def call
        event_log = Trace::Log::Event.new(root: @root)
        evidence_log = Trace::Log::Evidence.new(root: @root)
        bus = Trace::EventBus.new(event_log:, evidence_log:)
        Ground::Swallow.event_bus = bus
        ring = Trace::RingBuffer.new(RING_SIZE)
        logging = Trace::Logging.new(ring_buffer: ring, event_bus: bus)
        session = Trace::Session.new(root: @root, budget_max: @config.budget_max, req_max: @config.req_max)
        undo = Trace::Undo.new(session:, event_bus: bus, root: @root)
        metrics = Trace::Metrics.new(root: @root, event_bus: bus)
        Trace::Log::Audit.new(root: @root, event_bus: bus)
        Trace::Ledger::Swallow.new(event_bus: bus, root: @root).attach
        # soul.yml declares seven hooks and this is what fires them: it turns
        # five bus events the tree already publishes into the on_* names the
        # constitution uses, then runs what soul.yml declared for each. It was
        # written, and never attached — so on_violation_found was dead on a bus
        # carrying scan:complete, and .constitutional_violations.jsonl, which
        # the constitution says a violation is appended to, was never written.
        Trace::Hooks.new(root: @root, event_bus: bus, budget_max: @config.budget_max).attach
        recorder = Trace::Recorder.new(root: @root, event_bus: bus)
        write_tracker = Trace::WriteTracker.new(event_bus: bus)
        Trace::WriteTracker.current = write_tracker
        { event_log:, bus:, ring:, logging:, session:, undo:, metrics:, trace: recorder,
          write_tracker: }
      end
    end

    class LoopBoot
      def initialize(root:, config:, bus:)
        @root = root
        @config = config
        @bus = bus
      end

      def call
        homeostat = Fix::Homeostat.new(event_bus: @bus)
        governor = Fix::Governor.new(config: @config, event_bus: @bus)
        diff_stager = @config["staging_enabled"] ? Fix::DiffStager.new(root: @root, event_bus: @bus) : nil
        phase_gates = Ground::PhaseGates.new(root: @root, event_bus: @bus)
        { homeostat:, governor:, diff_stager:, phase_gates: }
      end
    end

    class ReachBoot
      def initialize(root:, config:, bus:)
        @root = root
        @config = config
        @bus = bus
      end

      def call
        breaker = Io::CircuitBreakerRegistry.new(
          budget_max: @config.budget_max,
          req_max: @config.req_max,
          warn_at: @config.warn_at,
          max_per_file: @config.max_per_file,
          event_bus: @bus,
        )
        cache = Io::SemanticCache.new(root: @root, ttl: @config["cache_ttl"], event_bus: @bus)
        mcp = Io::McpCoordinator.new(root: @root, event_bus: @bus)
        mcp.connect_all
        { breaker:, cache:, mcp: }
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
        library_verify = Ground::LibraryVerify.new(root: @root)
        law_resolver = Ground::LawResolver.new
        preserve_user_intent = Ground::PreserveUserIntent.new(root: @root)
        failure_taxonomy = Ground::FailureTaxonomy.new
        { memory:, personality:, learnings:,
          ground_truth:, library_verify:, law_resolver:,
          preserve_user_intent:, failure_taxonomy: }
      end
    end
  end
end
