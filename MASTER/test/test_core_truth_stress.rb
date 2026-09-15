# frozen_string_literal: true

require "minitest/autorun"
module Master
  class Result
    def self.ok(val = true); Struct.new(:ok?, :value, :category).new(true, val, nil); end
    def self.err(msg, category: :error); Struct.new(:ok?, :value, :category).new(false, msg, category); end
  end
  module Core; module Execution; end; end
end

require_relative "../lib/core/execution/truth/layer"
require_relative "../lib/core/execution/completion_contract"



# Mock StateMachine for the contract check
class MockStateMachine
  attr_reader :evidence_ledger, :episode
  def initialize
    @evidence_ledger = []
    @episode = Struct.new(:events).new([])
  end
  def all_verified? = true
end

class TestTruthStress < Minitest::Test
  def setup
    @truth = Master::Core::Execution::TruthLayer.new
    @contract = Master::Core::Execution::CompletionContract.new
    @sm = MockStateMachine.new
  end

  def test_block_simulated_completion
    # Case: Model claims a fix, but evidence is missing or unverified
    observation = "Tests passed (simulated)"
    # We provide an evidence chain that is NOT verified
    evidence = Struct.new(:verified?).new(false)
    
    result = @truth.process(observation, evidence)
    refute result.ok?, "Truth Layer should reject unverified evidence"
    
    # Ensure the Completion Contract also blocks it
    # We add the unverified evidence to the ledger
    @sm.evidence_ledger << evidence
    contract_result = @contract.verify(@sm)
    refute contract_result.ok?, "Completion Contract should block missing verified evidence"
  end

  def test_block_false_success_signature
    # Case: Model uses a "Success" keyword but no actual proof
    observation = "Task completed successfully!"
    evidence = Struct.new(:verified?).new(false)
    
    result = @truth.process(observation, evidence)
    refute result.ok?, "Truth Layer must ignore semantic success claims without proof"
  end
end
