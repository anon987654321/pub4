# frozen_string_literal: true

# Run using bin/ci — Rails 8.1 local CI (pub4 family apps)
require "rbconfig"
require_relative "../lib/pub4/ci_guard"

ENV["GIT_CEILING_DIRECTORIES"] ||= "/"
ENV["BUNDLER_AUDIT_UPDATE"] ||= "0"
ENV["NPM_CONFIG_CACHE"] ||= File.expand_path("~/.npm")
monorepo_rails = "/home/dev/pub4/RAILS"
ENV["PUB4_RAILS_ROOT"] ||= monorepo_rails if File.directory?(File.join(monorepo_rails, "shared"))

vps_host = ENV["PUB4_CI_GUARD"] == "1" || File.exist?("/var/db/pub4_vps") || File.exist?("/etc/relayd.conf")

Pub4::CiGuard.run! do
  CI.run do
    step "Setup", "bin/setup --skip-server"
    app = File.basename(Dir.getwd)
    css_builder = [
      ENV["PUB4_RAILS_ROOT"] && File.join(ENV["PUB4_RAILS_ROOT"], "tools", "build_all_css.rb"),
      "/home/dev/pub4/RAILS/tools/build_all_css.rb",
      File.expand_path("../..", __dir__) + "/tools/build_all_css.rb",
      File.expand_path("pub4-rails/RAILS/tools/build_all_css.rb", ENV["HOME"].to_s)
    ].compact.find { |candidate| File.readable?(candidate) }
    if css_builder
      step "Styles: pub4 CSS", "#{RbConfig.ruby} #{css_builder} --app #{app}"
    else
      step "Styles: pub4 CSS", "echo 'tools/build_all_css.rb not found in any known location -- skipping' >&2"
    end
    pub4_lib = ENV["PUB4_RAILS_ROOT"] && File.join(ENV["PUB4_RAILS_ROOT"], "shared/lib/pub4")
    pub4_lib ||= File.expand_path("../lib/pub4", __dir__)
    %w[
      rhythm_lint
      fallback_drift_lint
      empty_state_lint
      adhoc_empty_lint
      chrome_i18n_lint
      dialect_token_drift_check
    ].each do |lint|
      script = File.join(pub4_lib, "#{lint}.rb")
      label = lint.split("_").map(&:capitalize).join(" ")
      if File.readable?(script)
        step "Design: #{label}", "#{RbConfig.ruby} #{script}"
      else
        step "Design: #{label}", "echo '#{lint}.rb not found -- skipping' >&2"
      end
    end
    importmap_audit = %(bundle exec #{RbConfig.ruby} -e 'require "./config/environment"; require "importmap/commands"; Importmap::Commands.start(%w[audit])')
    step("Security: Importmap audit", importmap_audit) unless vps_host
    rubocop = 'bundle exec rubocop $(for d in app lib config db/migrate; do [ -d "$d" ] && printf "%s " "$d"; done)'
    step("Style: Ruby", rubocop) unless vps_host
    audit = ENV["BUNDLER_AUDIT_UPDATE"] == "1" ? "bundle exec bundler-audit check --update" : "bundle exec bundler-audit check"
    step "Security: Gem audit", audit
    step "Security: Brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
    step "Tests: DB prepare", "env RAILS_ENV=test bin/rails db:test:prepare"
    step "Tests: Rails", "bin/rails test"
    # System tests spin up a real headless-Chrome session -- too heavy for the
    # 1-vCPU VPS gate (see resource_guard.sh), but must run in local/dev CI.
    # This is also where axe-core accessibility checks live (see
    # test/application_system_test_case.rb's assert_accessible).
    step("Tests: System (a11y)", "bin/rails test:system") unless vps_host
    seed_env = vps_host ? "env RAILS_ENV=test SKIP_BERGEN_DEMO=1" : "env RAILS_ENV=test"
    step "Tests: Seeds", "#{seed_env} bin/rails db:seed:replant"
  end
end
