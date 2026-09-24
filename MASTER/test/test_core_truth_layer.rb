# frozen_string_literal: true

require_relative "test_helper"
require "digest"

class TestTruthLayer < Minitest::Test
  def setup
    @truth = Master::Core::Execution::TruthLayer.new
  end

  def test_promotion_to_truth
    # Mock a verified evidence chain
    evidence = Struct.new(:verified?).new(true)
    observation = "The file exists"

    result = @truth.process(observation, evidence)
    assert result.ok?

    fact_id = result.value
    assert @truth.true?(fact_id)
  end

  def test_refusal_of_unverified_evidence
    # Mock an unverified evidence chain
    evidence = Struct.new(:verified?).new(false)
    observation = "The file exists"

    result = @truth.process(observation, evidence)
    assert !result.ok?

    # Use the same logic as the TruthLayer for ID generation to check
    fact_id = Digest::SHA256.hexdigest(observation)[0, 12]
    refute @truth.true?(fact_id)
  end
end
