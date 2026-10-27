# frozen_string_literal: true

require_relative "test_helper"
require_relative "../checks/support/bounded_command"

class TestBoundedCommand < Minitest::Test
  def test_success_returns_output_and_process_status
    output, status = BoundedCommand.capture2e(RbConfig.ruby, "-e", "print 'ok'")

    assert_equal "ok", output
    assert BoundedCommand.success?(status)
    refute BoundedCommand.timed_out?(status)
  end

  def test_timeout_is_distinct_from_a_nonzero_exit
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # A child that inherits bundler's RUBYOPT takes ~0.2s to boot; the budget lets it print first.
    output, status = BoundedCommand.capture2e(
      RbConfig.ruby, "-e", "STDOUT.write('started'); sleep 10", timeout: 1.5
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert BoundedCommand.timed_out?(status)
    refute BoundedCommand.success?(status)
    assert_includes output, "TIMEOUT after 1.5s"
    assert_includes output, "started"
    assert_operator elapsed, :<, 5
  end
end
