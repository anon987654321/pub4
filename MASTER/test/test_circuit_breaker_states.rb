# frozen_string_literal: true

require_relative "test_helper"
require "ruby_llm"

# CLAUDE_OPUS_UNIFIED_HANDOFF.md 3.2 asks for the circuit breaker's states to be
# tested, and says to check the tree rather than assume the historical shape.
# The tree checked: Stoplight is not required, declared or referenced anywhere,
# so there is no NameError hazard to repair — Master::Io::CircuitBreaker is a
# hand-rolled replacement. What was actually missing is the half the handoff
# names second. The two existing tests in test_runtime_hardening.rb cover the
# rate limiter and the per-model registry; closed -> open -> half_open -> closed
# had no test at all, so the threshold, the cooldown and the recovery were three
# unheld numbers.
class TestCircuitBreakerStates < Minitest::Test
  # A cost of zero with budget_max zero disables the budget check, leaving the
  # circuit as the only thing under test.
  def breaker(**overrides)
    Master::Io::CircuitBreaker.new(budget_max: 0, req_max: 1_000, **overrides)
  end

  # execute_with_tracking treats a failure as a config error, not a backend one,
  # when no provider key is present — so without this the breaker never opens on
  # a machine with no keys and every test below would pass for the wrong reason.
  def with_keys
    Master.stub(:any_api_key_present?, true) { yield }
  end

  def fail_once(breaker)
    breaker.call(0.0) { raise StandardError, "backend down" }
  end

  def test_a_new_breaker_is_closed
    assert_equal :closed, breaker.state
  end

  def test_failures_below_the_threshold_do_not_open_it
    circuit = breaker
    with_keys { (Master::Io::CircuitBreaker::FAILURE_THRESHOLD - 1).times { fail_once(circuit) } }

    assert_equal :closed, circuit.state
  end

  def test_the_threshold_opens_it_and_the_block_stops_being_called
    circuit = breaker
    with_keys { Master::Io::CircuitBreaker::FAILURE_THRESHOLD.times { fail_once(circuit) } }

    assert_equal :open, circuit.state

    called = false
    result = circuit.call(0.0) { called = true }

    refute called, "an open circuit still ran the block"
    assert_equal :infrastructure, result.category
    assert_match(/circuit open/, result.message)
  end

  def test_a_success_resets_the_failure_count
    circuit = breaker
    with_keys do
      (Master::Io::CircuitBreaker::FAILURE_THRESHOLD - 1).times { fail_once(circuit) }
      circuit.call(0.0) { Master::Result.ok("fine") }
      (Master::Io::CircuitBreaker::FAILURE_THRESHOLD - 1).times { fail_once(circuit) }
    end

    assert_equal :closed, circuit.state
  end

  # The cooldown is wall time. Reaching in to move @opened_at back is the only
  # way to cross it without sleeping COOLDOWN_S seconds in the suite.
  def age_past_cooldown(circuit)
    opened_at = circuit.instance_variable_get(:@opened_at)
    circuit.instance_variable_set(:@opened_at, opened_at - Master::Io::CircuitBreaker::COOLDOWN_S - 1)
  end

  def test_the_cooldown_admits_one_trial_call_and_success_closes_it
    circuit = breaker
    with_keys { Master::Io::CircuitBreaker::FAILURE_THRESHOLD.times { fail_once(circuit) } }
    age_past_cooldown(circuit)

    called = false
    result = circuit.call(0.0) { called = true; Master::Result.ok("recovered") }

    assert called, "the trial call after cooldown never reached the block"
    assert_predicate Master::Result.wrap(result), :ok?
    assert_equal :closed, circuit.state
  end

  def test_a_failed_trial_call_leaves_it_out_of_closed
    circuit = breaker
    with_keys { Master::Io::CircuitBreaker::FAILURE_THRESHOLD.times { fail_once(circuit) } }
    age_past_cooldown(circuit)
    with_keys { fail_once(circuit) }

    refute_equal :closed, circuit.state, "one failed trial call closed the circuit"
  end

  # Infrastructure noise the caller is expected to retry through must not be
  # spent as one of the eight failures that open the circuit.
  def test_a_provider_rate_limit_does_not_open_it
    circuit = breaker
    with_keys do
      (Master::Io::CircuitBreaker::FAILURE_THRESHOLD * 2).times do
        circuit.call(0.0) { raise RubyLLM::RateLimitError.new(nil, "slow down") }
      end
    end

    assert_equal :closed, circuit.state
  end

  # An absent key is a configuration problem, not a backend that fell over, so
  # it must not count toward the threshold either.
  def test_a_missing_key_does_not_open_it
    circuit = breaker
    Master.stub(:any_api_key_present?, false) do
      Master.stub(:keyless_llm_enabled?, false) do
        (Master::Io::CircuitBreaker::FAILURE_THRESHOLD * 2).times { fail_once(circuit) }
      end
    end

    assert_equal :closed, circuit.state
  end

  def test_an_open_circuit_survives_the_process_that_opened_it
    Dir.mktmpdir do |dir|
      path = File.join(dir, "circuit.yml")
      circuit = breaker(state_path: path, state_key: "model-a")
      with_keys { Master::Io::CircuitBreaker::FAILURE_THRESHOLD.times { fail_once(circuit) } }

      assert_equal :open, circuit.state

      restored = breaker(state_path: path, state_key: "model-a")

      assert_equal :open, restored.state, "a restart re-armed a circuit that was open"
    end
  end

  def test_a_restored_circuit_belongs_to_its_own_key
    Dir.mktmpdir do |dir|
      path = File.join(dir, "circuit.yml")
      circuit = breaker(state_path: path, state_key: "model-a")
      with_keys { Master::Io::CircuitBreaker::FAILURE_THRESHOLD.times { fail_once(circuit) } }

      other = breaker(state_path: path, state_key: "model-b")

      assert_equal :closed, other.state, "one model's open circuit closed the door on another"
    end
  end
end
