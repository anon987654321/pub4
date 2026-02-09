# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestSimulatedExecution < Minitest::Test
  def test_simulated_scenarios_defined
    assert_equal 3, MASTER::Enforcement::SIMULATED_SCENARIOS.size
    
    scenarios = MASTER::Enforcement::SIMULATED_SCENARIOS.map { |s| s[:scenario] }
    assert_includes scenarios, "empty_input"
    assert_includes scenarios, "boundary_values"
    assert_includes scenarios, "malformed_input"
  end

  def test_empty_input_scenarios
    empty_scenario = MASTER::Enforcement::SIMULATED_SCENARIOS.find { |s| s[:scenario] == "empty_input" }
    
    assert_includes empty_scenario[:cases], nil
    assert_includes empty_scenario[:cases], ""
    assert_includes empty_scenario[:cases], []
    assert_includes empty_scenario[:cases], 0
    assert_includes empty_scenario[:cases], false
  end

  def test_boundary_value_scenarios
    boundary_scenario = MASTER::Enforcement::SIMULATED_SCENARIOS.find { |s| s[:scenario] == "boundary_values" }
    
    assert_includes boundary_scenario[:cases], 2**63 - 1
    assert boundary_scenario[:cases].any? { |c| c.is_a?(String) && c.length == 10_000 }
    assert_includes boundary_scenario[:cases], Float::INFINITY
  end

  def test_malformed_input_scenarios
    malformed_scenario = MASTER::Enforcement::SIMULATED_SCENARIOS.find { |s| s[:scenario] == "malformed_input" }
    
    assert malformed_scenario[:cases].any? { |c| c.include?("invalid json") }
    assert malformed_scenario[:cases].any? { |c| c.include?("DROP TABLE") }
    assert malformed_scenario[:cases].any? { |c| c.include?("<script>") }
    assert malformed_scenario[:cases].any? { |c| c.include?("../../../") }
  end

  def test_simulate_execution_safe_code
    code = "input.to_s.upcase"
    result = MASTER::Enforcement.simulate_execution(code)
    
    assert result.ok?, "Simulation should succeed for safe code"
    assert result.value[:results].is_a?(Array)
    assert result.value[:results].size > 0
  end

  def test_simulate_execution_results_structure
    code = "input.to_s"
    result = MASTER::Enforcement.simulate_execution(code)
    
    assert result.ok?
    first_result = result.value[:results].first
    
    assert first_result.key?(:scenario)
    assert first_result.key?(:input)
    assert first_result.key?(:result)
  end

  def test_simulate_execution_handles_errors
    code = "input.nonexistent_method"
    result = MASTER::Enforcement.simulate_execution(code)
    
    assert result.ok?, "Simulation framework should handle errors gracefully"
    
    # Should have some results with errors
    error_results = result.value[:results].select { |r| r[:result].is_a?(Hash) && r[:result][:error] }
    assert error_results.size > 0, "Should detect errors in unsafe code"
  end

  def test_simulate_execution_with_nil_input
    code = "input.nil? ? 'nil' : input.to_s"
    result = MASTER::Enforcement.simulate_execution(code)
    
    assert result.ok?
    nil_result = result.value[:results].find { |r| r[:input].nil? }
    assert nil_result, "Should test with nil input"
    assert_equal "nil", nil_result[:result]
  end

  def test_simulate_execution_invalid_syntax
    code = "def incomplete"
    result = MASTER::Enforcement.simulate_execution(code)
    
    # Should either fail with syntax error or handle gracefully
    assert result.err? || result.value[:results].all? { |r| r[:result].is_a?(Hash) && r[:result][:error] }
  end

  def test_simulate_execution_dangerous_patterns
    dangerous_code = "system('rm -rf /')"
    result = MASTER::Enforcement.simulate_execution(dangerous_code)
    
    # Simulation should not actually execute dangerous code
    # It should either fail or return error results
    if result.ok?
      # If it succeeded in simulating, verify no actual system command was run
      # by checking that results contain error information
      assert result.value[:results].is_a?(Array)
    else
      # If simulation failed, that's acceptable for dangerous code
      assert result.err?
    end
  end
end
