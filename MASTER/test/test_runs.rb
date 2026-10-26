# frozen_string_literal: true

# A test nothing runs is a test that passes forever.
#
# OPENBSD/test held four files -- check library, health check, restore scripts,
# VPS safety check, 80 assertions -- reachable from no entrypoint in the repo.
# They passed. They had always passed, because they had never run. bin/check's
# own comments record the same thing happening to test:subsystems, and
# the old backlog records it for four RAILS checks under
# `rails_checks_not_wired`.
#
# This asserts every test file is reachable from some entrypoint.

require "minitest/autorun"
require_relative "../tools/repo/runs"

class TestRuns < Minitest::Test
  def self.report = @report ||= Operator::Runs.run

  def setup
    @report = self.class.report
  end

  def test_all_tree_survey_runs_javascript_tests_and_reports_missing_runtime
    source = File.read(File.join(Operator::Runs::ROOT, "MASTER", "Rakefile"))

    assert_includes source, 'Dir.glob(File.join(path, "**", "*.test.mjs"))'
    assert_includes source, 'system(node_bin, "--test", *tests, chdir: working_dir)'
    assert_includes source, "inconclusive <<"
    assert_includes source, "exit 3"
  end

  def test_every_declared_runner_is_a_tracked_file
    missing = Operator::Runs::RUNNERS.reject do |runner|
      File.file?(File.join(Operator::Runs::ROOT, runner))
    end

    assert_empty missing,
                 "the runner census names files that do not exist: #{missing.join(', ')}"
  end

  def test_every_test_file_is_reachable_from_an_entrypoint
    assert_empty @report[:orphans],
                 "test files no entrypoint runs. Wire them into a runner, or delete them:\n  " +
                 @report[:orphans].join("\n  ")
  end

  # Reachability is computed from glob literals in the runner files. If a rename
  # breaks the extraction, every file goes unreachable at once and the assertion
  # above fires for the wrong reason; if extraction silently returns nothing, it
  # goes quiet instead. Both need catching here.
  def test_the_index_still_finds_the_runners
    assert_operator @report[:tests], :>, 300,
                    "only #{@report[:tests]} test files found — the discovery glob stopped matching"

    reaching = @report[:runners].reject { |_, globs| globs.empty? }
    assert_operator reaching.size, :>=, 8,
                    "only #{reaching.size} runners carry globs — extraction is broken, not the repo"
  end

  def test_who_runs_answers_for_a_known_file
    assert_includes Operator::Runs.who_runs("MASTER/test/test_runs.rb"), "MASTER/Rakefile"
    assert_empty Operator::Runs.who_runs("MASTER/test/no_such_file.rb")
  end

  # STUDIO was the fourth tree and the census never looked at it: 23 test files
  # outside every question this check asks. A runner that names one file outright
  # runs it, which a glob-only extractor could not see — STUDIO's Rakefile lists
  # test_studio_check.rb by name on purpose.
  def test_every_governed_tree_contributes_tests_to_the_census
    minimums = {
      "MASTER/" => 250,
      "RAILS/" => 100,
      "OPENBSD/" => 20,
      "STUDIO/" => 15,
    }

    minimums.each do |prefix, floor|
      found = Operator::Runs.test_files.count { |path| path.start_with?(prefix) }
      assert_operator found, :>=, floor,
                      "#{prefix} contributed only #{found} test files; test discovery likely stopped matching"
    end

    assert_includes Operator::Runs.globs.keys, "STUDIO/Rakefile",
                    "the dilla and tool suites must be part of the runner census"
  end

  def test_node_and_shell_test_files_are_in_the_same_reachability_census
    targets = {
      "RAILS/master/test/face_boot.test.mjs" => "MASTER/bin/check",
      "RAILS/test/pwa_offline_store.test.mjs" => "MASTER/tools/rails/premerge.rb",
      "RAILS/test/stimulus_components_runtime_contract.test.mjs" => "MASTER/tools/rails/premerge.rb",
      "OPENBSD/test/resource_guard_test.sh" => "OPENBSD/bin/check-openbsd",
    }

    targets.each do |path, runner|
      assert_includes Operator::Runs.test_files, path, "#{path} was omitted from test discovery"
      assert_includes Operator::Runs.who_runs(path), runner,
                      "#{path} is not reachable from #{runner}"
    end

    cross_language = Operator::Runs.test_files.select do |path|
      path.end_with?(".test.mjs", "_test.sh")
    end
    assert_operator cross_language.size, :>=, 24,
                    "only #{cross_language.size} Node/shell tests are in the reachability census"
  end

  def test_studio_is_in_the_census_and_its_named_runner_counts
    studio = Operator::Runs.test_files.select { |path| path.start_with?("STUDIO/") }

    assert_operator studio.size, :>, 15, "STUDIO's suite is not being read"
    assert_includes Operator::Runs.who_runs("STUDIO/test/test_studio_check.rb"), "STUDIO/Rakefile"
    assert_includes Operator::Runs.who_runs("STUDIO/test/dilla_test.rb"), "STUDIO/Rakefile"
  end

  # What makes a file a test is the directory, not the name — three source files
  # were named like tests and one of them, tools/test_naming.rb, was reported as
  # an orphan permanently. The narrowing must not turn the check off, so both
  # directions: a lint named test_naming is not a test, and a real test a
  # runner's glob does not reach is still unreached.
  def test_the_directory_is_what_makes_a_file_a_test
    refute_includes Operator::Runs.test_files, "MASTER/tools/test_naming.rb"
    refute_includes Operator::Runs.test_files, "MASTER/lib/review/scan/self_test.rb"
    assert_includes Operator::Runs.who_runs("MASTER/test/deep/nested/test_orphan.rb"), "MASTER/Rakefile",
                    "the Rakefile globs test/** recursively, so a nested test runs"
    assert_empty Operator::Runs.who_runs("MASTER/deep/nested/test_orphan.rb"),
                 "a test-named file outside any runner's directory is still unreached"
  end
end
