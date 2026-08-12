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
    # On vm23 the tree is already /home/<app>/app. bin/setup's db:prepare
    # loads development configs against that tree and dies (nil configurations).
    # Test DB has its own step below; production is migrated after CI.
    if vps_host
      step "Setup", "echo 'vps: skip bin/setup'"
    else
      step "Setup", "bin/setup --skip-server"
    end
    app = ENV["PUB4_CI_APP"].to_s
    app = File.basename(Dir.getwd) if app.empty?
    # cwd is /home/brgen/app on the VPS, so basename is "app" and --app app
    # looks for RAILS/app, which is not a Rails app and has no ../shared gem.
    app = File.basename(File.expand_path("..")) if app == "app"
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
    # bin/rails test globs test/**/*_test.rb from the app root, so the mountable
    # verticals under engines/*/test were invisible to it and to this step. They
    # went unrun from the extraction onward: 29 tests, four of which had rotted
    # into NameErrors on the pre-split marketplace_checkout_path helper while CI
    # stayed green. DEFAULT_TEST/DEFAULT_TEST_EXCLUDE are the runner's supported
    # overrides (rails/test_unit/runner.rb); both must be set together, since
    # widening the glob without widening the exclude would sweep in an engine's
    # test/system or test/dummy.
    #
    # Setting them here fixed the gate and left `bin/rails test` narrow, so the
    # two commands disagreed about what the suite is and the local one was the
    # weaker. That bit a second time on 2026-08-10: a validation-i18n change
    # broke two takeaway engine tests, three sessions reported brgen green from
    # the narrow command — 349 runs against this step's 381 — and the VPS gate
    # was the only thing that caught it, at the cost of a blocked deploy.
    #
    # brgen sets the same two values in config/application.rb now (9506d1db6),
    # so the local command matches this one, and RAILS/test/test_scope_parity_test.rb
    # fails if they drift apart. Change the globs here and that test will tell
    # you which app to update. This comment is a pointer, not a warning to keep
    # in mind — the keeping-in-mind is what failed twice.
    if Dir.glob("engines/*/test/**/*_test.rb").any?
      test_glob = "{test,engines/*/test}/**/*_test.rb"
      test_exclude = "{test,engines/*/test}/{system,dummy,fixtures}/**/*_test.rb"
      step "Tests: Rails", "env DEFAULT_TEST='#{test_glob}' DEFAULT_TEST_EXCLUDE='#{test_exclude}' bin/rails test"
    else
      step "Tests: Rails", "bin/rails test"
    end
    # System tests spin up a real headless-Chrome session -- too heavy for the
    # 1-vCPU VPS gate (see resource_guard.sh), but must run in local/dev CI.
    # This is also where axe-core accessibility checks live (see
    # test/application_system_test_case.rb's assert_accessible).
    step("Tests: System (a11y)", "bin/rails test:system") unless vps_host
    seed_env = vps_host ? "env RAILS_ENV=test SKIP_BERGEN_DEMO=1" : "env RAILS_ENV=test"
    step "Tests: Seeds", "#{seed_env} bin/rails db:seed:replant"
  end
end
