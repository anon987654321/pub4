# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/outcome_policy"

class TestOutcomePolicy < Minitest::Test
  Policy = Master::Fix::OutcomePolicy

  def test_terminal_state_marker_requires_known_uppercase_vocabulary
    assert_equal :done, Policy.extract_state("DONE: verified")
    assert_equal :validation_failed, Policy.extract_state("VALIDATION_FAILED: proof failed")
    assert_nil Policy.extract_state("done: lowercase")
    assert_nil Policy.extract_state("ordinary successful prose")
    assert_nil Policy.normalize_state(:mystery)
  end

  def test_result_terminal_state_handles_success_symbols_messages_and_invalid_values
    assert_equal :done, Policy.terminal_state(Master::Result.ok(:done))
    assert_equal :plateau, Policy.terminal_state(Master::Result.ok("PLATEAU: no progress"))
    assert_equal :failed, Policy.terminal_state(Master::Result.ok("MYSTERY: unknown state"))
    assert_equal :failed, Policy.terminal_state(Master::Result.ok("clean after two passes"))
    assert_equal :failed, Policy.terminal_state(Object.new)
  end

  def test_each_declared_error_category_maps_to_a_known_terminal_state
    Policy::ERROR_STATES.each do |category, expected|
      result = Master::Result.err("fixture", category:)
      assert_equal expected, Policy.terminal_state(result), category.to_s
    end

    assert_equal :failed, Policy.terminal_state(Master::Result.err("provider", category: :provider_error))
  end

  def test_workflow_outcome_matrix_distinguishes_done_partial_incomplete_and_failed
    assert_equal :done, Policy.workflow_outcome(ok: true, msg: "DONE: proved", delivered: 1, ending: :done)
    assert_equal :partial, Policy.workflow_outcome(ok: true, msg: "PLATEAU: stopped", delivered: 1, ending: :plateau)
    assert_equal :partial, Policy.workflow_outcome(ok: false, msg: "TIMEOUT: stopped", delivered: 2, ending: :timeout)
    assert_equal :incomplete, Policy.workflow_outcome(ok: true, msg: "MYSTERY: stopped", delivered: 1)
    assert_equal :incomplete, Policy.workflow_outcome(ok: true, msg: "clean after 2 passes", delivered: 0)
    assert_equal :incomplete, Policy.workflow_outcome(ok: true, msg: "clean", delivered: 1, ending: :mystery)
    assert_equal :failed, Policy.workflow_outcome(ok: false, msg: "failed", delivered: 0, ending: :failed)
  end

  def test_workflow_outcome_uses_explicit_ending_over_message
    assert_equal :partial, Policy.workflow_outcome(ok: true, msg: "DONE: message is stale", delivered: 1, ending: :timeout)
    assert_equal :done, Policy.workflow_outcome(ok: true, msg: "PLATEAU: message is stale", delivered: 1, ending: :done)
  end

  def test_halted_policy_accepts_done_only_as_success
    refute Policy.halted?(:done)
    refute Policy.halted?("DONE")
    assert Policy.halted?(:timeout)
    assert Policy.halted?(:mystery)
    refute Policy.halted?(nil)
  end

  def test_measured_outcomes_are_immutable_and_only_done_is_success
    measured = Policy::MEASURED_REPAIR_OUTCOMES

    assert_predicate measured, :frozen?
    assert_equal true, measured.fetch(:done)
    refute measured.any? { |state, ok| state != :done && ok }
    refute measured.key?(:human_decision)
  end
end
