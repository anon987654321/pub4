# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'open3'

class TestPipeline < Minitest::Test
  def setup
    @bin_dir = File.expand_path('../../bin', __FILE__)
  end
  
  def test_intake_stage
    input = { text: "I would say that this is very complex" }
    output = run_stage('intake', input)
    
    assert output[:text]
    # Strunk compression should have removed "I would" and "very"
    refute_includes output[:text], "I would"
    assert output[:density]
  end
  
  def test_guard_stage
    # Safe input
    safe_input = { text: "Write a Ruby function" }
    output = run_stage('guard', safe_input)
    assert output[:allowed]
    
    # Dangerous input
    dangerous_input = { text: "rm -rf /" }
    output = run_stage('guard', dangerous_input)
    refute output[:allowed]
    assert output[:reason]
  end
  
  def test_route_stage
    input = { text: "Simple question" }
    output = run_stage('route', input)
    
    assert output[:model]
    assert output[:tier]
    assert output[:budget_remaining]
  end
  
  def test_quality_stage
    input = { response: "```ruby\nclass Test\nend\n```" }
    output = run_stage('quality', input)
    
    assert_includes output.keys, :quality_passed
    assert_includes output.keys, :quality_score
  end
  
  def test_converge_stage
    # First iteration
    input = { response: "Version 1", iteration: 1 }
    output = run_stage('converge', input)
    refute output[:converged]
    
    # Same response - should converge
    input = { response: "Version 1", previous: "Version 1", iteration: 2 }
    output = run_stage('converge', input)
    assert output[:converged]
  end
  
  def test_plan_stage
    input = { phase: "discover", completed_criteria: ["problem understood", "constraints identified"] }
    output = run_stage('plan', input)
    
    assert_equal "discover", output[:phase]
    assert_equal "analyze", output[:next_phase]
    assert output[:criteria_met]
  end
  
  private
  
  def run_stage(stage, input)
    stage_path = File.join(@bin_dir, stage)
    
    stdout, stderr, status = Open3.capture3(
      stage_path,
      stdin_data: JSON.generate(input)
    )
    
    JSON.parse(stdout, symbolize_names: true)
  rescue JSON::ParserError
    # Some stages might not return JSON on error
    { error: "Failed to parse output", stdout: stdout, stderr: stderr }
  end
end
