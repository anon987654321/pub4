# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/pipeline/proof/rails_apps"

# A pass that changed a Rails app is proved in that app: it boots, and the tests that name what changed pass.
class TestProofRailsApps < Minitest::Test
  Apps = Master::CLI::Pipeline::Proof::RailsApps
  ROOT = Master::REPO_ROOT

  def owners(path) = Apps.apps_for([path], repo_root: ROOT).keys.sort

  def test_a_path_is_proved_in_the_app_that_loads_it
    assert_equal %w[brgen], owners("RAILS/brgen/app/models/bookmark.rb")
    assert_equal %w[brgen], owners("RAILS/brgen_dating/app/models/dating/daily_pick.rb")
    assert_equal Master::Fix::RailsApp.named_apps(repo_root: ROOT).sort, owners("RAILS/__shared/app/models/x.rb")
    assert_empty owners("RAILS/apps.yml")
  end

  def test_the_tests_are_the_own_test_and_those_naming_the_constant
    tests = Apps.tests_for("brgen", ["RAILS/brgen/app/models/bookmark.rb"], repo_root: ROOT)

    assert_includes tests, "test/models/bookmark_test.rb"
    assert(tests.none? { |test| test.match?(%r{/(?:system|dummy|fixtures)/}) })
  end

  def test_an_app_that_never_eager_loads_is_proved_to_boot_instead
    assert_equal "boots and eager-loads", Apps.boot_check(File.join(ROOT, "RAILS", "brgen")).first
    assert_equal "boots", Apps.boot_check(File.join(ROOT, "RAILS", "master")).first
  end

  # Each app is its own suite, so the judge names its failures against the baseline.
  def test_an_app_failure_is_named_in_the_reading
    out = ["proof suite brgen: FAIL", "brgen: boots and eager-loads: ok", "  1) Failure:",
           "BookmarkTest#test_belongs_to_user [test/models/bookmark_test.rb:9]:", "2 runs, 3 assertions, 1 failures"]

    reading = Master::CLI::Pipeline::Proof::Reading.parse(false, out)

    assert_includes reading.failing, "BookmarkTest#test_belongs_to_user"
  end
end
