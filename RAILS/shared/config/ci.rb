# frozen_string_literal: true

# Run using bin/ci. Steps are named in snake_case because the name is the whole
# of what a passing step prints: `ci0 at brgen: 14 of 14 steps passed in 6m 12s`,
# with each step's output in log/ci.log (Operator::Dmesg::CiRun says why).
require "rbconfig"
require_relative "../lib/operator/ci_guard"
require_relative "../lib/operator/dmesg"

ENV["GIT_CEILING_DIRECTORIES"] ||= "/"
# Refresh by default. This was "0", and the step below only passes --update
# when it is "1", so a clean bundler-audit meant "clean against whatever
# ruby-advisory-db shipped inside the installed gem" — a sentence about the
# gem release date, not about this tree. Set it to 0 to opt out where there is
# no network.
ENV["BUNDLER_AUDIT_UPDATE"] ||= "1"
ENV["NPM_CONFIG_CACHE"] ||= File.expand_path("~/.npm")
monorepo_rails = ENV["PUB4_RAILS_ROOT"].to_s.strip
monorepo_rails = File.expand_path("../..", __dir__) if monorepo_rails.empty?
ENV["PUB4_RAILS_ROOT"] ||= monorepo_rails if File.directory?(File.join(monorepo_rails, "shared"))

vps_host = ENV["PUB4_CI_GUARD"] == "1" || File.exist?("/var/db/pub4_vps") || File.exist?("/etc/relayd.conf")

app = ENV["PUB4_CI_APP"].to_s
app = File.basename(Dir.getwd) if app.empty?
# cwd is /home/brgen/app on the VPS, so basename is "app" and --app app
# looks for RAILS/app, which is not a Rails app and has no ../shared gem.
app = File.basename(File.expand_path("..")) if app == "app"

