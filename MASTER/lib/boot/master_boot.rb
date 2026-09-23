# frozen_string_literal: true

require_relative "../ground/service_supervisor"

module Master
  # Builder and CLI boot orchestration for Master.*.
  module MasterBoot
    def start_constitution_drift(container)
      return unless ENV["MASTER_DRIFT"] == "1"

      Thread.new do
        Ground::Orders::ConstitutionDrift.new(container:).call
      rescue StandardError => e
        warn("constitution_drift: #{e.message}")
      end
    end

    def bootstrap_container(root: Dir.pwd)
      prepare_runtime!
      init_ground(root:)
      container = Builder.build(root:)
      init_loop(root:, container:)
      start_constitution_drift(container)
      container
    end

    def init_ground(root:)
      Trace::Telemetry.bootstrap!(root:)
    end

    def init_loop(root:, container:)
      validate_data!(root:, bus: container[:bus])
      # After validation, so the first tick sees a container that finished
      # building rather than one mid-assembly. The tick is what persists, so
      # booting is also what restores continuity across restarts.
      container[:cognition] = Cognition::Mind.new(root:, bus: container[:bus], memory: container[:memory])
      container[:cognition].tick!
      container[:heartbeat]&.start!
    end

    def ensure_services!(root: ROOT)
      return true if ENV["MASTER_SKIP_TTS"] == "1"

      supervisor = Ground::ServiceSupervisor.new(root:)
      result = supervisor.ensure(
        name: "tts",
        start: -> { Voice::TtsSupervisor.ensure_daemon!(root:) },
        healthy: -> { Voice::Speech.edge_tts_ready? && Voice::TtsSupervisor.socket_alive?(Voice::TtsSupervisor.socket_path(root)) },
        max_restarts: 2,
        window_seconds: 300,
        wait_seconds: 5,
      )
      return true if result.ok? && result.value!.healthy?
      
      reason = result.ok? ? result.value!.message : result.message
      warn("tts0: degraded — #{reason}")
      false
    end

    def boot(root: Dir.pwd)
      return boot_fast(root:) if ENV["MASTER_FAST"] == "1"

      prepare_runtime!
      Ground::Pledge.stage1_boot!(root)
      service_ok = ensure_services!(root:)
      warn("master0: continuing in degraded presentation mode") unless service_ok
      container = bootstrap_container(root:)
      Ground::Pledge.stage2_lock!
      CLI::WebServer.start(container[:config])
      CLI::BootBanner.print
      CLI::Session.new(container:)
    end

    def boot_fast(root: Dir.pwd)
      prepare_runtime!
      CLI::Session.new(container: Builder.build_fast(root:))
    end
  end
end
