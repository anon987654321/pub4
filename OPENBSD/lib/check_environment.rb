# frozen_string_literal: true

require_relative "../lib/environment"
require_relative "../lib/ruby_runner"

module Deploy
  module CheckEnvironment
    Check = Struct.new(:name, :path, :args, :needs, :optional, keyword_init: true) do
      def initialize(name:, path:, args: [], needs: [], optional: false)
        super
      end
    end

    RAILS_CHECKS = "MASTER/checks/runner.rb"

    # The deploy-time integrity sequence, in order. This is not a registry of
    # RAILS checks -- that is MASTER/checks/checks.yml, and the rows below name a
    # check rather than a file so the two cannot drift. It used to point at
    # per-check scripts at the RAILS root; those were shims over the same classes
    # the runner already loads in-process.
    #
    # `needs` names only what skip_reason consults: :vps, :bundle and :browser.
    # Every check here needs the repo, so saying so decided nothing.
    INTEGRITY_CHECKS = [
      Check.new(name: "deploy_identity", path: "OPENBSD/checks/verify_deploy_identity.rb"),
      Check.new(name: "production", path: RAILS_CHECKS, args: %w[production]),
      Check.new(name: "phantom_fk", path: RAILS_CHECKS, args: %w[phantom_foreign_keys]),
      Check.new(name: "frontend", path: RAILS_CHECKS, args: %w[frontend_production]),
      Check.new(name: "relayd_smoke", path: "OPENBSD/checks/deploy_smoke_check.rb"),
      Check.new(name: "domain_align", path: RAILS_CHECKS, args: %w[domain_alignment]),
      Check.new(name: "crawl_inventory", path: "MASTER/tools/rails/crawl_probe.rb"),
      Check.new(name: "schema_migration", path: RAILS_CHECKS, args: %w[schema_migration]),
      Check.new(name: "asset_freshness", path: RAILS_CHECKS, args: %w[generated_asset]),
      Check.new(name: "human_walkthrough", path: RAILS_CHECKS, args: %w[human_walkthrough]),
      Check.new(name: "vps_health", path: "OPENBSD/checks/health_check.rb", args: ["--core"], needs: %i[vps]),
    ].freeze

    module_function

    def skip_reason(check, on_vps: Deploy::Environment.on_vps?)
      needs = Array(check.needs)
      if needs.include?(:vps) && !on_vps
        return "not on VPS"
      end
      if needs.include?(:bundle) && Deploy::RubyRunner.runtime_check_skipped?
        return Deploy::RubyRunner.runtime_skip_reason || "bundle runtime unavailable"
      end
      if needs.include?(:browser) && ENV["PROBE_REQUIRE_BROWSER"] != "1" && ENV["MASTER_CI_BROWSER"] != "1"
        return "browser probe optional"
      end

      nil
    end

    def post_pull_warning
      return unless Deploy::Environment.on_vps?

      <<~WARN
        integrity: note — source updated in /home/dev/pub4; deployed /home/<app>/app trees are unchanged.
        integrity: note — run: zsh OPENBSD/bin/vps-deploy <app>  (serial, one app at a time)
        integrity: note — then: ruby OPENBSD/checks/integrity_check.rb
      WARN
    end
  end
end
