# frozen_string_literal: true

require_relative "test_helper"

class TestIntentAndMemory < Minitest::Test
  def setup
    @goal = "Implement deterministic routing"
    @approach = "Move resolution to Core::Routing"
    @evidence = "Tests passing"
    @intent = Master::Core::Execution::Intent.new(
      goal: @goal,
      approach: @approach,
      evidence_summary: @evidence,
      risk: :high
    )
  end

  def test_intent_summarize
    summary = @intent.summarize
    assert_match(/Goal: #{@goal}/, summary)
    assert_match(/Approach: #{@approach}/, summary)
    assert_match(/Verified: #{@evidence}/, summary)
    assert_match(/Risk: high/, summary)
  end

  def test_intent_serialization
    hash = @intent.to_h
    assert_equal @goal, hash[:goal]
    
    restored = Master::Core::Execution::Intent.from_h(hash)
    assert_equal @goal, restored.goal
    assert_equal @approach, restored.approach
    assert_equal :high, restored.risk
  end

  def test_memory_seed_from_intent
    memory = Master::Core::Memory.new
    memory.seed_from_intent(@intent)
    
    context = memory.context
    assert context.any? { |e| e.text.include?("goal: #{@goal}") }
    assert context.any? { |e| e.text.include?("approach: #{@approach}") }
    assert context.any? { |e| e.text.include?("evidence: #{@evidence}") }
    assert_equal :high, memory.instance_variable_get(:@proof).risk
  end
end
