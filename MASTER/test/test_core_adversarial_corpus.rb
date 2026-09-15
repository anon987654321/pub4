# frozen_string_literal: true

require "minitest/autorun"
# Base module setup
module Master
  class Result
    def self.ok(val = true)
      res = Struct.new(:ok?, :value, :category).new(true, val, nil)
      res
    end
    def self.err(msg, category: :error)
      res = Struct.new(:ok?, :value, :category).new(false, msg, category)
      res
    end
  end
  module Core; module Execution; end; end
end

require_relative "../lib/core/execution/bench/adversarial_regression_corpus"

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
    assert_match(/regression detected/, result.value)
  end
end
