# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../lib/master"

class TestEvolveStaged < Minitest::Test
  def setup
    FileUtils.mkdir_p("tmp")
  end

  def test_evolve_default_behavior_unchanged
    # Default initialization should not use staging
    evolve = MASTER::Evolve.new
    
    # Should have instance variable for staged
    assert_respond_to evolve, :instance_variable_get
    assert_equal false, evolve.instance_variable_get(:@staged)
  end

  def test_evolve_staged_parameter
    evolve = MASTER::Evolve.new(staged: true)
    
    assert_equal true, evolve.instance_variable_get(:@staged)
  end

  def test_evolve_validation_command_parameter
    evolve = MASTER::Evolve.new(validation_command: "ruby -w -c")
    
    assert_equal "ruby -w -c", evolve.instance_variable_get(:@validation_command)
  end

  def test_evolve_with_staging_routes_through_staging
    skip "Requires full Chamber/LLM setup"
    
    # This test would verify that when staged: true,
    # file modifications go through Staging.staged_modify
    # But it requires mocking LLM and Chamber which is complex
  end
end
