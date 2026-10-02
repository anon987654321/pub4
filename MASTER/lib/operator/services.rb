# frozen_string_literal: true

require_relative "../core/capabilities"
require_relative "../ground/pledge"

module Master
  module Operator
    # Named cognitive subsystems. Embedded services are observed here; only the
    # OS-backed web service has an independent rcctl control plane.
    SERVICES = %w[cognition mission model memory device voice web].freeze
    SYSTEM_SERVICE = { "web" => "master" }.freeze

    module_function

    def status(name = nil)
      names = name ? [name.to_s] : SERVICES
      names.to_h { |service| [service, state(service)] }
    end

    def stop(name)
      service = system_service(name)
      raise ArgumentError, "service #{name} is embedded; no independent stop operation" unless service

      run_rcctl("stop", service)
    end

    def restart(name)
      service = system_service(name)
      raise ArgumentError, "service #{name} is embedded; no independent restart operation" unless service

      run_rcctl("restart", service)
    end

    def security
      profile = Master::Core::Capabilities.for(:fix)
      {
        constitution: "active",
        capability_profile: profile.name,
        capabilities: profile.capabilities,
        monotonic_reduction: true,
        openbsd_pledge: Master::Ground::Pledge.openbsd?,
        transactional_fix: true,
        model_authority: "proposal-only",
      }
    end

    def system_service(name)
      SYSTEM_SERVICE[name.to_s]
    end

    def state(name)
      case name.to_s
      when "cognition" then defined?(Master::Core::Fold) ? "ready" : "unloaded"
      when "mission" then mission_state
      when "model" then model_state
      when "memory" then "ready"
      when "device" then "ready"
      when "voice" then ENV["MASTER_TTS_DEGRADED"] == "1" ? "degraded" : "ready"
      when "web" then rcctl_state("master")
      else "unknown"
      end
    rescue StandardError => e
      "unknown, #{e.class}"
    end

    def mission_state
      return "idle" unless defined?(Master::Fix::Mission)

      record = Master::Fix::Mission.current(root: Master::ROOT)
      return "idle" unless record

      record["state"].to_s.empty? ? "unknown" : record["state"].to_s
    rescue StandardError
      "unknown"
    end

    def model_state
      configured = ENV.values_at("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "REPLICATE_API_TOKEN").any? { |v| v.to_s != "" }
      configured ? "configured" : "local/degraded"
    end

    def rcctl_state(service)
      return "unmanaged" unless File.executable?("/usr/sbin/rcctl")

      _, _, status = Master::Io::Exec.capture3("/usr/sbin/rcctl", "check", service)
      status.success? ? "running" : "stopped"
    rescue StandardError => e
      "unknown, #{e.class}"
    end

    def run_rcctl(action, service)
      raise SecurityError, "service #{service} is not allowlisted" unless system_service(service)

      out, status = Master::Io::Exec.capture2e("doas", "-n", "/usr/sbin/rcctl", action.to_s, service)
      status.success? ? out.strip : raise("rcctl #{action} #{service} failed: #{out.strip}")
    end
  end
end
