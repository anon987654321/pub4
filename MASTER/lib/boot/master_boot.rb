# frozen_string_literal: true

module Master
  # Builder and CLI boot orchestration for Master.*.
  module MasterBoot
    def build(root: Dir.pwd)
      ENV["MASTER_SCAN_ONLY"] == "1" ? Builder.build_scan_only(root:) : Builder.build(root:)
    end

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
      Io::GitHooks.ensure_pre_commit!(root:)
    end

    def init_loop(root:, container:)
      validate_data!(root:, bus: container[:bus])
      Builder.boot_snapshot(container)
      # After boot_snapshot, so the first tick sees a container that finished
      # building rather than one mid-assembly. The tick is what persists, so
      # booting is also what restores continuity across restarts.
      container[:cognition] = Cognition::Mind.new(root:, bus: container[:bus], memory: container[:memory])
      container[:cognition].tick!
      container[:heartbeat]&.start!
    end

    def ensure_services!(root: ROOT)
      Voice::TtsSupervisor.ensure_daemon!(root:) unless ENV["MASTER_SKIP_TTS"] == "1"
    end

    def boot(root: Dir.pwd)
      return boot_fast(root:) if ENV["MASTER_FAST"] == "1"

      prepare_runtime!
      Ground::Pledge.stage1_boot!(root)
      ensure_services!(root:)
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
