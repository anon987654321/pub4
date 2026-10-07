# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop"

class TestFixTerminalVocabulary < Minitest::Test
  def test_crash_and_skip_are_distinct_terminal_states
    loop = Master::Fix::FixLoop.allocate

    crash = Master::Result.err("boom", category: :crash)
    skip = Master::Result.err("no app", category: :skip)
    failed = Master::Result.err("broken", category: :provider_error)

    assert_equal :crash, loop.send(:terminal_state_for, crash)
    assert_equal :skip, loop.send(:terminal_state_for, skip)
    assert_equal :failed, loop.send(:terminal_state_for, failed)
  end
end
