# frozen_string_literal: true

require_relative "test_helper"
# Mock for StateMachine
class MockStateMachine
  attr_accessor :evidence_ledger, :episode
  def initialize
    @evidence_ledger = []
    @episode = Struct.new(:events).new([])
  end
  def all_verified? = true
end

class TestCompletionContract < Minitest::Test
  def setup
    @contract = Master::Core::Execution::CompletionContract.new
    @sm = MockStateMachine.new
  end

  def test_fails_when_empty
    assert_equal false, @contract.verify(@sm).ok?
  end

  def test_passes_when_satisfied
    # Mock a verified test_pass evidence
    evidence = Struct.new(:kind, :verified?).new(:test_pass, true)
    @sm.evidence_ledger << evidence

    # Mock a scan_clean evidence
    @sm.evidence_ledger << Struct.new(:kind, :verified?).new(:scan_clean, true)

    assert_equal true, @contract.verify(@sm).ok?
  end

  def test_fails_on_high_severity_violation
    @sm.evidence_ledger << Struct.new(:kind, :verified?).new(:test_pass, true)
    @sm.evidence_ledger << Struct.new(:kind, :verified?).new(:scan_clean, true)

    # Add a high severity violation to the episode
    @sm.episode.events << { type: "violation", severity: :high }

    assert_equal false, @contract.verify(@sm).ok?
  end
end
