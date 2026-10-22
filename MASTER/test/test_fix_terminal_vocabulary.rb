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

    protocol = Master::Fix::Protocol::TERMINAL_STATES
    assert_includes protocol, "CRASH"
    assert_includes protocol, "SKIP"
  end

  def test_failed_verification_outcomes_never_map_to_done
    loop = Master::Fix::FixLoop.allocate

    %i[provider_error validation infrastructure policy timeout crash].each do |category|
      result = Master::Result.err("verification failed", category:)

      refute_equal :done, loop.send(:terminal_state_for, result), "#{category} must not report DONE"
    end
  end
end
