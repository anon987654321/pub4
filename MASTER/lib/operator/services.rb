# frozen_string_literal: true

require_relative "../core"
require_relative "../ground/pledge"

module Master
  module Operator
    # Named cognitive subsystems. Embedded services are observed here; only the
    # OS-backed web service has an independent rcctl control plane.
    SERVICES = %w[cognition mission model memory device voice web].freeze
    SYSTEM_SERVICE = { "web" => "master" }.freeze
    # One vocabulary for every service, provider and channel status: ready only when
    # something observed it working, configured when its prerequisites exist but
    # nothing has tried it, not_tested when nothing was measured. A reason follows a
    # colon. memory and device read "ready" from a literal before, which is the false
    # ready CAPABILITY_STATUS_MUST_BE_TRUTHFUL forbids.
    HEALTH = %w[ready configured degraded failed unavailable not_tested].freeze
    MODEL_CLIS = %w[claude codex grok gemini].freeze

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
        operator_modes: Master::Operator::Mode::SPECS.transform_values do |spec|
          {
            profile: spec[:profile],
            risk: spec[:risk],
            model_tier: spec[:model_tier],
            council: spec[:council],
            evidence: spec[:evidence],
          }
        end,
      }
    end

    def system_service(name)
      SYSTEM_SERVICE[name.to_s]
    end

    def state(name)
      case name.to_s
      when "cognition" then defined?(Master::Core::Fold) ? "ready" : "not_tested: the Fold is not loaded"
      when "mission" then mission_state
      when "model" then model_state
      when "memory", "device" then "not_tested: no probe"
      when "voice" then voice_state
      when "web" then rcctl_state("master")
      else "not_tested: unknown service"
      end
    rescue StandardError => e
      "failed: #{e.class}"
    end

    # Ready until speech or playback has failed in this process; the failure is the reason.
    def voice_state
      errors = [defined?(Master::Voice::Speech) && Master::Voice::Speech.last_error,
                defined?(Master::Voice::Playback) && Master::Voice::Playback.last_error]
      reason = errors.select { |error| error.is_a?(String) && !error.empty? }.first
      return "degraded: #{reason}" if reason

      ENV["MASTER_TTS_DEGRADED"] == "1" ? "degraded: MASTER_TTS_DEGRADED=1" : "ready"
    end

    def mission_state
      return "not_tested: missions are not loaded" unless defined?(Master::Fix::Mission)

      records = { "fold" => Master::ROOT, "fix" => Master::REPO_ROOT }
                .filter_map { |kind, at| (record = Master::Fix::Mission.current(root: at)) && [kind, record] }
      return "ready: no mission" if records.empty?
      return "failed: mission record has no state" if records.any? { |_, record| record["state"].to_s.empty? }

      "ready: #{records.map { |kind, record| "#{kind} mission #{record["state"]}" }.join(", ")}"
    rescue StandardError => e
      "failed: #{e.class}"
    end

    def model_state
      keys = ENV.values_at("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY").any? { |value| value.to_s != "" }
      clis = MODEL_CLIS.select { |cli| Master::Io::Exec.which(cli) }
      return "configured: #{[("API key" if keys), *clis].compact.join(", ")}" if keys || clis.any?

      "unavailable: no API key and no model CLI on PATH"
    end

    def rcctl_state(service)
      return "not_tested: no rcctl on this host" unless File.executable?("/usr/sbin/rcctl")

      _, _, status = Master::Io::Exec.capture3("/usr/sbin/rcctl", "check", service)
      status.success? ? "ready" : "unavailable: #{service} is stopped"
    rescue StandardError => e
      "failed: #{e.class}"
    end

    def run_rcctl(action, service)
      allowed = service == "master" && %w[stop restart].include?(action.to_s)
      raise SecurityError, "service action is not allowlisted" unless allowed

      broker = "/usr/local/sbin/pub4-admin"
      raise SecurityError, "pub4-admin is a symlink" if File.symlink?(broker)

      command = if File.executable?(broker)
                  ["doas", "-n", broker, "service", action.to_s, service]
                else
                  # Legacy hosts only; remove once the broker is installed everywhere.
                  ["doas", "-n", "/usr/sbin/rcctl", action.to_s, service]
                end
      out, status = Master::Io::Exec.capture2e(*command)
      status.success? ? out.strip : raise("service #{action} #{service} failed: #{out.strip}")
    end
  end
end
