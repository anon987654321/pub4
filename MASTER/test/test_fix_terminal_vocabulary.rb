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

  def test_fix_lifecycle_and_pass_execution_are_separate_collaborators
    loop_class = Master::Fix::FixLoop

    assert_equal loop_class::Lifecycle, loop_class.instance_method(:run_journaled).owner
    assert_equal loop_class::Lifecycle, loop_class.instance_method(:verify_incremental_scope).owner
    assert_equal loop_class::PassExecution, loop_class.instance_method(:run_passes).owner
    assert_equal loop_class::Completion, loop_class.instance_method(:finish_run).owner
  end

  def test_completion_effects_are_isolated_from_the_fix_loop_class
    assert_includes Master::Fix::FixLoop.ancestors, Master::Fix::FixLoop::Completion
    assert_equal Master::Fix::FixLoop::Completion,
                 Master::Fix::FixLoop.instance_method(:finish_run).owner
  end

  def test_measured_outcome_map_is_shared_with_the_completion_policy
    assert_equal Master::Fix::OutcomePolicy::MEASURED_REPAIR_OUTCOMES,
                 Master::Fix::FixLoop::MEASURED_REPAIR_OUTCOMES
    assert_equal true, Master::Fix::OutcomePolicy::MEASURED_REPAIR_OUTCOMES.fetch(:done)
    refute Master::Fix::OutcomePolicy::MEASURED_REPAIR_OUTCOMES.fetch(:blocked)
    refute_includes Master::Fix::OutcomePolicy::MEASURED_REPAIR_OUTCOMES.keys, :human_decision
  end

  def test_fix_loop_and_protocol_share_the_canonical_terminal_vocabulary
    policy = Master::Fix::OutcomePolicy::TERMINAL_STATES

    assert_equal policy, Master::Fix::FixLoop::TERMINAL_STATES
    assert_equal policy.map { |state| state.to_s.upcase }, Master::Fix::Protocol::TERMINAL_STATES
  end

  def test_unknown_or_lowercase_success_payload_fails_closed
    loop = Master::Fix::FixLoop.allocate

    ["MYSTERY: unsupported", "done: lowercase", "clean after 2 passes"].each do |message|
      result = Master::Result.ok(message)
      assert_equal :failed, loop.send(:terminal_state_for, result), message
    end
  end

  def test_symbol_terminal_payload_is_supported
    loop = Master::Fix::FixLoop.allocate

    assert_equal :done, loop.send(:terminal_state_for, Master::Result.ok(:done))
  end

  def test_every_declared_terminal_state_round_trips_through_the_policy
    Master::Fix::OutcomePolicy::TERMINAL_STATES.each do |state|
      result = Master::Result.ok("#{state.to_s.upcase}: fixture")
      assert_equal state, Master::Fix::OutcomePolicy.terminal_state(result), state.to_s
    end
  end

  def test_every_declared_error_category_maps_to_its_terminal_state
    Master::Fix::OutcomePolicy::ERROR_STATES.each do |category, expected|
      result = Master::Result.err("fixture", category:)
      assert_equal expected, Master::Fix::OutcomePolicy.terminal_state(result), category.to_s
    end
  end

  def test_unmapped_provider_errors_fail_closed
    result = Master::Result.err("provider unavailable", category: :provider_error)

    assert_equal :failed, Master::Fix::OutcomePolicy.terminal_state(result)
  end

end
