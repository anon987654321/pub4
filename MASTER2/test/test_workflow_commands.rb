# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestWorkflowCommands < Minitest::Test
  def setup
    @session = MASTER::Session.current
  end

  def test_workflow_engine_starts_workflow
    result = MASTER::WorkflowEngine.start_workflow(@session)
    
    assert result.ok?, "Starting workflow should succeed"
    assert @session.metadata[:workflow], "Session should have workflow data"
    assert_equal :discover, @session.metadata[:workflow][:current_phase]
  end

  def test_workflow_current_phase
    MASTER::WorkflowEngine.start_workflow(@session)
    phase = MASTER::WorkflowEngine.current_phase(@session)
    
    assert_equal :discover, phase, "Initial phase should be discover"
  end

  def test_workflow_commands_module_exists
    assert defined?(MASTER::Commands::WorkflowCommands), "WorkflowCommands module should exist"
  end

  def test_workflow_status_method_exists
    assert_respond_to MASTER::Commands, :workflow_status
  end

  def test_workflow_advance_method_exists
    assert_respond_to MASTER::Commands, :workflow_advance
  end

  def test_workflow_status_returns_error_without_workflow
    @session.metadata[:workflow] = nil
    result = MASTER::Commands.workflow_status
    
    refute result.ok?, "Should error when workflow not started"
    assert_match(/not started/, result.error)
  end
end
