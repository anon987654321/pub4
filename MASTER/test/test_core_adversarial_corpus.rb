# frozen_string_literal: true

require_relative "test_helper"

class TestAdversarialRegressionCorpus < Minitest::Test
  def setup
    @corpus = Master::Core::Execution::AdversarialRegressionCorpus.new
  end

  def test_record_failure
    episode = Struct.new(:id, :intent, :outcome, :verification).new(
      "ep-123", "fix bug", :failed, [Struct.new(:kind).new(:test_pass)]
    )
    @corpus.record_failure(episode)
    assert_equal 1, @corpus.cases.length
    assert_equal "ep-123", @corpus.cases.first[:id]
  end

  def test_regression_detection
    @corpus.cases << { id: "reg-1", failure_signature: :timeout }

    # Clean evidence
    assert @corpus.check_for_regressions([:test_pass]).ok?

    # Regressive evidence
    result = @corpus.check_for_regressions([:test_pass, :timeout])
    refute result.ok?
    assert_match(/regression detected/, result.message)
  end
end
