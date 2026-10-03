# frozen_string_literal: true

require "minitest/autorun"

# `bin/rails test` and the VPS gate must agree about what the suite is.
#
# Rails globs test/**/*_test.rb from the app root, which never reached the
# mountable verticals under engines/*/test. shared/config/ci.rb sets
# DEFAULT_TEST/DEFAULT_TEST_EXCLUDE so the box runs them; nothing set it locally,
# so the local command was the weaker one and reported the smaller number.
#
# It has bitten twice. ci.rb's comment records four engine tests rotting into
# NameErrors on a stale route helper while CI stayed green. On 2026-08-10 a
# validation-i18n change broke two takeaway engine tests, three sessions reported
# "brgen green" from the narrow command, and the VPS gate caught it — 349 runs
# locally against CI's 381, and a blocked deploy.
#
# brgen sets the same globs in config/application.rb now. This asserts the two
# stay equal, because the failure mode is silent in the direction that matters:
# a narrower local glob still passes, just over less.
class TestScopeParityTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CI = File.join(ROOT, "shared", "config", "ci.rb")

  # Apps that carry mountable engines. Only these need the wider glob; the others
  # have no engines/ directory and Rails' default already covers them.
  def apps_with_engines
    @apps_with_engines ||= Dir.glob(File.join(ROOT, "*", "engines", "*", "test")).map { |p|
      p.delete_prefix("#{ROOT}/").split("/").first
    }.uniq.sort
  end

  def ci_source = @ci_source ||= File.read(CI)

  def ci_glob(name)
    ci_source[/#{name}\s*=\s*"([^"]+)"/, 1]
  end

  def test_ci_still_widens_the_glob_for_engines
    assert_equal "{test,engines/*/test}/**/*_test.rb", ci_glob("test_glob"),
                 "ci.rb no longer widens DEFAULT_TEST — if the shape changed, application.rb must follow"
    assert_equal "{test,engines/*/test}/{system,dummy,fixtures}/**/*_test.rb", ci_glob("test_exclude"),
                 "ci.rb's exclude changed shape; the app-local default must match it"
  end

  def test_every_app_with_engines_matches_cis_scope_locally
    refute_empty apps_with_engines, "no app has engines/*/test — this check has stopped measuring anything"

    mismatched = apps_with_engines.reject do |app|
      config = File.read(File.join(ROOT, app, "config", "application.rb"))
      config.include?(ci_glob("test_glob")) && config.include?(ci_glob("test_exclude"))
    end

    assert_empty mismatched,
                 "these apps have engine tests that `bin/rails test` does not run, while CI does — " \
                 "set DEFAULT_TEST/DEFAULT_TEST_EXCLUDE in config/application.rb to ci.rb's values"
  end

  # The number is the thing that misled three sessions, so assert on files rather
  # than on prose: the wide glob must actually find more than the narrow one.
  def test_the_wider_glob_finds_engine_tests_the_narrow_one_misses
    apps_with_engines.each do |app|
      Dir.chdir(File.join(ROOT, app)) do
        narrow = Dir.glob("test/**/*_test.rb")
        wide = Dir.glob("{test,engines/*/test}/**/*_test.rb")
             .reject { |f| File.fnmatch?("{test,engines/*/test}/{system,dummy,fixtures}/**/*_test.rb", f, File::FNM_EXTGLOB) }

        missed = wide - narrow
        refute_empty missed,
                     "#{app} has engines/*/test but the wide glob finds nothing extra — check the glob, not the tree"
      end
    end
  end
end
