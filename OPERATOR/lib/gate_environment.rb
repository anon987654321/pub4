# frozen_string_literal: true

require_relative "../../MASTER/lib/pub4/environment"
require_relative "../../MASTER/lib/pub4/ruby_runner"

module Deploy
  module GateEnvironment
    Gate = Struct.new(:name, :path, :args, :needs, :optional, keyword_init: true) do
      def initialize(name:, path:, args: [], needs: [], optional: false)
        super
      end
    end

    INTEGRITY_GATES = [
      Gate.new(name: "deploy_identity", path: "OPERATOR/verify_deploy_identity.rb", needs: %i[repo]),
      Gate.new(name: "production", path: "RAILS/check_production_gate.rb", needs: %i[repo]),
      Gate.new(name: "phantom_fk", path: "RAILS/check_phantom_foreign_keys.rb", needs: %i[repo]),
      Gate.new(name: "frontend", path: "RAILS/frontend_production_gate.rb", needs: %i[repo]),
      Gate.new(name: "relayd_smoke", path: "OPENBSD/deploy_smoke_gate.rb", needs: %i[repo]),
      Gate.new(name: "domain_align", path: "RAILS/domain_alignment_gate.rb", needs: %i[repo]),
      Gate.new(name: "crawl_inventory", path: "RAILS/crawl_probe.rb", needs: %i[repo]),
      Gate.new(name: "schema_migration", path: "RAILS/schema_migration_gate.rb", needs: %i[repo]),
      Gate.new(name: "asset_freshness", path: "RAILS/generated_asset_freshness_gate.rb", needs: %i[repo]),
      Gate.new(name: "human_walkthrough", path: "RAILS/human_walkthrough_gate.rb", needs: %i[repo]),
      Gate.new(name: "vps_health", path: "OPENBSD/health_check.rb", args: ["--core"], needs: %i[vps live_http], optional: false),
    ].freeze

    module_function

    def skip_reason(gate)
      needs = Array(gate.needs)
      if needs.include?(:vps) && !Pub4::Environment.on_vps?
        return "not on VPS"
      end
      if needs.include?(:bundle) && Pub4::RubyRunner.runtime_gate_skipped?
        return Pub4::RubyRunner.runtime_skip_reason || "bundle runtime unavailable"
      end
      if needs.include?(:browser) && ENV["PROBE_REQUIRE_BROWSER"] != "1" && ENV["MASTER_CI_BROWSER"] != "1"
        return "browser probe optional"
      end

      nil
    end

    def post_pull_warning
      return unless Pub4::Environment.on_vps?

      <<~WARN
        integrity: note — source updated in /home/dev/pub4; deployed /home/<app>/app trees are unchanged.
        integrity: note — run: zsh OPENBSD/sh/vps_ci.sh <app>  (serial, one app at a time)
        integrity: note — then: ruby34 OPERATOR/integrity_gate.rb
      WARN
    end
  end
end