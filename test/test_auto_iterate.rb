require 'minitest/autorun'
require_relative '../lib/auto_iterate'
require_relative '../lib/engine'

class TestAutoIterate < Minitest::Test
  def test_initialization
    iterator = MASTER::AutoIterate.new(max_iterations: 5, max_time: 60)
    
    assert_equal 5, iterator.instance_variable_get(:@max_iterations)
    assert_equal 60, iterator.instance_variable_get(:@max_time)
    assert_equal 0, iterator.iterations
    assert_empty iterator.scores
  end

  def test_convergence_detection_with_zero_scores
    iterator = MASTER::AutoIterate.new(convergence_window: 3)
    
    # Test that division by zero is handled
    iterator.instance_variable_set(:@scores, [0, 0, 0, 0])
    
    # Should not raise error
    assert_nothing_raised do
      iterator.send(:converged?)
    end
  end

  def test_convergence_threshold
    iterator = MASTER::AutoIterate.new(convergence_threshold: 0.01, convergence_window: 3)
    
    # Small improvements should converge
    iterator.instance_variable_set(:@scores, [90, 90.5, 90.6, 90.65])
    
    converged = iterator.send(:converged?)
    assert converged
  end

  def test_no_convergence_with_large_improvements
    iterator = MASTER::AutoIterate.new(convergence_threshold: 0.01, convergence_window: 3)
    
    # Large improvements should not converge
    iterator.instance_variable_set(:@scores, [70, 80, 90, 95])
    
    converged = iterator.send(:converged?)
    refute converged
  end

  def test_iteration_result
    result = MASTER::IterationResult.new(
      number: 1,
      score: 85,
      improvements: 3,
      files_changed: ['file1.rb', 'file2.rb'],
      elapsed_time: 10.5
    )
    
    assert_equal 1, result.number
    assert_equal 85, result.score
    assert_equal 3, result.improvements
    assert_equal 2, result.files_changed.size
  end
end
