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
    assert_equal %w[amber brgen bsdports], owners("RAILS/__shared/app/models/x.rb")
    assert_equal %w[master], owners("RAILS/master/app/controllers/dashboard_controller.rb")
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

  FAILED = ["  1) Failure:", "BookmarkTest#test_belongs_to_user [test/models/bookmark_test.rb:9]:",
            "1 runs, 1 failures"].freeze

  # A failure the starting commit has too is named, not printed as a failure; a new one still fails.
  def test_a_failure_the_pass_did_not_introduce_is_not_held_against_it
    judge = ->(before) { Apps.failing_before("brgen", tests: %w[t.rb], output: FAILED, rerun: -> { before * "\n" }) }

    held, lines = judge.call(FAILED)
    refused, = judge.call(["1 runs"])

    assert held
    assert_match(/1 failing before the pass too/, lines.first)
    refute refused
  end

  def test_the_files_are_as_they_were_at_the_revision_while_the_block_runs
    Dir.mktmpdir do |repo|
      file = File.join(repo, "a.rb")
      git = ->(*args) { system("git", *args, chdir: repo, out: File::NULL, err: File::NULL) }
      git.call("init", "-q") && File.write(file, "old\n")
      git.call("add", "a.rb") && git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "a")
      File.write(file, "new\n")

      seen = Apps.at_revision(%w[a.rb], "HEAD", repo_root: repo) { File.read(file) }

      assert_equal ["old\n", "new\n"], [seen, File.read(file)]
    end
  end

  # Each app is its own suite, so the judge names its failures against the baseline.
  def test_an_app_failure_is_named_in_the_reading
    out = ["proof suite brgen: FAIL", "brgen: boots and eager-loads: ok", "  1) Failure:",
           "BookmarkTest#test_belongs_to_user [test/models/bookmark_test.rb:9]:", "2 runs, 3 assertions, 1 failures"]

    reading = Master::CLI::Pipeline::Proof::Reading.parse(false, out)

    assert_includes reading.failing, "BookmarkTest#test_belongs_to_user"
  end
end
