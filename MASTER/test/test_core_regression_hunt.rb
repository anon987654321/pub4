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
require_relative "../lib/core/execution/bench/traps/regression_trap"

class TestRegressionHunt < Minitest::Test
  def setup
    @corpus = Master::Core::Execution::AdversarialRegressionCorpus.new
  end

  def test_trap_detection
    # 1. Setup a known failure in the corpus
    failure_sig = :false_completion
    @corpus.cases << { id: "fail-001", failure_signature: failure_sig }

    # 2. Create a trap that produces this signature
    trap = Master::Core::Execution::RegressionTrap.new(
      id: "trap-001",
      signature: failure_sig,
      payload: [:test_pass, :false_completion]
    )

    # 3. Execute trap and verify that the corpus blocks it
    observation = trap.execute
    result = @corpus.check_for_regressions(observation)
    
    refute result.ok?, "Corpus must block a known failure signature"
    assert_match(/regression detected/, result.value)
  end

  def test_no_false_positives
    # 1. Setup a known failure
    @corpus.cases << { id: "fail-001", failure_signature: :timeout }

    # 2. Execute a "clean" trap
    clean_payload = [:test_pass, :scan_clean]
    result = @corpus.check_for_regressions(clean_payload)
    
    assert result.ok?, "Corpus should not block clean evidence"
  end
end