Operator::CiGuard.run! do
  Operator::Dmesg::CiRun.run(app) do
    # On vm23 the tree is already /home/<app>/app. bin/setup's db:prepare
    # loads development configs against that tree and dies (nil configurations).
    # Test DB has its own step below; production is migrated after CI.
    if vps_host
      step "setup", "echo 'vps: skip bin/setup'"
    else
      step "setup", "bin/setup --skip-server"
    end
    css_builder = [
      ENV["PUB4_RAILS_ROOT"] && File.join(ENV["PUB4_RAILS_ROOT"], "tools", "build_all_css.rb"),
      "/home/dev/pub4/RAILS/tools/build_all_css.rb",
      File.expand_path("../..", __dir__) + "/tools/build_all_css.rb",
      File.expand_path("pub4-rails/RAILS/tools/build_all_css.rb", ENV["HOME"].to_s),
    ].compact.find { |candidate| File.readable?(candidate) }
    # A step that could not run is not a step that passed. These else branches
    # used to `echo ... skipping`, which exits 0, so a checkout missing the CSS
    # builder or a design lint reported a full green CI having measured none of
    # them. RAILS/bin/premerge's header argues exactly this and implements
    # exit-3 for it.
    if css_builder
      step "css_build", "#{RbConfig.ruby} #{css_builder} --app #{app}"
    else
      step "css_build", "echo 'tools/build_all_css.rb not found in any known location' >&2; exit 1"
    end
    pub4_lib = ENV["PUB4_RAILS_ROOT"] && File.join(ENV["PUB4_RAILS_ROOT"], "shared/lib/operator")
    pub4_lib ||= File.expand_path("../lib/operator", __dir__)
    %w[
      rhythm_lint
      fallback_drift_lint
      empty_state_lint
      adhoc_empty_lint
      chrome_i18n_lint
      dialect_token_drift_check
    ].each do |lint|
      script = File.join(pub4_lib, "#{lint}.rb")
      if File.readable?(script)
        step lint, "#{RbConfig.ruby} #{script}"
      else
        step lint, "echo '#{lint}.rb not found at #{script}' >&2; exit 1"
      end
    end
    importmap_audit = %(bundle exec #{RbConfig.ruby} -e 'require "./config/environment"; require "importmap/commands"; Importmap::Commands.start(%w[audit])')
    step("importmap_audit", importmap_audit) unless vps_host
    # Two changes, and they belong together.
    #
    # `engines` and `test`: brgen's five mountable verticals live at
    # engines/*/app, outside every root this listed, and no app's test/ was
    # linted either. Those are the directories the misindented methods were
    # found in — valid Ruby at the wrong nesting level, exactly where RuboCop
    # was not pointed.
    #
    # No `unless vps_host`: vm23 is where the deploy gate actually runs, so
    # skipping it there left the only enforcement a local bin/ci or bin/premerge
    # that nothing runs automatically. It is a source-text check needing no
    # browser and no database, so the reasons the system tests and the importmap
    # audit are skipped on the VPS do not apply to it.
    # Autocorrect first, then check. A correctable offence must never be why an
    # app does not ship: bsdports sat on a commit from 2026-08-22 until
    # 2026-09-10, 156 commits behind, because two Style/TrailingCommaInArrayLiteral
    # offences in one test file failed this step at 2m43s — after 102 tests and
    # the seeds had passed. The deploy exited before the sync, so nothing shipped
    # and nothing said why in a place anyone looked.
    #
    # `-a`, never `-A`. Safe autocorrect only touches offences RuboCop can fix
    # without changing behaviour; unsafe autocorrect rewrites semantics, which is
    # not something a deploy may decide on its own. Anything left after it — a
    # real offence, an uncorrectable one — still fails the step, so the guard is
    # intact and only the mechanical half stops blocking.
    #
    # On the VPS the correction lands in the synced live directory and not in
    # git, so the next sync restores the offence and the next deploy fixes it
    # again. That is fine for shipping and useless as a record, which is why each
    # corrected file is a `warn:` line, the one thing a passing step prints.
    #
    # The transcript goes to the app's own log/. A shared /tmp path is owned by
    # whichever app user wrote it first, so on vm23 the next app's redirect
    # failed with "Permission denied" and the shell never ran RuboCop at all.
    dirs = '$(for d in app lib config db/migrate test engines; do [ -d "$d" ] && printf "%s " "$d"; done)'
    autocorrect = "mkdir -p log; " \
                  "bundle exec rubocop --autocorrect --format quiet #{dirs} > log/rubocop-autocorrect.log 2>&1; " \
                  "git diff --name-only -- #{dirs} 2>/dev/null | " \
                  "while read -r f; do echo \"warn: rubocop autocorrected $f, not in git\"; done; true"
    step "rubocop_autocorrect", autocorrect
    rubocop = "bundle exec rubocop #{dirs}"
    step "rubocop", rubocop
    # --config, because bundler-audit reads .bundler-audit.yml from the
    # directory it runs in and no app has one: the shared ignore list sat in
    # this directory with no reader, so an entry in it changed nothing and
    # looked like it had. __dir__ resolves in both tree shapes — RAILS/shared
    # in the monorepo, /home/<app>/shared on the box.
    audit = "bundle exec bundler-audit check --config #{File.join(__dir__, 'bundler-audit.yml')}"
    audit += " --update" if ENV["BUNDLER_AUDIT_UPDATE"] == "1"
    step "bundler_audit", audit
    step "brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
    step "test_db_prepare", "env RAILS_ENV=test bin/rails db:test:prepare"
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
      step "rails_test", "env DEFAULT_TEST='#{test_glob}' DEFAULT_TEST_EXCLUDE='#{test_exclude}' bin/rails test"
    else
      step "rails_test", "bin/rails test"
    end
    # System tests spin up a real headless-Chrome session -- too heavy for the
    # 1-vCPU VPS gate (see resource_guard.sh), but must run in local/dev CI.
    # This is also where axe-core accessibility checks live (see
    # test/application_system_test_case.rb's assert_accessible).
    step("system_test", "bin/rails test:system") unless vps_host
    seed_env = vps_host ? "env RAILS_ENV=test SKIP_BERGEN_DEMO=1" : "env RAILS_ENV=test"
    # bin/rake, not bin/rails.
    #
    # Both run the same task, but bin/rails routes through railties' command
    # dispatch, which globs every command file and requires them inside a rescue.
    # On vm23 that lookup fails with "[WARNING] Could not load command
    # rails/commands/rake/rake_command. Error: uninitialized constant
    # Encoding::UTF_8" and then dies on "undefined method 'perform' for nil",
    # because find_by_namespace("rake") returned nothing. The seed step is the LAST
    # thing bin/ci runs, so this blocked every brgen deploy while the suite above it
    # read green -- exactly the trap the seed-failure note warns about.
    #
    # Isolated rather than guessed: rake 13.4.2 is in the bundle; on the box
    # `bundle exec ruby -e 'require "rake"; puts Encoding::UTF_8'` prints UTF-8;
    # locally `rails -T` lists all 156 tasks. Bundle fine, rake fine, constant fine
    # -- only the dispatch is broken, and only there. Going straight to rake does
    # not touch it.
    step "seeds", "#{seed_env} bin/rake db:seed:replant"
  end
end
