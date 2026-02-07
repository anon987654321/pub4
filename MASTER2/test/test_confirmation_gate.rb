# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestConfirmationGate < Minitest::Test
  def setup
    # Reset auto_confirm before each test
    MASTER::ConfirmationGate.auto_confirm = false
  end

  def test_gate_with_auto_confirm
    MASTER::ConfirmationGate.auto_confirm = true
    
    executed = false
    result = MASTER::ConfirmationGate.gate("Test Operation") do
      executed = true
      "success"
    end
    
    assert result.ok?
    assert executed
    assert_equal "success", result.value[:result]
  end

  def test_gate_requires_block
    result = MASTER::ConfirmationGate.gate("Test Operation")
    
    refute result.ok?
    assert_match(/No block/, result.error)
  end

  def test_gate_with_description
    MASTER::ConfirmationGate.auto_confirm = true
    
    result = MASTER::ConfirmationGate.gate(
      "Test Operation",
      description: "This is a test"
    ) { "done" }
    
    assert result.ok?
  end

  def test_gate_handles_errors
    MASTER::ConfirmationGate.auto_confirm = true
    
    result = MASTER::ConfirmationGate.gate("Test Operation") do
      raise "Something went wrong"
    end
    
    refute result.ok?
    assert_match(/failed/, result.error)
  end

  def test_stage_class_exists
    stage = MASTER::ConfirmationGate::Stage.new("Test", description: "Test stage")
    assert_respond_to stage, :call
  end

  def test_stage_call_with_auto_confirm
    MASTER::ConfirmationGate.auto_confirm = true
    
    stage = MASTER::ConfirmationGate::Stage.new("Test")
    result = stage.call({ data: "test" })
    
    assert result.ok?
    assert_equal({ data: "test" }, result.value[:result])
  end
end
