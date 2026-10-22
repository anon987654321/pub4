# frozen_string_literal: true

require_relative "test_helper"

# Another writer's save landing while /fix's preflight reads the tree is drift, not a defect:
# the trace is read again, and refuses the run only if the drift persists.
class TestFixTraceDrift < Minitest::Test
  Registry = Master::CLI::CommandRegistry
  Trace = Master::Fix::ExecutionTrace::Result

  def trace(*failures)
    Trace.new(ok: failures.empty?, files: 1, bytes: 1, ruby_files: 1, phases: {}, failures:)
  end

  def traced(results)
    queue = results.dup
    Master::Fix::ExecutionTrace.stub(:new, ->(**) { Struct.new(:result) { def run = result }.new(queue.shift) }) do
      Registry.steady_trace(scope: [], dependencies: {})
    end
  end

  def test_drift_that_settles_is_read_again_and_passes
    drifted = trace("MASTER/lib/a.rb: changed during preflight")

    assert traced([drifted, trace]).clean?
  end

  def test_drift_that_persists_still_refuses
    drifted = trace("file inventory changed during preflight (added: x.rb)")

    refute traced([drifted, drifted, drifted]).clean?
  end

  def test_a_real_failure_is_not_read_again
    broken = trace("MASTER/lib/a.rb: syntax failed: SyntaxError: unexpected end")

    result = traced([broken, trace])

    assert_equal ["MASTER/lib/a.rb: syntax failed: SyntaxError: unexpected end"], result.failures
  end
end
