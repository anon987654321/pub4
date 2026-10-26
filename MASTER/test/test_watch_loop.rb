# frozen_string_literal: true

require_relative "test_helper"

class TestWatchLoop < Minitest::Test
  # The platform watcher gem is absent on a Mac, so the test builds none.
  class Unwatched < Master::Fix::WatchLoop
    private

    def build_watcher = nil
  end

  class FixLoopDouble
    attr_reader :calls

    def initialize(alive:)
      @alive = alive
      @calls = []
    end

    def background_alive? = @alive
    def wake_background!(**kw) = @calls << [:wake, kw]
    def run(path, **kw) = @calls << [:run, path, kw]
  end

  # A changed file reaches FixLoop and nothing else, so its repair has a pass
  # transaction and a run ledger of its own.
  def test_a_changed_file_runs_through_fix_loop
    fix_loop = FixLoopDouble.new(alive: false)
    Unwatched.new(root: Master::ROOT, fix_loop:).send(:run_laws_on, __FILE__)

    assert_equal [[:run, __FILE__, { max_passes: 3, budget_seconds: 120, incremental: true }]], fix_loop.calls
  end

  def test_a_running_background_loop_is_woken_instead
    fix_loop = FixLoopDouble.new(alive: true)
    Unwatched.new(root: Master::ROOT, fix_loop:).send(:run_laws_on, __FILE__)

    assert_equal [[:wake, { reason: "source_changed", path: __FILE__ }]], fix_loop.calls
  end
end
