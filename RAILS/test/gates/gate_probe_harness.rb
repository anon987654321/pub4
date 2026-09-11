# frozen_string_literal: true

# Test-side instruments for the gates that need a browser, a booted fleet or the
# deploy host.
#
# Those gates are otherwise unreachable from a bare `ruby` suite. Without Chrome
# each one reports inconclusive and returns before any judgement runs, so a test
# that only calls `.run` proves the precondition check and nothing else — and a
# test that runs the gate against a live tree and asserts "passes" proves less
# still, because it passes equally against `return ok`.
#
# The half worth testing is what the gate does with a measurement, and that half
# takes a payload. So the payload is supplied from here: a planted defect goes in,
# and the assertion is that the gate names it.
module GateProbe
  # A CDP session that answers from a block instead of a browser. The block gets
  # the JavaScript the gate would have evaluated and returns what the page would
  # have returned, so each gate's own PROBE/MEASURE/ACTIVE constant still selects
  # the answer and a gate that stops asking its own question fails here.
  class FakeCdp
    attr_reader :navigated, :presses

    def initialize(&answer)
      @answer = answer
      @navigated = []
      @presses = 0
    end

    def evaluate(js, await_promise: false)
      @answer.call(js.to_s, await_promise)
    end

    def navigate(url, settle: nil)
      @navigated << url
      url
    end

    def press(_key) = @presses += 1
    def viewport(*, **) = nil
    def headers(*) = nil
    def clear_cookies = nil
    def status = 200
  end

  # Swap a constant for the duration of the block.
  #
  # Every one of these gates resolves its paths into a constant at load time, so
  # a fixture tree is only reachable this way. Deliberately not a second `root:`
  # keyword on each gate: a parameter that exists for the tests is a second code
  # path, and the gate would then be proved on a path production never takes.
  def with_const(owner, name, value)
    present = owner.const_defined?(name, false)
    previous = owner.const_get(name, false) if present
    owner.send(:remove_const, name) if present
    owner.const_set(name, value)
    yield
  ensure
    owner.send(:remove_const, name) if owner.const_defined?(name, false)
    owner.const_set(name, previous) if present
  end

  # name => callable. Replaces singleton methods for the duration of the block
  # and restores them afterwards, so one test's stubbed browser cannot leak into
  # the next file's measurement.
  def with_methods(owner, replacements)
    singleton = owner.singleton_class
    replacements.each_key { |name| singleton.send(:alias_method, saved(name), name) }
    replacements.each { |name, impl| singleton.send(:define_method, name, &impl) }
    yield
  ensure
    replacements.each_key do |name|
      next unless singleton.method_defined?(saved(name)) || singleton.private_method_defined?(saved(name))

      singleton.send(:alias_method, name, saved(name))
      singleton.send(:remove_method, saved(name))
    end
  end

  def saved(name) = :"gate_probe_original_#{name}"

  # The four states a gate can report, asked of the result rather than re-derived
  # from its three lists — GateResult#outcome is the one place they are ranked.
  def assert_inconclusive(result, matching)
    assert_equal :inconclusive, result.outcome,
                 "a gate that measured nothing must not report #{result.outcome}: " \
                 "#{(result.failures + result.unchecked).join(' | ')}"
    assert_match matching, result.unchecked.join(" | ")
  end

  def assert_names_defect(result, matching)
    assert_equal :failed, result.outcome, "planted defect went unnamed; gate said #{result.outcome}"
    assert_match matching, result.failures.join(" | ")
  end

  def assert_clean(result)
    assert_equal :passed, result.outcome,
                 "a clean measurement must pass: #{(result.failures + result.unchecked).join(' | ')}"
  end
end
