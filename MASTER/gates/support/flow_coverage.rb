# frozen_string_literal: true

require_relative "gate_result"
require_relative "../../lib/gap"

module Deploy
  # What a flow gate says about an app it could not reach.
  #
  # user_flow and flow_journey used to file a closed port as one warning line and
  # carry on: the source checks had run, so the gate printed PASSED with every
  # live journey of the stopped apps unmeasured. A skipped app is now a named
  # outcome (skipped:app-down), listed once per app with the flows it took
  # down, and it makes the gate :inconclusive. GATE_SOURCE_ONLY=1 says the run
  # is source-only on purpose and restores the old reading.
  module FlowCoverage
    module_function

    def source_only?(env = ENV) = GateResult.flag?("GATE_SOURCE_ONLY", env)

    # FLOW_<APP>_PORT points one app's flows at a copy booted elsewhere (a worktree
    # on a spare port) without touching the ports the triangle owns.
    def port_for(app, default, env = ENV)
      override = env["FLOW_#{app.to_s.upcase}_PORT"].to_s
      override.match?(/\A\d+\z/) ? Integer(override) : default
    end

    # A journey marked mutates: true writes to the database behind the app. That is
    # a throwaway on a laptop and production on the deploy host (vps-deploy runs
    # flow_journey against the apps it just restarted), so it runs on the first and
    # not the second unless GATE_ALLOW_WRITES=1 says the copy is disposable.
    def writes_allowed?(env = ENV, vps: on_deploy_host?)
      return false if GateResult.flag?("GATE_NO_WRITES", env)

      GateResult.flag?("GATE_ALLOW_WRITES", env) || !vps
    end

    def on_deploy_host? = File.file?("/etc/relayd.conf") || ENV["DEPLOY_ASSUME_VPS"] == "1"

    # One call per app, after its flows were counted. flows: the ids not run.
    def record_app_down(result, gate:, app:, port:, flows:)
      listed = flows.empty? ? "" : " -- #{flows.join(', ')}"
      line = "#{gate}: #{app} skipped:app-down, port #{port} closed, #{flows.size} flow(s) not run#{listed}"
      return result.warn(line) if source_only?

      result.skipped_live(line)
      result.incomplete!(line, gap: Master::Gap::APP_DOWN)
    end

    # The apps a result says it could not reach, for the runner's one-line verdict
    # and for /fix, whose baseline otherwise sees only "inconclusive".
    def down_apps(result)
      Array(result.unchecked).filter_map { |reason| reason[/\A(?:user_flow|flow_journey): (\w+) skipped:app-down/, 1] }.uniq
    end

    # The per-app summary every flow gate prints: the outcome of each flow, grouped.
    def summary_line(gate, app, port, outcomes)
      tally = outcomes.values.tally
      parts = %i[passed failed inconclusive skipped].filter_map do |state|
        next unless tally[state]

        label = state == :skipped ? "skipped:app-down" : state.to_s
        "#{label}=#{tally[state]}"
      end
      "#{gate}: #{app} (port #{port}) #{parts.join(' ')}"
    end
  end
end
