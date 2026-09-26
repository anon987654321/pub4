# frozen_string_literal: true

require_relative "../ground/service_supervisor"

module Master
  # Builder and CLI boot orchestration for Master.*.
  module MasterBoot
    def start_constitution_drift(container)
      return unless ENV["MASTER_DRIFT"] == "1"

      thread = Thread.new do
        result = Ground::Orders::ConstitutionDrift.new(container:).call
        unless result.ok?
          container[:bus]&.publish("constitution_drift:error", error: result.message)
        end
      rescue StandardError => e
        container[:bus]&.publish("constitution_drift:error", error: e.message)
      end
      thread.report_on_exception = false
      thread
    end

    def bootstrap_container(root: Dir.pwd)
      prepare_runtime!
      init_ground(root:)
      container = Builder.build(root:)
      Runtime::Jit.apply!
      container[:native_inventory] = Runtime::NativeInventory.snapshot
      init_loop(root:, container:)
      start_constitution_drift(container)
      container
    end

    def init_ground(root:)
      Trace::Telemetry.bootstrap!(root:)
    end

    def init_loop(root:, container:)
      validate_data!(root:, bus: container[:bus])
      Ground::LawHandshake::Admission.enable!
      # After validation, so the first tick sees a container that finished
      # building rather than one mid-assembly. The tick is what persists, so
      # booting is also what restores continuity across restarts.
      container[:cognition] = Cognition::Mind.new(root:, bus: container[:bus], memory: container[:memory])
      container[:cognition].tick!
      Device::Agent.start!(root:, bus: container[:bus], cognition: container[:cognition],
                           standing: container[:standing])
      unless ENV["MASTER_DEVICE"] == "0"
        container[:device_perception] = Device::Perception.new(bus: container[:bus])
        container[:device_perception].start!
      end
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

    def emit_device_status
      return unless Device.android?

      # Without Termux:API every capability is unavailable for one reason, so
      # the boot says it once; /doctor device still lists each.
      lines = Device.status_lines
      lines = lines.first(2) unless Device.termux?
      lines.each { |line| warn(line) }
    rescue StandardError => e
      warn("device0: capability discovery failed — #{e.class}: #{e.message}")
    end

    # The first interactive boot on a host says what is present and what is
    # missing, each with its fix line; Device::Onboarding never raises.
    def onboard = Device::Onboarding.run!

    # A new phone gets the face's ear in the background, so the session
    # opens at once; Device::Setup says what it does as it goes.
    def set_up_device
      Device::Setup.start!
    rescue StandardError => e
      warn("ear0: setup did not start — #{e.class}: #{e.message}")
    end

    def boot(root: Dir.pwd)
      prepare_runtime!
      emit_device_status
      onboard
      set_up_device
      Ground::Pledge.stage1_boot!(root)
      service_ok = ensure_services!(root:)
      warn("master0: continuing in degraded presentation mode") unless service_ok
      container = bootstrap_container(root:)
      Ground::Pledge.stage2_lock!
      CLI::WebServer.start(container[:config]) unless ENV["MASTER_WEB"] == "0"
      CLI::BootBanner.print unless ENV["MASTER_FAST"] == "1"
      CLI::Session.new(container:)
    end
  end
end
