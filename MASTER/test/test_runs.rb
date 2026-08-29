# frozen_string_literal: true

# A test nothing runs is a test that passes forever.
#
# OPENBSD/test held four files -- gate library, health check, restore scripts,
# VPS safety gate, 80 assertions -- reachable from no entrypoint in the repo.
# They passed. They had always passed, because they had never run. bin/check's
# own comments record the same thing happening to test:subsystems, and
# TODO.md records it for four RAILS gates under
# `rails_gates_not_wired`.
#
# This asserts every test file is reachable from some entrypoint.

require "minitest/autorun"
require_relative "../tools/runs"

class TestRuns < Minitest::Test
  def self.report = @report ||= Pub4::Runs.run

  def setup
    @report = self.class.report
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
    assert_includes Pub4::Runs.who_runs("MASTER/test/test_runs.rb"), "MASTER/Rakefile"
    assert_empty Pub4::Runs.who_runs("MASTER/test/no_such_test.rb")
  end
end
