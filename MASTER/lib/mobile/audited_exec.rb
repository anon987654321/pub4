# frozen_string_literal: true

require "securerandom"
require_relative "../execution/contract"

module Master
  module Mobile
    # Runs `pkg install` under the effect lifecycle the Fold uses: a typed
    # envelope before and after, and no install when the before-event cannot
    # be published. The envelope carries a digest of the package list, never
    # the list itself.
    class AuditedExec
      Observation = Data.define(:ok, :detail) do
        def ok? = ok == true
        def message = detail.to_s
      end

      Effect = Data.define(:verb, :capability)
      PKG_INSTALL = Effect.new(verb: :exec, capability: :mobile_bootstrap)

      def initialize(observer: nil, run_id: SecureRandom.uuid, mission_id: nil,
                     runner: ->(argv) { system(*argv) })
        @observer = observer
        @run_id = run_id
        @mission_id = mission_id
        @runner = runner
        @lifecycle_failure = nil
      end

      def pkg_install!(packages)
        packages = Array(packages).map(&:to_s).reject(&:empty?).uniq
        return Observation.new(ok: true, detail: "nothing to install") if packages.empty?

        effect_id = SecureRandom.uuid
        scope = packages.sort.join("\0")
        notify(:before, effect_id:, scope:)
        return refused("before") if @lifecycle_failure

        observation, elapsed_ms = install(packages)
        notify(:after, effect_id:, scope:, observation:, elapsed_ms:)
        return refused("after", ran: true) if @lifecycle_failure && observation.ok?

        observation
      end

      private

      def install(packages)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ok = @runner.call(["pkg", "install", "-y", *packages]) ? true : false
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        verdict = ok ? "installed" : "pkg install failed"
        [Observation.new(ok:, detail: "#{verdict}: #{packages.join(', ')}"), elapsed_ms]
      end

      def refused(stage, ran: false)
        lead = ran ? "install ran but the after-event failed" : "not installed: the before-event failed"
        Observation.new(ok: false, detail: "#{lead} (#{@lifecycle_failure}) at #{stage}")
      end

      def notify(stage, effect_id:, scope:, observation: nil, elapsed_ms: nil)
        return unless @observer

        @observer.call(stage:, turn: 0, effect: PKG_INSTALL, effect_id:, operation: :perform,
                       run_id: @run_id, mission_id: @mission_id, scope:, observation:, elapsed_ms:)
      rescue StandardError => e
        @lifecycle_failure ||= "#{e.class}: #{e.message}"
      end
    end
  end
end
