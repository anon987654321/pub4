# frozen_string_literal: true

require_relative "../../MASTER/lib/operator/environment"
require_relative "../../MASTER/lib/operator/ruby_runner"

module Deploy
  module GateEnvironment
    Gate = Struct.new(:name, :path, :args, :needs, :optional, keyword_init: true) do
      def initialize(name:, path:, args: [], needs: [], optional: false)
        super
      end
    end

    RAILS_GATES = "MASTER/gates/runner.rb"

    # The deploy-time integrity sequence, in order. This is not a registry of
    # RAILS gates -- that is MASTER/gates/gates.yml, and the rows below name a
    # gate rather than a file so the two cannot drift. It used to point at
    # per-gate scripts at the RAILS root; those were shims over the same classes
    # the runner already loads in-process.
    #
    # `needs` names only what skip_reason consults: :vps, :bundle and :browser.
    # Every gate here needs the repo, so saying so decided nothing.
    INTEGRITY_GATES = [
      Gate.new(name: "deploy_identity", path: "OPENBSD/gates/verify_deploy_identity.rb"),
      Gate.new(name: "production", path: RAILS_GATES, args: %w[production]),
      Gate.new(name: "phantom_fk", path: RAILS_GATES, args: %w[phantom_foreign_keys]),
      Gate.new(name: "frontend", path: RAILS_GATES, args: %w[frontend_production]),
      Gate.new(name: "relayd_smoke", path: "OPENBSD/gates/deploy_smoke_gate.rb"),
      Gate.new(name: "domain_align", path: RAILS_GATES, args: %w[domain_alignment]),
      Gate.new(name: "crawl_inventory", path: "RAILS/tools/crawl_probe.rb"),
      Gate.new(name: "schema_migration", path: RAILS_GATES, args: %w[schema_migration]),
      Gate.new(name: "asset_freshness", path: RAILS_GATES, args: %w[generated_asset]),
      Gate.new(name: "human_walkthrough", path: RAILS_GATES, args: %w[human_walkthrough]),
      Gate.new(name: "vps_health", path: "OPENBSD/gates/health_check.rb", args: ["--core"], needs: %i[vps]),
    ].freeze

    module_function

    def skip_reason(gate, on_vps: Operator::Environment.on_vps?)
      needs = Array(gate.needs)
      if needs.include?(:vps) && !on_vps
        return "not on VPS"
      end
      if needs.include?(:bundle) && Operator::RubyRunner.runtime_gate_skipped?
        return Operator::RubyRunner.runtime_skip_reason || "bundle runtime unavailable"
      end
      if needs.include?(:browser) && ENV["PROBE_REQUIRE_BROWSER"] != "1" && ENV["MASTER_CI_BROWSER"] != "1"
        return "browser probe optional"
      end

      nil
    end

    def post_pull_warning
      return unless Operator::Environment.on_vps?

      <<~WARN
        integrity: note — source updated in /home/dev/pub4; deployed /home/<app>/app trees are unchanged.
        integrity: note — run: zsh OPENBSD/bin/vps-deploy <app>  (serial, one app at a time)
        integrity: note — then: ruby34 OPENBSD/gates/integrity_gate.rb
      WARN
    end
  end
end
