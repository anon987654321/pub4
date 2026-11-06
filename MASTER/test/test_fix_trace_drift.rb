# frozen_string_literal: true

require_relative "test_helper"

# Another writer's save landing while /fix's preflight reads the tree is drift, not a defect:
# the trace is read again; drift that persists is reported and the run goes on, because the
# pass re-reads every file it repairs. Only a real failure (syntax, boot surface) refuses.
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

  def test_drift_that_persists_is_still_reported_by_the_trace
    drifted = trace("file inventory changed during preflight (added: x.rb)")

    refute traced([drifted, drifted, drifted]).clean?
  end

  def with_registry_stubs(stubs, &)
    return yield if stubs.empty?

    (name, value), *rest = stubs
    Registry.stub(name, value) { with_registry_stubs(rest, &) }
  end

  # A dry run of /fix whose preflight trace is the one given; true when the pass ran.
  def pass_ran?(result)
    ran = false
    previous = ENV.delete("MASTER_FIX_DEEP_TRACE")
    stubs = {
      first_read: ->(**) { {} }, weekly_backlog_review: ->(**) { :not_due }, steady_trace: ->(**) { result },
      structural_review: ->(**) {}, run_pass: ->(*, **) { (ran = true) && "preview" },
    }

    with_registry_stubs(stubs.to_a) do
      Registry.dispatch_fix(scanner: Object.new, fix_loop: Object.new, deliberation: nil,
                            root: Master::ROOT, bus: nil, ctx: { args: "MASTER --dry-run" })
    end
    ran
  ensure
    previous.nil? ? ENV.delete("MASTER_FIX_DEEP_TRACE") : ENV["MASTER_FIX_DEEP_TRACE"] = previous
  end

  def test_persistent_drift_alone_does_not_refuse_the_run
    drifted = trace("file inventory changed during preflight (added: x.rb)",
                    "MASTER/lib/a.rb: content differs during syntax validation")

    assert pass_ran?(drifted)
  end

  def test_drift_beside_a_real_failure_still_refuses
    mixed = trace("MASTER/lib/a.rb: changed during preflight",
                  "MASTER/lib/b.rb: syntax failed: SyntaxError: unexpected end")

    refute pass_ran?(mixed)
    refute Registry.trace_drift_only?(trace)
  end

  def test_a_real_failure_is_not_read_again
    broken = trace("MASTER/lib/a.rb: syntax failed: SyntaxError: unexpected end")

    result = traced([broken, trace])

    assert_equal ["MASTER/lib/a.rb: syntax failed: SyntaxError: unexpected end"], result.failures
  end
end
